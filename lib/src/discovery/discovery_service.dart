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

  /// Discover all types of devices
  /// Including Chromecast and DLNA (Renderer and Media Server)
  Future<Map<String, List<DiscoveredDevice>>> discoverAllDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_eventController.isClosed) {
      throw StateError(
        'DiscoveryService already disposed: _eventController is closed',
      );
    }
    final result = <String, List<DiscoveredDevice>>{
      'chromecast': [],
      'dlna': [],
      'airplay': [], // 新增 AirPlay 結果欄位
    };
    final errors = <String>[];

    // 通知開始整體搜尋
    _safeAddEvent(SearchStartedEvent('all', 'DiscoveryService'));

    // 包裝函數：掃描 Chromecast
    Future<List<DiscoveredDevice>> scanChromecastDevicesWithEvents() async {
      _safeAddEvent(SearchStartedEvent('chromecast', 'mDNS'));
      try {
        final devices = await scanChromecastDevices(
          onDeviceFound: (device) {
            _safeAddEvent(DeviceFoundEvent(device, 'mDNS'));
          },
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
    Future<List<DiscoveredDevice>> scanAllDlnaDevicesWithEvents() async {
      _safeAddEvent(SearchStartedEvent('dlna', 'SSDP'));
      try {
        final devices = await scanAllDlnaDevices(
          timeout: timeout,
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
    Future<List<DiscoveredDevice>> scanAirplayRxDevicesWithEvents() async {
      _safeAddEvent(SearchStartedEvent('airplay_rx', 'mDNS'));
      try {
        final devices = await scanAirplayRxDevices(
          onDeviceFound: (device) {
            _safeAddEvent(DeviceFoundEvent(device, 'mDNS'));
          },
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
    Future<List<DiscoveredDevice>> scanAirplayTxDevicesWithEvents() async {
      _safeAddEvent(SearchStartedEvent('airplay_tx', 'mDNS'));
      try {
        final devices = await scanAirplayTxDevices(
          onDeviceFound: (device) {
            _safeAddEvent(DeviceFoundEvent(device, 'mDNS'));
          },
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
      final chromecastDevicesFuture = scanChromecastDevicesWithEvents();
      final dlnaDevicesFuture = scanAllDlnaDevicesWithEvents();
      final airplayRxDevicesFuture = scanAirplayRxDevicesWithEvents();
      final airplayTxDevicesFuture = scanAirplayTxDevicesWithEvents();
      final results = await Future.wait([
        chromecastDevicesFuture,
        dlnaDevicesFuture,
        airplayRxDevicesFuture,
        airplayTxDevicesFuture,
      ]);
      result['chromecast'] = results[0];
      result['dlna'] = results[1];
      // 將 airplay_rx, airplay_tx 合併到 airplay，並去重
      final airplayMap = <String, DiscoveredDevice>{};
      for (final d in results[2]) {
        final key = d.ip + (d.id ?? '') + (d.name);
        airplayMap[key] = d;
      }
      for (final d in results[3]) {
        final key = d.ip + (d.id ?? '') + (d.name);
        airplayMap[key] = d;
      }
      result['airplay'] = airplayMap.values.toList();
    } catch (e) {
      await _logger.error(
        'errors.unexpected_scan_error',
        tag: 'Discovery',
        error: e,
        params: {'error': e.toString()},
      );
      errors.add('errors.unexpected_scan_error');
    }

    // 去除重複裝置
    // 建立一個臨時Map來檢查裝置是否重複，使用更可靠的識別方式
    final uniqueDevices = <String, DiscoveredDevice>{};
    final duplicates = <DiscoveredDevice>[];

    // 生成更可靠的裝置唯一識別鍵
    String getDeviceKey(DiscoveredDevice device) {
      // 如果 Chromecast 裝置有 ID，優先使用
      if (device.isChromecast && device.id != null) {
        return 'chromecast_${device.id}';
      }
      // AirPlay 裝置唯一識別
      if (device.type == DeviceType.airplay) {
        // 若有 name 優先用 name
        return 'airplay_${device.name}';
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

    // 處理 Chromecast 裝置
    for (final device in result['chromecast']!) {
      final key = getDeviceKey(device);
      if (uniqueDevices.containsKey(key)) {
        await _logger.debug(
          'debug.duplicate_device',
          tag: 'Discovery',
          params: {
            'type': 'Chromecast',
            'name': device.name,
            'ip': device.ip,
            'key': key,
          },
        );
        duplicates.add(device);
      } else {
        uniqueDevices[key] = device;
      }
    }

    // 處理 DLNA 裝置
    for (final device in result['dlna']!) {
      final key = getDeviceKey(device);
      if (uniqueDevices.containsKey(key)) {
        await _logger.debug(
          'debug.duplicate_device',
          tag: 'Discovery',
          params: {
            'type': 'DLNA',
            'name': device.name,
            'ip': device.ip,
            'key': key,
          },
        );
        duplicates.add(device);
      } else {
        uniqueDevices[key] = device;
      }
    }

    // 處理 AirPlay 裝置
    for (final device in result['airplay']!) {
      final key = getDeviceKey(device);
      if (uniqueDevices.containsKey(key)) {
        await _logger.debug(
          'debug.duplicate_device',
          tag: 'Discovery',
          params: {
            'type': 'AirPlay',
            'name': device.name,
            'ip': device.ip,
            'key': key,
          },
        );
        duplicates.add(device);
      } else {
        uniqueDevices[key] = device;
      }
    }

    // 更新結果中的裝置清單，移除重複項
    if (duplicates.isNotEmpty) {
      await _logger.info(
        'info.removed_duplicate_devices',
        tag: 'Discovery',
        params: {'count': duplicates.length},
      );

      // 從所有列表中移除重複裝置
      result['chromecast'] =
          result['chromecast']!
              .where((device) => !duplicates.contains(device))
              .toList();
      result['dlna'] =
          result['dlna']!
              .where((device) => !duplicates.contains(device))
              .toList();
      result['airplay'] =
          result['airplay']!
              .where((device) => !duplicates.contains(device))
              .toList();
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
    // airplay 只保留唯一裝置（不重複）
    final airplayUnique = <String, DiscoveredDevice>{};
    for (final device in result['airplay']!) {
      final key = device.ip + (device.id ?? '') + (device.name);
      airplayUnique[key] = device;
    }
    result['airplay'] = airplayUnique.values.toList();

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

    // Process each device type
    json['chromecast'] =
        (result['chromecast'] ?? []).map((device) => device.toJson()).toList();
    json['chromecast_dongle'] =
        (result['chromecast_dongle'] ?? [])
            .map((device) => device.toJson())
            .toList();
    json['chromecast_audio'] =
        (result['chromecast_audio'] ?? [])
            .map((device) => device.toJson())
            .toList();
    json['dlna'] =
        (result['dlna'] ?? []).map((device) => device.toJson()).toList();
    json['dlna_renderer'] =
        (result['dlna_renderer'] ?? [])
            .map((device) => device.toJson())
            .toList();
    json['dlna_media_server'] =
        (result['dlna_media_server'] ?? [])
            .map((device) => device.toJson())
            .toList();
    json['airplay'] =
        (result['airplay'] ?? []).map((device) => device.toJson()).toList();
    json['airplay_tx'] =
        (result['airplay_tx'] ?? []).map((device) => device.toJson()).toList();
    json['airplay_rx'] =
        (result['airplay_rx'] ?? []).map((device) => device.toJson()).toList();
    // 不再輸出 airplay_device

    // 計算 RX/TX 數量
    final rxSet = <String>{};
    for (final device in result['airplay_rx'] ?? []) {
      rxSet.add(device.ip + (device.id ?? '') + (device.name));
    }
    for (final device in result['chromecast'] ?? []) {
      rxSet.add(device.ip + (device.id ?? '') + (device.name));
    }
    for (final device in result['dlna_renderer'] ?? []) {
      rxSet.add(device.ip + (device.id ?? '') + (device.name));
    }
    // TX: DLNA Media Server + AirPlay TX
    final txSet = <String>{};
    for (final device in result['dlna_media_server'] ?? []) {
      txSet.add(device.ip + (device.id ?? '') + (device.name));
    }
    for (final device in result['airplay_tx'] ?? []) {
      txSet.add(device.ip + (device.id ?? '') + (device.name));
    }
    // total: RX + TX（去重複）
    final totalSet = <String>{};
    totalSet.addAll(rxSet);
    totalSet.addAll(txSet);

    json['count'] = {
      'tx': txSet.length,
      'rx': rxSet.length,
      'total': totalSet.length,
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
