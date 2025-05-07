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
Future<List<DiscoveredDevice>> scanChromecastDevices() async {
  final logger = AppLogger();
  await logger.info('info.start_chromecast_scan', tag: 'mDNS');
  final List<DiscoveredDevice> devices = [];
  MDnsClient? client;
  
  try {
    // Try standard mDNS port, explicitly set reuseAddress=true and reusePort=true
    // This allows binding even if other processes are already listening
    client = MDnsClient(rawDatagramSocketFactory: (dynamic host, int port, {bool? reuseAddress, bool? reusePort, int? ttl}) {
      return RawDatagramSocket.bind(host, port, reuseAddress: true, reusePort: true, ttl: ttl ?? 1);
    });
    await client.start();
    await logger.info('info.standard_mdns_port', tag: 'mDNS');
  } on SocketException catch (e) {
    if (e.osError?.errorCode == 48 || // macOS/Linux port in use
        e.osError?.errorCode == 10048) { // Windows port in use
      await logger.error('errors.port_in_use', tag: 'mDNS', params: {'port': e.port});
      throw MdnsPortInUseException('mDNS port ${e.port} is in use, cannot scan for Chromecast devices');
    }
    rethrow;
  } catch (e) {
    await logger.error('errors.mdns_init_error', tag: 'mDNS', error: e);
    rethrow;
  }

  // Continue normal scanning process
  try {
    // dns-sd -B _googlecast._tcp local
    await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer('_googlecast._tcp.local'))) {
      final serviceName = ptr.domainName; // e.g. Chromecast-XXXXXX._googlecast._tcp.local
      await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(serviceName))) {
        await logger.debug('debug.found_service', tag: 'mDNS', params: {
          'target': srv.target,
          'port': srv.port,
          'priority': srv.priority,
          'weight': srv.weight
        });
        await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))) {
          // Query TXT record
          await for (final TxtResourceRecord txt in client.lookup<TxtResourceRecord>(ResourceRecordQuery.text(serviceName))) {
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
            
            // Display different messages based on device type
            final deviceType = device.isChromecastAudio ? 'Chromecast Audio' : 'Chromecast';
            await logger.info('info.found_device', tag: 'mDNS', params: {
              'deviceType': deviceType,
              'name': device.name,
              'ip': device.ip,
              'model': device.model
            });
            
            devices.add(device);
          }
        }
      }
    }
  } catch (e) {
    await logger.error('errors.chromecast_scan_failed', tag: 'mDNS', error: e);
  } finally {
    client.stop();
  }
  
  await logger.info('info.chromecast_scan_complete', tag: 'mDNS', params: {'count': devices.length});
  return devices;
}

/// Parse TXT record, fill results into txtMap
Future<void> _parseTxtRecord(dynamic txtRaw, Map<String, String> txtMap, AppLogger logger) async {
  await logger.debug('debug.txt_record_type', tag: 'mDNS', params: {'type': txtRaw.runtimeType});
  
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
    await logger.debug('debug.nonstandard_txt_format', tag: 'mDNS', params: {'txtRaw': txtRaw});
    
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
      await logger.debug('debug.parse_txt_record_failed', tag: 'mDNS', params: {'error': e});
    }
  }
  
  await logger.debug('debug.txt_map', tag: 'mDNS', params: {'map': txtMap});
}
