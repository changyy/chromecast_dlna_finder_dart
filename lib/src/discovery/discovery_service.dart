import 'dart:async';
import 'device.dart';
import 'mdns_scanner.dart';
import 'ssdp_scanner.dart';
import '../util/logger.dart';

/// Device discovery service
class DiscoveryService {
  // Logging service
  final AppLogger _logger = AppLogger();

  /// Discover all types of devices
  /// Including Chromecast and DLNA (Renderer and Media Server)
  Future<Map<String, List<DiscoveredDevice>>> discoverAllDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final result = <String, List<DiscoveredDevice>>{
      'chromecast': [],
      'dlna': [],
    };

    final errors = <String>[];

    try {
      // Asynchronously scan Chromecast devices
      final chromecastTask = scanChromecastDevices()
          .then((devices) {
            result['chromecast'] = devices;
          })
          .catchError((e) async {
            await _logger.error(
              'errors.chromecast_scan_error',
              tag: 'Discovery',
              error: e,
              params: {'error': e.toString()},
            );
            if (e is MdnsPortInUseException) {
              errors.add('errors.mdns_port_in_use');
            } else {
              errors.add('errors.chromecast_scan_error');
            }
          });

      // Asynchronously scan DLNA devices
      final dlnaTask = scanAllDlnaDevices(timeout: timeout)
          .then((devices) {
            result['dlna'] = devices;
          })
          .catchError((e) async {
            await _logger.error(
              'errors.dlna_scan_error',
              tag: 'Discovery',
              error: e,
              params: {'error': e.toString()},
            );
            errors.add('errors.dlna_scan_error');
          });

      // Wait for all scans to complete
      await Future.wait([chromecastTask, dlnaTask]);
    } catch (e) {
      await _logger.error(
        'errors.unexpected_scan_error',
        tag: 'Discovery',
        error: e,
        params: {'error': e.toString()},
      );
      errors.add('errors.unexpected_scan_error');
    }

    // Categorize Chromecast devices by type
    final chromecastDongles = <DiscoveredDevice>[];
    final chromecastAudios = <DiscoveredDevice>[];

    for (final device in result['chromecast']!) {
      if (device.type == DeviceType.chromecastDongle) {
        chromecastDongles.add(device);
      } else if (device.type == DeviceType.chromecastAudio) {
        chromecastAudios.add(device);
      }
    }

    result['chromecast_dongle'] = chromecastDongles;
    result['chromecast_audio'] = chromecastAudios;

    // Categorize DLNA devices by type
    final dlnaRenderers = <DiscoveredDevice>[];
    final dlnaMediaServers = <DiscoveredDevice>[];

    for (final device in result['dlna']!) {
      if (device.type == DeviceType.dlnaRenderer) {
        dlnaRenderers.add(device);
      } else if (device.type == DeviceType.dlnaMediaServer) {
        dlnaMediaServers.add(device);
      }
    }

    result['dlna_renderer'] = dlnaRenderers;
    result['dlna_media_server'] = dlnaMediaServers;

    // Add error information
    result['errors'] =
        errors
            .map(
              (e) =>
                  DiscoveredDevice(name: e, ip: '', type: DeviceType.unknown),
            )
            .toList();

    await _logger.debug(
      'Device discovery complete: Chromecast=${result['chromecast']!.length}, DLNA=${result['dlna']!.length}, Errors=${errors.length}',
      tag: 'Discovery',
    );

    return result;
  }

  /// Convert to JSON format result
  Map<String, dynamic> toJson(Map<String, List<DiscoveredDevice>> result) {
    final json = <String, dynamic>{};

    // Process each device type
    json['chromecast'] =
        result['chromecast']!.map((device) => device.toJson()).toList();
    json['chromecast_dongle'] =
        result['chromecast_dongle']!.map((device) => device.toJson()).toList();
    json['chromecast_audio'] =
        result['chromecast_audio']!.map((device) => device.toJson()).toList();
    json['dlna'] = result['dlna']!.map((device) => device.toJson()).toList();
    json['dlna_renderer'] =
        result['dlna_renderer']!.map((device) => device.toJson()).toList();
    json['dlna_media_server'] =
        result['dlna_media_server']!.map((device) => device.toJson()).toList();

    json['count'] = {
      'tx': result['dlna_media_server']!.length,
      'rx': result['chromecast']!.length + result['dlna_renderer']!.length,
      'total':
          result['chromecast']!.length +
          result['dlna_renderer']!.length +
          result['dlna_media_server']!.length,
    };

    // Process errors
    json['error'] =
        result['errors']?.map((device) => device.name).toList() ?? [];
    json['status'] = (result['errors']?.isEmpty ?? true);

    return json;
  }
}
