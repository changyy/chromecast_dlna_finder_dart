import 'dart:async';
import 'dart:convert';
import 'discovery/device.dart';
import 'discovery/discovery_service.dart';
import 'util/logger.dart';
import 'util/platform_info.dart';

/// Main class for Chromecast and DLNA device discovery
class ChromecastDlnaFinder {
  final DiscoveryService _discoveryService = DiscoveryService();
  final AppLogger _logger;

  /// Allow external injection of logger, default to AppLogger singleton
  ChromecastDlnaFinder({AppLogger? logger}) : _logger = logger ?? AppLogger();

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
    await _logger.info('Logging system configured: outputs=$outputs, minLevel=$minLevel', tag: 'Config');
  }
  
  /// Discover all devices and return raw data model
  Future<Map<String, List<DiscoveredDevice>>> findDevices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final result = await _discoveryService.discoverAllDevices(timeout: timeout);
    return result;
  }
  
  /// Discover all devices and return JSON format data
  Future<Map<String, dynamic>> findDevicesAsJson({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final devices = await findDevices(timeout: timeout);
    final json = _discoveryService.toJson(devices);
    await _logger.debug('Generated JSON data: ${json.keys.length} main fields', tag: 'Finder');
    return json;
  }
  
  /// Discover all devices and return JSON string
  Future<String> findDevicesAsJsonString({
    Duration timeout = const Duration(seconds: 5),
    bool pretty = false,
  }) async {
    final jsonMap = await findDevicesAsJson(timeout: timeout);
    String result;
    
    if (pretty) {
      result = JsonEncoder.withIndent('  ').convert(jsonMap);
      await _logger.debug('Generated pretty JSON string, length: ${result.length}', tag: 'Finder');
    } else {
      result = jsonEncode(jsonMap);
      await _logger.debug('Generated JSON string, length: ${result.length}', tag: 'Finder');
    }
    
    return result;
  }
  
  /// Check if running on mobile platform
  bool get isMobilePlatform => PlatformInfo.isMobile;

  /// Check if running on supported platform (not web)
  bool get isSupportedPlatform => PlatformInfo.isSupportedPlatform;
  
  /// Release resources
  Future<void> dispose() async {
    await _logger.dispose();
  }
}
