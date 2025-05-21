/// 裝置資料結構
enum DeviceType {
  dlnaRenderer,
  dlnaMediaServer,
  chromecastDongle,
  chromecastAudio,
  airplay, // 新增 AirPlay 型別
  unknown,
}

class DiscoveredDevice {
  final String name;
  final String ip;
  final DeviceType type;
  final String? model;
  final String? location; // description.xml or mDNS serviceName
  final String? avTransportControlUrl; // 只有 DLNA renderer 會有
  final String? renderingControlUrl; // 只有 DLNA renderer 會有

  // Chromecast 專屬欄位
  final String? id; // Chromecast TXT record 的 id
  final String? friendlyName; // Chromecast TXT record 的 fn
  final int? port; // Chromecast SRV record 的 port
  final Map<String, String>? extra; // Chromecast 其他 TXT 欄位
  final List<String>? mdnsTypes; // 新增: mDNS 服務型別

  DiscoveredDevice({
    required this.name,
    required this.ip,
    required this.type,
    this.model,
    this.location,
    this.avTransportControlUrl,
    this.renderingControlUrl,
    this.id,
    this.friendlyName,
    this.port,
    this.extra,
    this.mdnsTypes, // 新增
  });

  bool get isDlnaRenderer =>
      type == DeviceType.dlnaRenderer &&
      avTransportControlUrl != null &&
      renderingControlUrl != null;
  bool get isDlnaMediaServer => type == DeviceType.dlnaMediaServer;
  bool get isChromecastDongle => type == DeviceType.chromecastDongle;
  bool get isChromecastAudio => type == DeviceType.chromecastAudio;
  bool get isChromecast =>
      type == DeviceType.chromecastDongle || type == DeviceType.chromecastAudio;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'ip': ip,
      'type': type.toString().split('.').last,
      if (model != null) 'model': model,
      if (location != null) 'location': location,
      if (avTransportControlUrl != null)
        'avTransportControlUrl': avTransportControlUrl,
      if (renderingControlUrl != null)
        'renderingControlUrl': renderingControlUrl,
      if (id != null) 'id': id,
      if (friendlyName != null) 'friendlyName': friendlyName,
      if (port != null) 'port': port,
      if (extra != null) 'extra': extra,
      if (mdnsTypes != null) 'mdnsTypes': mdnsTypes, // 新增
    };
  }

  /// Chromecast TXT record 轉換建構
  factory DiscoveredDevice.fromChromecast({
    required String ip,
    required int port,
    required String serviceName,
    required Map<String, String> txtMap,
  }) {
    // 判斷 Chromecast 類型
    DeviceType chromecastType = DeviceType.chromecastDongle;
    final model = txtMap['md']?.toLowerCase() ?? '';

    // 根據型號判斷是否為 Audio 設備
    if (model.contains('audio') || model.contains('speaker')) {
      chromecastType = DeviceType.chromecastAudio;
    }

    return DiscoveredDevice(
      name: txtMap['fn'] ?? serviceName,
      ip: ip,
      type: chromecastType,
      model: txtMap['md'],
      location: serviceName,
      id: txtMap['id'],
      friendlyName: txtMap['fn'],
      port: port,
      extra: txtMap,
    );
  }

  /// DLNA Renderer 建構工廠
  factory DiscoveredDevice.fromDlnaRenderer({
    required String name,
    required String ip,
    required String location,
    String? avTransportControlUrl,
    String? renderingControlUrl,
    String? model,
  }) {
    return DiscoveredDevice(
      name: name,
      ip: ip,
      type: DeviceType.dlnaRenderer,
      model: model,
      location: location,
      avTransportControlUrl: avTransportControlUrl,
      renderingControlUrl: renderingControlUrl,
    );
  }

  /// DLNA Media Server 建構工廠
  factory DiscoveredDevice.fromDlnaMediaServer({
    required String name,
    required String ip,
    required String location,
    String? model,
  }) {
    return DiscoveredDevice(
      name: name,
      ip: ip,
      type: DeviceType.dlnaMediaServer,
      model: model,
      location: location,
    );
  }

  /// AirPlay TXT record 轉換建構
  factory DiscoveredDevice.fromAirplay({
    required String ip,
    required int port,
    required String serviceName,
    required Map<String, String> txtMap,
    List<String>? mdnsTypes, // 新增
  }) {
    return DiscoveredDevice(
      name: txtMap['fn'] ?? txtMap['cn'] ?? serviceName, // AirPlay 常見欄位 fn/cn
      ip: ip,
      type: DeviceType.airplay,
      model: txtMap['md'],
      location: serviceName,
      id: txtMap['id'],
      friendlyName: txtMap['fn'] ?? txtMap['cn'],
      port: port,
      extra: txtMap,
      mdnsTypes: mdnsTypes, // 新增
    );
  }
}
