import 'dart:async';
import 'device.dart';
import 'mdns_scanner.dart';
import 'ssdp_scanner.dart';
import 'discovery_events.dart';
import '../util/logger.dart';

/// Device discovery service
class DiscoveryService {
  // Logging service
  final AppLogger _logger = AppLogger();

  // 事件廣播控制器
  final StreamController<DeviceDiscoveryEvent> _eventController =
      StreamController.broadcast();

  /// 取得裝置發現事件的串流
  Stream<DeviceDiscoveryEvent> get discoveryEvents => _eventController.stream;

  // 安全地發送事件，避免 controller 已關閉時拋出異常
  void _safeAddEvent(DeviceDiscoveryEvent event) {
    if (!_eventController.isClosed) {
      try {
        _eventController.add(event);
      } catch (_) {
        // ignore
      }
    }
  }

  // 生成更可靠的裝置唯一識別鍵
  String getDeviceKey(DiscoveredDevice device) {
    // 如果 Chromecast 裝置有 ID，優先使用
    if (device.isChromecast && device.id != null) {
      return 'chromecast_${device.id}';
    }
    // AirPlay 裝置唯一識別
    if (device.type == DeviceType.airplay) {
      // 優先使用 location
      return 'airplay_${device.location ?? '${device.ip}_${device.name}'}';
    }
    // 如果有 location，結合 IP 和 location 作為識別
    if (device.location != null) {
      // 對於 DLNA renderer，加上控制 URL 以更精確識別
      if (device.isDlnaRenderer && device.avTransportControlUrl != null) {
        return 'dlna_${device.location}_${device.avTransportControlUrl}';
      }
      return 'device_${device.type}_${device.location}';
    }
    // 如果 model 非空，結合 name、IP 和 model
    if (device.model != null) {
      return 'device_${device.name}_${device.ip}_${device.model}';
    }
    // 最後的退路：使用名稱+IP+類型的組合
    return 'device_${device.name}_${device.ip}_${device.type}';
  }

  /// Discover all types of devices
  /// Including Chromecast and DLNA (Renderer and Media Server)
  Future<Map<String, List<DiscoveredDevice>>> discoverAllDevices({
    Duration scanDuration = const Duration(seconds: 5),
  }) async {
    if (_eventController.isClosed) {
      throw StateError(
        'DiscoveryService already disposed: _eventController is closed',
      );
    }
    final result = <String, List<DiscoveredDevice>>{
      'chromecast': [],
      'dlna': [],
      'dlna_rx': [],
      'dlna_tx': [],
      'airplay': [],
      'airplay_rx': [],
      'airplay_tx': [],
      'all': [],
    };
    final errors = <String>[];

    // 通知開始整體搜尋
    _safeAddEvent(SearchStartedEvent('all', 'DiscoveryService'));

    // 包裝函數：掃描 Chromecast
    Future<List<DiscoveredDevice>> scanChromecastDevicesWithEvents({
      Duration scanDuration = const Duration(seconds: 5),
    }) async {
      _safeAddEvent(SearchStartedEvent('chromecast', 'mDNS'));
      try {
        final devices = await scanChromecastDevices(
          onDeviceFound: (device) {
            _safeAddEvent(DeviceFoundEvent(device, 'mDNS'));
          },
          scanDuration: scanDuration,
        );
        _safeAddEvent(
          SearchCompleteEvent('chromecast', devices.length, 'mDNS'),
        );
        return devices;
      } catch (e) {
        _safeAddEvent(SearchErrorEvent('chromecast', e.toString(), 'mDNS'));
        return [];
      }
    }

    // 包裝函數：掃描 DLNA
    Future<List<DiscoveredDevice>> scanAllDlnaDevicesWithEvents({
      Duration scanDuration = const Duration(seconds: 5),
    }) async {
      _safeAddEvent(SearchStartedEvent('dlna', 'SSDP'));
      try {
        final devices = await scanAllDlnaDevices(
          scanDuration: scanDuration,
          onDeviceFound: (device) {
            _safeAddEvent(DeviceFoundEvent(device, 'SSDP'));
          },
        );
        _safeAddEvent(SearchCompleteEvent('dlna', devices.length, 'SSDP'));
        return devices;
      } catch (e) {
        _safeAddEvent(SearchErrorEvent('dlna', e.toString(), 'SSDP'));
        return [];
      }
    }

    // 包裝函數：掃描 AirPlay RX
    Future<List<DiscoveredDevice>> scanAirplayRxDevicesWithEvents({
      Duration scanDuration = const Duration(seconds: 5),
    }) async {
      _safeAddEvent(SearchStartedEvent('airplay_rx', 'mDNS'));
      try {
        final devices = await scanAirplayRxDevices(
          onDeviceFound: (device) {
            _safeAddEvent(DeviceFoundEvent(device, 'mDNS'));
          },
          scanDuration: scanDuration,
        );
        _safeAddEvent(
          SearchCompleteEvent('airplay_rx', devices.length, 'mDNS'),
        );
        return devices;
      } catch (e) {
        _safeAddEvent(SearchErrorEvent('airplay_rx', e.toString(), 'mDNS'));
        return [];
      }
    }

    // 包裝函數：掃描 AirPlay TX
    Future<List<DiscoveredDevice>> scanAirplayTxDevicesWithEvents({
      Duration scanDuration = const Duration(seconds: 5),
    }) async {
      _safeAddEvent(SearchStartedEvent('airplay_tx', 'mDNS'));
      try {
        final devices = await scanAirplayTxDevices(
          onDeviceFound: (device) {
            _safeAddEvent(DeviceFoundEvent(device, 'mDNS'));
          },
          scanDuration: scanDuration,
        );
        _safeAddEvent(
          SearchCompleteEvent('airplay_tx', devices.length, 'mDNS'),
        );
        return devices;
      } catch (e) {
        _safeAddEvent(SearchErrorEvent('airplay_tx', e.toString(), 'mDNS'));
        return [];
      }
    }

    try {
      // 並行掃描 chromecast, dlna, airplay_rx, airplay_tx
      final chromecastDevicesFuture = scanChromecastDevicesWithEvents(
        scanDuration: scanDuration,
      );
      final dlnaDevicesFuture = scanAllDlnaDevicesWithEvents(
        scanDuration: scanDuration,
      );
      final airplayRxDevicesFuture = scanAirplayRxDevicesWithEvents(
        scanDuration: scanDuration,
      );
      final airplayTxDevicesFuture = scanAirplayTxDevicesWithEvents(
        scanDuration: scanDuration,
      );
      final results = await Future.wait([
        chromecastDevicesFuture,
        dlnaDevicesFuture,
        airplayRxDevicesFuture,
        airplayTxDevicesFuture,
      ]);
      final deviceMap = <String, DiscoveredDevice>{};

      deviceMap.clear();
      for (final d in results[0]) {
        deviceMap[getDeviceKey(d)] = d;
      }
      result['chromecast'] = deviceMap.values.toList();

      deviceMap.clear();
      for (final d in results[1]) {
        deviceMap[getDeviceKey(d)] = d;
      }
      result['dlna'] = deviceMap.values.toList();

      deviceMap.clear();
      for (final d in results[2]) {
        deviceMap[getDeviceKey(d)] = d;
      }
      for (final d in results[3]) {
        deviceMap[getDeviceKey(d)] = d;
      }
      result['airplay'] = deviceMap.values.toList();
    } catch (e) {
      await _logger.error(
        'errors.unexpected_scan_error',
        tag: 'Discovery',
        error: e,
        params: {'error': e.toString()},
      );
      errors.add(['errors.unexpected_scan_error', e.toString()].join(' '));
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

    result['dlna_rx'] = dlnaRenderers;
    result['dlna_tx'] = dlnaMediaServers;
    result['dlna_renderer'] = dlnaRenderers;
    result['dlna_media_server'] = dlnaMediaServers;

    // Categorize AirPlay devices
    final airplayRxDevices = <String, DiscoveredDevice>{};
    final airplayTxDevices = <String, DiscoveredDevice>{};
    for (final device in result['airplay']!) {
      final mdnsTypes = device.mdnsTypes ?? <String>[];
      final hasAirplay = mdnsTypes.contains('_airplay._tcp');
      final hasRaop = mdnsTypes.contains('_raop._tcp');
      final key = device.ip + (device.id ?? '') + (device.name);
      // RX: 只收錄有 _airplay._tcp 的裝置
      if (hasAirplay) {
        airplayRxDevices[key] = device;
      }
      // TX: 只收錄有 _raop._tcp 的裝置
      if (hasRaop) {
        airplayTxDevices[key] = device;
      }
    }
    result['airplay_rx'] = airplayRxDevices.values.toList();
    result['airplay_tx'] = airplayTxDevices.values.toList();

    result['all'] = [
      ...result['chromecast']!,
      ...result['dlna']!,
      ...result['airplay']!,
    ];

    // Add error information
    result['errors'] =
        errors
            .map(
              (e) =>
                  DiscoveredDevice(name: e, ip: '', type: DeviceType.unknown),
            )
            .toList();

    await _logger.debug(
      'Device discovery complete: Chromecast=[0m${result['chromecast']!.length}, DLNA=${result['dlna']!.length}, Errors=${errors.length}',
      tag: 'Discovery',
    );

    return result;
  }

  /// Convert to JSON format result
  Map<String, dynamic> toJson(Map<String, List<DiscoveredDevice>> result) {
    final json = <String, dynamic>{};

    for (final field in [
      'all',
      'chromecast',
      'chromecast_dongle',
      'chromecast_audio',
      'dlna',
      'dlna_renderer',
      'dlna_media_server',
      'dlna_rx',
      'dlna_tx',
      'airplay',
      'airplay_rx',
      'airplay_tx',
    ]) {
      json[field] =
          (result[field] ?? []).map((device) => device.toJson()).toList();
    }

    final airplayIPSet = <String>{};
    for (final device in result['airplay'] ?? []) {
      airplayIPSet.add(device.ip);
    }

    final dlnaIPSet = <String>{};
    for (final device in result['dlna'] ?? []) {
      dlnaIPSet.add(device.ip);
    }

    final chromecastIPSet = <String>{};
    for (final device in result['chromecast'] ?? []) {
      chromecastIPSet.add(device.ip);
    }

    json['count'] = {
      'chromecast': {
        'total': chromecastIPSet.length,
        'rx': chromecastIPSet.length,
        'tx': 0,
      },
      'dlna': {
        'total': dlnaIPSet.length,
        'rx': result['dlna_rx']?.length ?? 0,
        'tx': result['dlna_tx']?.length ?? 0,
      },
      'ariplay': {
        'total': airplayIPSet.length,
        'rx': result['airplay_rx']?.length ?? 0,
        'tx': result['airplay_tx']?.length ?? 0,
      },
    };

    // Process errors
    json['error'] =
        result['errors']?.map((device) => device.name).toList() ?? [];
    json['status'] = (result['errors']?.isEmpty ?? true);

    return json;
  }

  /// 釋放資源
  Future<void> dispose() async {
    await _eventController.close();
  }
}
