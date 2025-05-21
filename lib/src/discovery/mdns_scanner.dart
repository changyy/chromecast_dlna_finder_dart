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

/// Scan for Chromecast devices in the local network
/// [onDeviceFound] 回調函數，當找到新裝置時調用
Future<List<DiscoveredDevice>> scanChromecastDevices({
  Function(DiscoveredDevice)? onDeviceFound,
}) async {
  final logger = AppLogger();
  await logger.info('info.start_chromecast_scan', tag: 'mDNS');
  final List<DiscoveredDevice> devices = [];
  // 使用 Map 來追蹤已發現的裝置，避免重複
  final deviceMap = <String, DiscoveredDevice>{};
  MDnsClient? client;

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
    await logger.info('info.standard_mdns_port', tag: 'mDNS');
  } on SocketException catch (e) {
    if (e.osError?.errorCode == 48 || // macOS/Linux port in use
        e.osError?.errorCode == 10048) {
      // Windows port in use
      await logger.error(
        'errors.port_in_use',
        tag: 'mDNS',
        params: {'port': e.port},
      );
      throw MdnsPortInUseException(
        'mDNS port ${e.port} is in use, cannot scan for Chromecast devices',
      );
    }
    rethrow;
  } catch (e) {
    await logger.error('errors.mdns_init_error', tag: 'mDNS', error: e);
    rethrow;
  }

  // Continue normal scanning process
  try {
    // dns-sd -B _googlecast._tcp local
    await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer('_googlecast._tcp.local'),
    )) {
      final serviceName =
          ptr.domainName; // e.g. Chromecast-XXXXXX._googlecast._tcp.local
      await for (final SrvResourceRecord srv in client
          .lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(serviceName),
          )) {
        await logger.debug(
          'debug.found_service',
          tag: 'mDNS',
          params: {
            'target': srv.target,
            'port': srv.port,
            'priority': srv.priority,
            'weight': srv.weight,
          },
        );
        await for (final IPAddressResourceRecord ip in client
            .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            )) {
          // Query TXT record
          await for (final TxtResourceRecord txt in client
              .lookup<TxtResourceRecord>(
                ResourceRecordQuery.text(serviceName),
              )) {
            final txtMap = <String, String>{};
            final dynamic txtRaw = txt.text;

            // Safely parse TXT record
            await _parseTxtRecord(txtRaw, txtMap, logger);

            // Use factory method to create device object, automatically determine Chromecast type
            final device = DiscoveredDevice.fromChromecast(
              ip: ip.address.address,
              port: srv.port,
              serviceName: serviceName,
              txtMap: txtMap,
            );

            // 取得裝置 ID，若不存在則使用 IP 與名稱組合
            final deviceId = device.id ?? '${device.ip}_${device.name}';

            // 檢查是否已經有相同裝置
            if (deviceMap.containsKey(deviceId)) {
              await logger.debug(
                'debug.duplicate_device',
                tag: 'mDNS',
                params: {'id': deviceId, 'name': device.name, 'ip': device.ip},
              );
              continue; // 跳過重複裝置
            }

            // 加入到裝置映射表
            deviceMap[deviceId] = device;

            // Display different messages based on device type
            final deviceType =
                device.isChromecastAudio ? 'Chromecast Audio' : 'Chromecast';
            await logger.info(
              'info.found_device',
              tag: 'mDNS',
              params: {
                'deviceType': deviceType,
                'name': device.name,
                'ip': device.ip,
                'model': device.model,
              },
            );

            // 調用回調函數
            if (onDeviceFound != null) {
              onDeviceFound(device);
            }
          }
        }
      }
    }
  } catch (e) {
    await logger.error('errors.chromecast_scan_failed', tag: 'mDNS', error: e);
  } finally {
    bool clientStopped = false;
    if (!clientStopped) {
      try {
        client.stop();
      } catch (_) {}
      clientStopped = true;
    }
  }

  // 從映射表中取出不重複的裝置
  devices.addAll(deviceMap.values);

  await logger.info(
    'info.chromecast_scan_complete',
    tag: 'mDNS',
    params: {'count': devices.length},
  );
  return devices;
}

/// Scan for AirPlay RX (接收端, 如 Apple TV, 支援 AirPlay RX 的 Mac/iOS)
Future<List<DiscoveredDevice>> scanAirplayRxDevices({
  Function(DiscoveredDevice)? onDeviceFound,
}) async {
  final logger = AppLogger();
  await logger.info('info.start_airplay_rx_scan', tag: 'mDNS');
  final List<DiscoveredDevice> devices = [];
  final deviceMap = <String, DiscoveredDevice>{};
  MDnsClient? client;

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
    await logger.info('info.standard_mdns_port', tag: 'mDNS');
  } on SocketException catch (e) {
    if (e.osError?.errorCode == 48 || e.osError?.errorCode == 10048) {
      await logger.error(
        'errors.port_in_use',
        tag: 'mDNS',
        params: {'port': e.port},
      );
      throw MdnsPortInUseException(
        'mDNS port ${e.port} is in use, cannot scan for AirPlay RX devices',
      );
    }
    rethrow;
  } catch (e) {
    await logger.error('errors.mdns_init_error', tag: 'mDNS', error: e);
    rethrow;
  }

  try {
    // dns-sd -B _airplay._tcp local
    await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer('_airplay._tcp.local'),
    )) {
      final serviceName = ptr.domainName;
      await for (final SrvResourceRecord srv in client
          .lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(serviceName),
          )) {
        await logger.debug(
          'debug.found_airplay_service',
          tag: 'mDNS',
          params: {
            'target': srv.target,
            'port': srv.port,
            'priority': srv.priority,
            'weight': srv.weight,
          },
        );
        await for (final IPAddressResourceRecord ip in client
            .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            )) {
          await for (final TxtResourceRecord txt in client
              .lookup<TxtResourceRecord>(
                ResourceRecordQuery.text(serviceName),
              )) {
            final txtMap = <String, String>{};
            final dynamic txtRaw = txt.text;
            await _parseTxtRecord(txtRaw, txtMap, logger);

            final device = DiscoveredDevice.fromAirplay(
              ip: ip.address.address,
              port: srv.port,
              serviceName: serviceName,
              txtMap: txtMap,
              mdnsTypes: ['_airplay._tcp'],
            );

            final deviceId = device.id ?? '${device.ip}_${device.name}';
            if (deviceMap.containsKey(deviceId)) {
              await logger.debug(
                'debug.duplicate_airplay_device',
                tag: 'mDNS',
                params: {'id': deviceId, 'name': device.name, 'ip': device.ip},
              );
              continue;
            }
            deviceMap[deviceId] = device;

            await logger.info(
              'info.found_airplay_device',
              tag: 'mDNS',
              params: {
                'deviceType': 'AirPlay RX',
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
    }
  } catch (e) {
    await logger.error('errors.airplay_rx_scan_failed', tag: 'mDNS', error: e);
  } finally {
    bool clientStopped = false;
    if (!clientStopped) {
      try {
        client.stop();
      } catch (_) {}
      clientStopped = true;
    }
  }
  devices.addAll(deviceMap.values);
  await logger.info(
    'info.airplay_rx_scan_complete',
    tag: 'mDNS',
    params: {'count': devices.length},
  );
  return devices;
}

/// Scan for AirPlay TX (發射端, 如 iPhone/iPad/Mac)
Future<List<DiscoveredDevice>> scanAirplayTxDevices({
  Function(DiscoveredDevice)? onDeviceFound,
}) async {
  final logger = AppLogger();
  await logger.info('info.start_airplay_tx_scan', tag: 'mDNS');
  final List<DiscoveredDevice> devices = [];
  final deviceMap = <String, DiscoveredDevice>{};
  MDnsClient? client;

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
    await logger.info('info.standard_mdns_port', tag: 'mDNS');
  } on SocketException catch (e) {
    if (e.osError?.errorCode == 48 || e.osError?.errorCode == 10048) {
      await logger.error(
        'errors.port_in_use',
        tag: 'mDNS',
        params: {'port': e.port},
      );
      throw MdnsPortInUseException(
        'mDNS port ${e.port} is in use, cannot scan for AirPlay TX devices',
      );
    }
    rethrow;
  } catch (e) {
    await logger.error('errors.mdns_init_error', tag: 'mDNS', error: e);
    rethrow;
  }

  try {
    // dns-sd -B _raop._tcp local
    await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer('_raop._tcp.local'),
    )) {
      final serviceName = ptr.domainName;
      await for (final SrvResourceRecord srv in client
          .lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(serviceName),
          )) {
        await logger.debug(
          'debug.found_raop_service',
          tag: 'mDNS',
          params: {
            'target': srv.target,
            'port': srv.port,
            'priority': srv.priority,
            'weight': srv.weight,
          },
        );
        await for (final IPAddressResourceRecord ip in client
            .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            )) {
          await for (final TxtResourceRecord txt in client
              .lookup<TxtResourceRecord>(
                ResourceRecordQuery.text(serviceName),
              )) {
            final txtMap = <String, String>{};
            final dynamic txtRaw = txt.text;
            await _parseTxtRecord(txtRaw, txtMap, logger);

            final device = DiscoveredDevice.fromAirplay(
              ip: ip.address.address,
              port: srv.port,
              serviceName: serviceName,
              txtMap: txtMap,
              mdnsTypes: ['_raop._tcp'],
            );

            final deviceId = device.id ?? '${device.ip}_${device.name}';
            if (deviceMap.containsKey(deviceId)) {
              await logger.debug(
                'debug.duplicate_airplay_tx_device',
                tag: 'mDNS',
                params: {'id': deviceId, 'name': device.name, 'ip': device.ip},
              );
              continue;
            }
            deviceMap[deviceId] = device;

            await logger.info(
              'info.found_airplay_tx_device',
              tag: 'mDNS',
              params: {
                'deviceType': 'AirPlay TX',
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
    }
  } catch (e) {
    await logger.error('errors.airplay_tx_scan_failed', tag: 'mDNS', error: e);
  } finally {
    bool clientStopped = false;
    if (!clientStopped) {
      try {
        client.stop();
      } catch (_) {}
      clientStopped = true;
    }
  }
  devices.addAll(deviceMap.values);
  await logger.info(
    'info.airplay_tx_scan_complete',
    tag: 'mDNS',
    params: {'count': devices.length},
  );
  return devices;
}

/// 安全嘗試 bind，優先用 reusePort=true，失敗再 fallback
Future<RawDatagramSocket> _safeBind(dynamic host, int port, {int? ttl}) async {
  try {
    return await RawDatagramSocket.bind(
      host,
      port,
      reuseAddress: true,
      reusePort: true,
      ttl: ttl ?? 1,
    );
  } catch (_) {
    // fallback: 不支援 reusePort
    return await RawDatagramSocket.bind(
      host,
      port,
      reuseAddress: true,
      ttl: ttl ?? 1,
    );
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
