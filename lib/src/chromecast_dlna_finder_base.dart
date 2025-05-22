import 'dart:async';
import 'dart:convert';
import 'discovery/device.dart';
import 'discovery/discovery_service.dart';
import 'discovery/discovery_events.dart';
import 'util/logger.dart';
import 'util/platform_info.dart';

/// Main class for Chromecast and DLNA device discovery
class ChromecastDlnaFinder {
  final DiscoveryService _discoveryService = DiscoveryService();
  final AppLogger _logger;

  // Forward events from discovery service
  StreamSubscription? _discoveryEventsSubscription;
  StreamController<DeviceDiscoveryEvent>? _eventController;

  /// Allow external injection of logger, default to AppLogger singleton
  ChromecastDlnaFinder({AppLogger? logger}) : _logger = logger ?? AppLogger() {
    // Initialize event channel
    _eventController = StreamController.broadcast();

    // Subscribe to discovery service events
    _discoveryEventsSubscription = _discoveryService.discoveryEvents.listen((
      event,
    ) {
      if (_eventController?.isClosed == false) {
        _eventController?.add(event);
      }
    });
  }

  /// Get device discovery event stream
  /// Can be listened to in Flutter UI for real-time device discovery events
  Stream<DeviceDiscoveryEvent>? get deviceEvents => _eventController?.stream;

  /// Configure logging system
  /// [outputs] log output channels
  /// [minLevel] Minimum log level
  Future<void> configureLogger({
    Set<LoggerOutput> outputs = const {LoggerOutput.stderr},
    AppLogLevel minLevel = AppLogLevel.info,
  }) async {
    _logger.setOutputs(outputs);
    _logger.setMinLevel(minLevel);
    await _logger.init();
    await _logger.info(
      'Logging system configured: outputs=$outputs, minLevel=$minLevel',
      tag: 'Config',
    );
  }

  /// Discover all devices and return raw data model
  Future<Map<String, List<DiscoveredDevice>>> findDevices({
    Duration scanDuration = const Duration(seconds: 5),
  }) async {
    final result = await _discoveryService.discoverAllDevices(
      scanDuration: scanDuration,
    );
    return result;
  }

  /// Discover all devices and return JSON format data
  Future<Map<String, dynamic>> findDevicesAsJson({
    Duration scanDuration = const Duration(seconds: 5),
  }) async {
    final devices = await findDevices(scanDuration: scanDuration);
    final json = _discoveryService.toJson(devices);
    await _logger.debug(
      'Generated JSON data: ${json.keys.length} main fields',
      tag: 'Finder',
    );
    return json;
  }

  /// Discover all devices and return JSON string
  Future<String> findDevicesAsJsonString({
    Duration scanDuration = const Duration(seconds: 5),
    bool pretty = false,
  }) async {
    final jsonMap = await findDevicesAsJson(scanDuration: scanDuration);
    String result;

    if (pretty) {
      result = JsonEncoder.withIndent('  ').convert(jsonMap);
      await _logger.debug(
        'Generated pretty JSON string, length: ${result.length}',
        tag: 'Finder',
      );
    } else {
      result = jsonEncode(jsonMap);
      await _logger.debug(
        'Generated JSON string, length: ${result.length}',
        tag: 'Finder',
      );
    }

    return result;
  }

  /// Check if running on mobile platform
  bool get isMobilePlatform => PlatformInfo.isMobile;

  /// Check if running on supported platform (not web)
  bool get isSupportedPlatform => PlatformInfo.isSupportedPlatform;

  /// Release resources
  Future<void> dispose() async {
    await _discoveryEventsSubscription?.cancel();
    await _eventController?.close();
    await _discoveryService.dispose();
    await _logger.dispose();
  }
}
