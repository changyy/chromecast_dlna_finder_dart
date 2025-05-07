import 'device.dart';

/// 裝置發現事件的基礎類別
abstract class DeviceDiscoveryEvent {
  final DateTime timestamp = DateTime.now();
  final String source;

  DeviceDiscoveryEvent(this.source);

  Map<String, dynamic> toJson();
}

/// 找到裝置的事件
class DeviceFoundEvent extends DeviceDiscoveryEvent {
  final DiscoveredDevice device;

  DeviceFoundEvent(this.device, String source) : super(source);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'device_found',
    'timestamp': timestamp.toIso8601String(),
    'source': source,
    'device': device.toJson(),
  };
}

/// 搜尋開始事件
class SearchStartedEvent extends DeviceDiscoveryEvent {
  final String deviceType;

  SearchStartedEvent(this.deviceType, String source) : super(source);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'search_started',
    'timestamp': timestamp.toIso8601String(),
    'source': source,
    'deviceType': deviceType,
  };
}

/// 搜尋完成事件
class SearchCompleteEvent extends DeviceDiscoveryEvent {
  final String deviceType;
  final int deviceCount;

  SearchCompleteEvent(this.deviceType, this.deviceCount, String source)
    : super(source);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'search_complete',
    'timestamp': timestamp.toIso8601String(),
    'source': source,
    'deviceType': deviceType,
    'deviceCount': deviceCount,
  };
}

/// 搜尋錯誤事件
class SearchErrorEvent extends DeviceDiscoveryEvent {
  final String error;
  final String deviceType;

  SearchErrorEvent(this.deviceType, this.error, String source) : super(source);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'search_error',
    'timestamp': timestamp.toIso8601String(),
    'source': source,
    'deviceType': deviceType,
    'error': error,
  };
}
