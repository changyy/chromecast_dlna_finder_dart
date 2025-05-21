import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../discovery/device.dart';
import '../util/dlna_device_utils.dart';
import '../util/logger.dart';

/// Scan for DLNA Renderer devices in the local network (using SSDP/UPnP)
/// [onDeviceFound] 回調函數，當找到新裝置時調用
Future<List<DiscoveredDevice>> scanDlnaRendererDevices({
  Duration timeout = const Duration(seconds: 3),
  Function(DiscoveredDevice)? onDeviceFound,
}) async {
  final logger = AppLogger();
  await logger.info('info.start_dlna_renderer_scan', tag: 'SSDP');
  final List<DiscoveredDevice> devices = [];
  RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  } catch (e) {
    return [];
  }
  // SSDP discovery message
  const String ssdpRequest =
      'M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 2\r\n'
      'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
      '\r\n';
  final data = utf8.encode(ssdpRequest);
  socket.send(data, InternetAddress('239.255.255.250'), 1900);

  final responses = <String, DiscoveredDevice>{};
  final completer = Completer<void>();
  socket.listen(
    (RawSocketEvent event) async {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          final resp = utf8.decode(datagram.data);
          final ip = datagram.address.address;
          if (resp.contains('MediaRenderer')) {
            // Parse device information
            final nameMatch = RegExp(r'\nSERVER: (.+)').firstMatch(resp);
            final name = nameMatch?.group(1) ?? 'DLNA Renderer';
            // Parse LOCATION field
            final locationMatch = RegExp(
              r'LOCATION:\s*(.+)\r?\n',
              caseSensitive: false,
            ).firstMatch(resp);
            final location = locationMatch?.group(1)?.trim();

            // Parse model information (if available)
            final modelMatch = RegExp(
              r'MODEL: (.+?)\r?\n',
              caseSensitive: false,
            ).firstMatch(resp);
            final model = modelMatch?.group(1)?.trim();

            String? avTransportControlUrl;
            String? renderingControlUrl;
            if (location != null) {
              try {
                final urls = await fetchControlUrls(location);
                avTransportControlUrl = urls[0];
                renderingControlUrl = urls[1];
              } catch (e) {
                await logger.error(
                  'errors.parse_control_urls_failed',
                  tag: 'SSDP',
                  error: e,
                );
              }
            }
            if (!responses.containsKey(ip)) {
              final device = DiscoveredDevice.fromDlnaRenderer(
                name: name,
                ip: ip,
                location: location ?? '',
                avTransportControlUrl: avTransportControlUrl,
                renderingControlUrl: renderingControlUrl,
                model: model,
              );

              await logger.info(
                'info.found_dlna_renderer',
                tag: 'SSDP',
                params: {
                  'name': device.name,
                  'ip': device.ip,
                  'model': device.model ?? 'unknown',
                  'location': device.location,
                },
              );

              responses[ip] = device;
              if (onDeviceFound != null) {
                onDeviceFound(device);
              }
            }
          }
        }
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
    onError: (e) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
  );
  // Wait for timeout to complete
  Future.delayed(timeout, () {
    socket.close();
    if (!completer.isCompleted) {
      completer.complete();
    }
  });
  try {
    await completer.future;
  } catch (e) {
    rethrow;
  }
  devices.addAll(responses.values);

  await logger.info(
    'info.dlna_renderer_scan_complete',
    tag: 'SSDP',
    params: {'count': devices.length},
  );

  return devices;
}

/// Scan for DLNA Media Server devices in the local network (using SSDP/UPnP)
/// [onDeviceFound] 回調函數，當找到新裝置時調用
Future<List<DiscoveredDevice>> scanDlnaMediaServerDevices({
  Duration timeout = const Duration(seconds: 3),
  Function(DiscoveredDevice)? onDeviceFound,
}) async {
  final logger = AppLogger();
  await logger.info('info.start_dlna_server_scan', tag: 'SSDP');
  final List<DiscoveredDevice> devices = [];
  RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  } catch (e) {
    return [];
  }
  // SSDP discovery message specifically for Media Server
  const String ssdpRequest =
      'M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1900\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 2\r\n'
      'ST: urn:schemas-upnp-org:device:MediaServer:1\r\n'
      '\r\n';
  final data = utf8.encode(ssdpRequest);
  socket.send(data, InternetAddress('239.255.255.250'), 1900);

  final responses = <String, DiscoveredDevice>{};
  final completer = Completer<void>();
  socket.listen(
    (RawSocketEvent event) async {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          final resp = utf8.decode(datagram.data);
          final ip = datagram.address.address;
          if (resp.contains('MediaServer')) {
            // Parse device information
            final nameMatch = RegExp(r'\nSERVER: (.+)').firstMatch(resp);
            final name = nameMatch?.group(1) ?? 'DLNA Media Server';
            // Parse LOCATION field
            final locationMatch = RegExp(
              r'LOCATION:\s*(.+)\r?\n',
              caseSensitive: false,
            ).firstMatch(resp);
            final location = locationMatch?.group(1)?.trim();

            // Parse model information (if available)
            final modelMatch = RegExp(
              r'MODEL: (.+?)\r?\n',
              caseSensitive: false,
            ).firstMatch(resp);
            final model = modelMatch?.group(1)?.trim();

            if (!responses.containsKey(ip) && location != null) {
              final device = DiscoveredDevice.fromDlnaMediaServer(
                name: name,
                ip: ip,
                location: location,
                model: model,
              );
              await logger.info(
                'info.found_dlna_server',
                tag: 'SSDP',
                params: {
                  'name': device.name,
                  'ip': device.ip,
                  'model': device.model ?? 'unknown',
                  'location': device.location,
                },
              );
              responses[ip] = device;
              if (onDeviceFound != null) {
                onDeviceFound(device);
              }
            }
          }
        }
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
    onError: (_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    },
  );
  // Wait for timeout to complete
  Future.delayed(timeout, () {
    socket.close();
    if (!completer.isCompleted) {
      completer.complete();
    }
  });
  await completer.future;
  devices.addAll(responses.values);
  await logger.info(
    'info.dlna_server_scan_complete',
    tag: 'SSDP',
    params: {'count': devices.length},
  );
  return devices;
}

/// Scan for all DLNA devices (including Renderers and Media Servers)
/// [onDeviceFound] 回調函數，當找到新裝置時調用
Future<List<DiscoveredDevice>> scanAllDlnaDevices({
  Duration timeout = const Duration(seconds: 3),
  Function(DiscoveredDevice)? onDeviceFound,
}) async {
  final logger = AppLogger();
  await logger.info('info.start_all_dlna_scan', tag: 'SSDP');

  // 使用 Future.wait 同時掃描兩種裝置
  final results = await Future.wait([
    scanDlnaRendererDevices(timeout: timeout, onDeviceFound: onDeviceFound),
    scanDlnaMediaServerDevices(timeout: timeout, onDeviceFound: onDeviceFound),
  ]);

  final renderers = results[0];
  final mediaServers = results[1];

  final devices = [...renderers, ...mediaServers];
  await logger.info(
    'info.all_dlna_scan_complete',
    tag: 'SSDP',
    params: {'count': devices.length},
  );
  return devices;
}
