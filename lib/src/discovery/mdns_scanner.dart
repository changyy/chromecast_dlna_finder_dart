import 'dart:async';
import 'dart:io';
import 'package:multicast_dns/multicast_dns.dart';
import 'device.dart';
import '../util/logger.dart';

/// Exception that may occur when scanning Chromecast devices in the local network
class MdnsPortInUseException implements Exception {
  final String message;
  MdnsPortInUseException([this.message = 'Port 5353 is in use']);
  @override
  String toString() => 'MdnsPortInUseException: $message';
}

/// Create an mDNS client with a socket factory that enables port reuse.
MDnsClient createMdnsClient() {
  return MDnsClient(
    rawDatagramSocketFactory: (
      dynamic host,
      int port, {
      bool? reuseAddress,
      bool? reusePort,
      int? ttl,
    }) {
      return _safeBind(host, port, ttl: ttl);
    },
  );
}

/// 共用 mDNS 掃描器
Future<List<DiscoveredDevice>> scanMdnsDevices({
  required String
  serviceType, // 例如 '_airplay._tcp', '_raop._tcp', '_googlecast._tcp'
  required String
  mdnsType, // 例如 '_airplay._tcp', '_raop._tcp', '_googlecast._tcp'
  required DiscoveredDevice Function({
    required String ip,
    required int port,
    required String serviceName,
    required Map<String, String> txtMap,
    List<String>? mdnsTypes,
  })
  deviceFactory,
  Function(DiscoveredDevice)? onDeviceFound,
  String? logTag,
  Duration sendQueryMessageInterval = const Duration(seconds: 3),
  Duration scanDuration = const Duration(seconds: 15), // 改名為 scanDuration
  bool useSystemMdns = false, // 新增參數，預設 false
  MDnsClient? sharedClient, // 可共享的 client，用於並行 mDNS 掃描
  bool stopClientOnFinish = true,
}) async {
  final logger = AppLogger();
  final List<DiscoveredDevice> devices = [];
  final deviceMap = <String, DiscoveredDevice>{};
  logTag ??= 'mDNS';
  final MDnsClient client = sharedClient ?? createMdnsClient();
  final bool ownsClient = sharedClient == null;

  // 平台判斷
  bool isApplePlatform = false;
  try {
    isApplePlatform = Platform.isIOS || Platform.isMacOS;
  } catch (_) {}

  if (useSystemMdns && isApplePlatform) {
    // TODO: 實作系統內建 mDNS 查詢
    await logger.info('info.use_system_mdns', tag: logTag);
    throw UnimplementedError('系統內建 mDNS 尚未實作，請自行擴充');
  }

  await _ensureClientStarted(client, logger, logTag);

  final completer = Completer<void>();
  final List<StreamSubscription> subscriptions = [];
  Timer? periodicQueryTimer;
  Timer? scanTimer;
  bool isCompleted = false;
  SocketException? sendPermissionError;

  // Ends the scan early, e.g. when the (shared) client was stopped elsewhere.
  void finishScan() {
    if (!completer.isCompleted) completer.complete();
  }

  // A lookup that never throws: once the scan is over or the client has been
  // stopped (by us, by another scan sharing the client, or by dispose()),
  // MDnsClient.lookup throws a StateError — synchronously, and nothing awaits
  // these nested lookups, so it used to surface as an uncaught app crash.
  Stream<T> safeLookup<T extends ResourceRecord>(ResourceRecordQuery query) {
    if (isCompleted) return const Stream.empty();
    try {
      return client.lookup<T>(query).handleError((Object e) {
        logger.debug(
          'debug.lookup_after_stop',
          tag: logTag,
          params: {'error': e.toString()},
        );
      }, test: (e) => e is StateError);
    } on StateError catch (e) {
      logger.debug(
        'debug.lookup_after_stop',
        tag: logTag,
        params: {'error': e.toString()},
      );
      _mdnsClientStarted[client] = false;
      finishScan();
      return const Stream.empty();
    } on SocketException catch (e) {
      // Sending the query failed, also synchronously (RawDatagramSocket.send):
      // "Network is unreachable" (errno 101) when Wi-Fi drops or switches
      // during a scan. From the periodic timer this crashed the app. Skip this
      // query; the next periodic query tries again.
      logger.debug(
        'debug.mdns_send_failed',
        tag: logTag,
        params: {'error': e.toString()},
      );
      if (e.osError?.errorCode == 1) {
        // No multicast permission: retrying won't help, fail the scan.
        sendPermissionError ??= e;
        finishScan();
      }
      return const Stream.empty();
    }
  }

  Future<void> resolveService(String serviceName) async {
    await for (final srv in safeLookup<SrvResourceRecord>(
      ResourceRecordQuery.service(serviceName),
    )) {
      if (isCompleted) return;
      await logger.debug(
        'debug.found_service',
        tag: logTag,
        params: {
          'target': srv.target,
          'port': srv.port,
          'priority': srv.priority,
          'weight': srv.weight,
        },
      );
      await for (final ip in safeLookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(srv.target),
      )) {
        if (isCompleted) return;
        await for (final txt in safeLookup<TxtResourceRecord>(
          ResourceRecordQuery.text(serviceName),
        )) {
          if (isCompleted) return;
          final txtMap = <String, String>{};
          final dynamic txtRaw = txt.text;
          await _parseTxtRecord(txtRaw, txtMap, logger);

          final device = deviceFactory(
            ip: ip.address.address,
            port: srv.port,
            serviceName: serviceName,
            txtMap: txtMap,
            mdnsTypes: [mdnsType],
          );
          final deviceId =
              '${mdnsType}_${(device.id ?? device.location ?? "${device.ip}_${device.name}")}';
          if (deviceMap.containsKey(deviceId)) {
            await logger.debug(
              'debug.duplicate_device',
              tag: logTag,
              params: {'id': deviceId, 'name': device.name, 'ip': device.ip},
            );
            continue;
          }
          // The scan may have finished while we were awaiting the logger.
          if (isCompleted) return;
          deviceMap[deviceId] = device;
          await logger.info(
            'info.found_device',
            tag: logTag,
            params: {
              'deviceType': device.type.toString(),
              'name': device.name,
              'ip': device.ip,
              'model': device.model,
            },
          );
          if (onDeviceFound != null && !isCompleted) {
            onDeviceFound(device);
          }
        }
      }
    }
  }

  void sendPtrQuery() {
    if (isCompleted) return;
    final ptrSubscription = safeLookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer('$serviceType.local'),
    ).listen(
      (ptr) {
        // Not awaited by anyone: every error has to be handled here.
        resolveService(ptr.domainName).catchError((Object e) {
          logger.debug(
            'debug.lookup_after_stop',
            tag: logTag,
            params: {'error': e.toString()},
          );
        });
      },
      onError: (Object e) {
        logger.debug(
          'debug.lookup_after_stop',
          tag: logTag,
          params: {'error': e.toString()},
        );
      },
    );
    subscriptions.add(ptrSubscription);
  }

  try {
    // 首次查詢
    sendPtrQuery();
    // 週期性查詢
    periodicQueryTimer = Timer.periodic(sendQueryMessageInterval, (timer) {
      if (isCompleted) {
        timer.cancel();
        return;
      }
      sendPtrQuery();
    });

    // Wait for scanDuration to complete (DLNA style)
    scanTimer = Timer(scanDuration, finishScan);

    await completer.future;
    if (sendPermissionError != null) throw sendPermissionError!;
  } catch (e) {
    if (e is SocketException && e.osError?.errorCode == 1) {
      await logger.error(
        'errors.mdns_send_permission_denied',
        tag: logTag,
        params: {'error': e.toString()},
      );
      throw Exception(
        'mDNS permission denied: unable to send multicast packets. Please ensure you have network and multicast permissions, or run as root/administrator.',
      );
    }
    await logger.error('errors.scan_failed', tag: logTag, error: e);
  } finally {
    isCompleted = true;
    periodicQueryTimer?.cancel();
    scanTimer?.cancel();
    for (final sub in subscriptions) {
      await sub.cancel();
    }
    if (stopClientOnFinish && ownsClient) {
      stopMdnsClient(client);
    }
  }
  devices.addAll(deviceMap.values);
  await logger.info(
    'info.scan_complete',
    tag: logTag,
    params: {'count': devices.length},
  );
  return devices;
}

/// Scan for Chromecast devices in the local network
/// [onDeviceFound] 回調函數，當找到新裝置時調用
Future<List<DiscoveredDevice>> scanChromecastDevices({
  Function(DiscoveredDevice)? onDeviceFound,
  Duration scanDuration = const Duration(seconds: 5), // 改名為 scanDuration
  MDnsClient? sharedClient,
  bool stopClientOnFinish = true,
}) async {
  return scanMdnsDevices(
    serviceType: '_googlecast._tcp',
    mdnsType: '_googlecast._tcp',
    deviceFactory: ({
      required String ip,
      required int port,
      required String serviceName,
      required Map<String, String> txtMap,
      List<String>? mdnsTypes,
    }) {
      return DiscoveredDevice.fromChromecast(
        ip: ip,
        port: port,
        serviceName: serviceName,
        txtMap: txtMap,
      );
    },
    onDeviceFound: onDeviceFound,
    logTag: 'mDNS',
    scanDuration: scanDuration, // 傳遞 scanDuration
    sharedClient: sharedClient,
    stopClientOnFinish: stopClientOnFinish,
  );
}

/// Scan for AirPlay RX (接收端, 如 Apple TV, 支援 AirPlay RX 的 Mac/iOS)
Future<List<DiscoveredDevice>> scanAirplayRxDevices({
  Function(DiscoveredDevice)? onDeviceFound,
  Duration scanDuration = const Duration(seconds: 5), // 改名為 scanDuration
  MDnsClient? sharedClient,
  bool stopClientOnFinish = true,
}) async {
  return scanMdnsDevices(
    serviceType: '_airplay._tcp',
    mdnsType: '_airplay._tcp',
    deviceFactory: ({
      required ip,
      required port,
      required String serviceName,
      required txtMap,
      List<String>? mdnsTypes,
    }) {
      return DiscoveredDevice.fromAirplay(
        ip: ip,
        port: port,
        serviceName: serviceName,
        txtMap: txtMap,
        mdnsTypes: mdnsTypes,
      );
    },
    onDeviceFound: onDeviceFound,
    logTag: 'mDNS',
    scanDuration: scanDuration, // 傳遞 scanDuration
    sharedClient: sharedClient,
    stopClientOnFinish: stopClientOnFinish,
  );
}

/// Scan for AirPlay TX (發射端, 如 iPhone/iPad/Mac)
Future<List<DiscoveredDevice>> scanAirplayTxDevices({
  Function(DiscoveredDevice)? onDeviceFound,
  Duration scanDuration = const Duration(seconds: 5), // 改名為 scanDuration
  MDnsClient? sharedClient,
  bool stopClientOnFinish = true,
}) async {
  return scanMdnsDevices(
    serviceType: '_companion-link._tcp',
    mdnsType: '_companion-link._tcp',
    deviceFactory: ({
      required ip,
      required port,
      required String serviceName,
      required txtMap,
      List<String>? mdnsTypes,
    }) {
      return DiscoveredDevice.fromAirplay(
        ip: ip,
        port: port,
        serviceName: serviceName,
        txtMap: txtMap,
        mdnsTypes: mdnsTypes,
      );
    },
    onDeviceFound: onDeviceFound,
    logTag: 'mDNS',
    scanDuration: scanDuration, // 傳遞 scanDuration
    sharedClient: sharedClient,
    stopClientOnFinish: stopClientOnFinish,
  );
}

/// 安全嘗試 bind，所有平台都先嘗試 reusePort，失敗再 fallback
Future<RawDatagramSocket> _safeBind(dynamic host, int port, {int? ttl}) async {
  ttl ??= 255;
  try {
    // 先嘗試帶 reusePort
    return await RawDatagramSocket.bind(
      host,
      port,
      reuseAddress: true,
      reusePort: true,
      ttl: ttl,
    );
  } catch (e) {
    // fallback: 不支援 reusePort 或權限不足
    try {
      return await RawDatagramSocket.bind(
        host,
        port,
        reuseAddress: true,
        reusePort: true,
        ttl: ttl,
      );
    } catch (_) {}

    try {
      // 嘗試僅開啟 reusePort，避免 reuseAddress 衝突
      return await RawDatagramSocket.bind(
        host,
        port,
        reuseAddress: false,
        reusePort: true,
        ttl: ttl,
      );
    } catch (e2) {
      // 針對權限錯誤給出提示
      if (e2 is SocketException && e2.osError?.errorCode == 1) {
        throw Exception(
          'Failed to bind mDNS port 5353. Please ensure you have sufficient permissions (e.g., run as root or administrator).',
        );
      }
      if (e2 is SocketException &&
          (e2.osError?.errorCode == 48 || e2.osError?.errorCode == 10048)) {
        throw MdnsPortInUseException(
          'mDNS port ${e2.port} is in use, cannot bind socket',
        );
      }
      rethrow;
    }
  }
}

/// Stop [client] and forget that it was started, so the next scan that is
/// handed this client starts it again instead of calling lookup on a stopped
/// client. Never throws.
void stopMdnsClient(MDnsClient client) {
  try {
    client.stop();
  } catch (_) {}
  _mdnsClientStarted[client] = false;
  _mdnsClientStarting[client] = null;
}

final _mdnsClientStarted = Expando<bool>();
final _mdnsClientStarting = Expando<Future<void>>();

Future<void> _ensureClientStarted(
  MDnsClient client,
  AppLogger logger,
  String logTag,
) async {
  if (_mdnsClientStarted[client] == true) return;
  if (_mdnsClientStarting[client] != null) {
    await _mdnsClientStarting[client];
    return;
  }
  final future = () async {
    try {
      await client.start();
      _mdnsClientStarted[client] = true;
      await logger.info('info.standard_mdns_port', tag: logTag);
    } on SocketException catch (e) {
      if (e.osError?.errorCode == 48 || e.osError?.errorCode == 10048) {
        await logger.error(
          'errors.port_in_use',
          tag: logTag,
          params: {'port': e.port},
        );
        throw MdnsPortInUseException(
          'mDNS port ${e.port} is in use, cannot scan for services',
        );
      }
      rethrow;
    } catch (e) {
      await logger.error('errors.mdns_init_error', tag: logTag, error: e);
      rethrow;
    } finally {
      _mdnsClientStarting[client] = null;
    }
  }();
  _mdnsClientStarting[client] = future;
  await future;
}

/// Parse TXT record, fill results into txtMap
Future<void> _parseTxtRecord(
  dynamic txtRaw,
  Map<String, String> txtMap,
  AppLogger logger,
) async {
  await logger.debug(
    'debug.txt_record_type',
    tag: 'mDNS',
    params: {'type': txtRaw.runtimeType},
  );

  if (txtRaw is String) {
    // Single string format
    final lines = txtRaw.split('\n');
    for (final line in lines) {
      final parts = line.split('=');
      if (parts.length == 2) {
        txtMap[parts[0]] = parts[1];
      }
    }
  } else if (txtRaw is Iterable) {
    // Iterable object format
    for (final item in txtRaw) {
      if (item is String) {
        final parts = item.split('=');
        if (parts.length == 2) {
          txtMap[parts[0]] = parts[1];
        }
      }
    }
  } else {
    // Other formats, try to convert to string
    await logger.debug(
      'debug.nonstandard_txt_format',
      tag: 'mDNS',
      params: {'txtRaw': txtRaw},
    );

    try {
      String textValue = txtRaw.toString();
      // Remove possible [ and ] symbols
      if (textValue.startsWith('[') && textValue.endsWith(']')) {
        textValue = textValue.substring(1, textValue.length - 1);
      }

      // Split by comma
      final parts = textValue.split(',');
      for (final part in parts) {
        final trimmed = part.trim();
        final keyValue = trimmed.split('=');
        if (keyValue.length == 2) {
          txtMap[keyValue[0].trim()] = keyValue[1].trim();
        }
      }
    } catch (e) {
      await logger.debug(
        'debug.parse_txt_record_failed',
        tag: 'mDNS',
        params: {'error': e},
      );
    }
  }

  await logger.debug('debug.txt_map', tag: 'mDNS', params: {'map': txtMap});
}
