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
}) async {
  final logger = AppLogger();
  final List<DiscoveredDevice> devices = [];
  final deviceMap = <String, DiscoveredDevice>{};
  MDnsClient? client;
  logTag ??= 'mDNS';

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

  try {
    client = MDnsClient(
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
    await client.start();
    await logger.info('info.standard_mdns_port', tag: logTag);
  } on SocketException catch (e) {
    if (e.osError?.errorCode == 48 || e.osError?.errorCode == 10048) {
      await logger.error(
        'errors.port_in_use',
        tag: logTag,
        params: {'port': e.port},
      );
      throw MdnsPortInUseException(
        'mDNS port ￿e.port} is in use, cannot scan for $serviceType devices',
      );
    }
    rethrow;
  } catch (e) {
    await logger.error('errors.mdns_init_error', tag: logTag, error: e);
    rethrow;
  }

  final completer = Completer<void>();
  final List<StreamSubscription> subscriptions = [];
  Timer? periodicQueryTimer;
  bool isCompleted = false;

  Future<void> sendPtrQuery() async {
    final ptrStream = client!.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer('$serviceType.local'),
    );
    final ptrSubscription = ptrStream.listen((ptr) async {
      final serviceName = ptr.domainName;
      await for (final srv in client!.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(serviceName),
      )) {
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
        await for (final ip in client.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(srv.target),
        )) {
          await for (final txt in client.lookup<TxtResourceRecord>(
            ResourceRecordQuery.text(serviceName),
          )) {
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
            if (onDeviceFound != null) {
              onDeviceFound(device);
            }
          }
        }
      }
    });
    subscriptions.add(ptrSubscription);
  }

  try {
    // 首次查詢
    await sendPtrQuery();
    // 週期性查詢
    periodicQueryTimer = Timer.periodic(sendQueryMessageInterval, (timer) {
      if (isCompleted) return;
      sendPtrQuery();
    });

    // Wait for scanDuration to complete (DLNA style)
    Future.delayed(scanDuration, () {
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await completer.future;
    } catch (e) {
      rethrow;
    }
    isCompleted = true;
    periodicQueryTimer.cancel();
    for (final sub in subscriptions) {
      await sub.cancel();
    }
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
    bool clientStopped = false;
    if (!clientStopped) {
      try {
        client.stop();
      } catch (_) {}
      clientStopped = true;
    }
    periodicQueryTimer?.cancel();
    for (final sub in subscriptions) {
      await sub.cancel();
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
  );
}

/// Scan for AirPlay RX (接收端, 如 Apple TV, 支援 AirPlay RX 的 Mac/iOS)
Future<List<DiscoveredDevice>> scanAirplayRxDevices({
  Function(DiscoveredDevice)? onDeviceFound,
  Duration scanDuration = const Duration(seconds: 5), // 改名為 scanDuration
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
  );
}

/// Scan for AirPlay TX (發射端, 如 iPhone/iPad/Mac)
Future<List<DiscoveredDevice>> scanAirplayTxDevices({
  Function(DiscoveredDevice)? onDeviceFound,
  Duration scanDuration = const Duration(seconds: 5), // 改名為 scanDuration
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
  );
}

/// 安全嘗試 bind，所有平台都先嘗試 reusePort，失敗再 fallback
Future<RawDatagramSocket> _safeBind(dynamic host, int port, {int? ttl}) async {
  try {
    // 先嘗試帶 reusePort
    return await RawDatagramSocket.bind(
      host,
      port,
      reuseAddress: true,
      reusePort: true,
      ttl: ttl ?? 1,
    );
  } catch (e) {
    // fallback: 不支援 reusePort 或權限不足
    try {
      return await RawDatagramSocket.bind(
        host,
        port,
        reuseAddress: true,
        ttl: ttl ?? 1,
      );
    } catch (e2) {
      // 針對權限錯誤給出提示
      if (e2 is SocketException && e2.osError?.errorCode == 1) {
        throw Exception(
          'Failed to bind mDNS port 5353. Please ensure you have sufficient permissions (e.g., run as root or administrator).',
        );
      }
      rethrow;
    }
  }
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
