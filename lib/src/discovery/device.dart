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
    String? location, // 可傳入 location
  }) {
    final bestName = pickBestName(
      txtMap: txtMap,
      fallback: txtMap['fn'] ?? txtMap['cn'],
      location: location ?? serviceName,
      serviceName: serviceName,
    );
    return DiscoveredDevice(
      name: bestName,
      ip: ip,
      type: DeviceType.airplay,
      model: txtMap['md'],
      location: location ?? serviceName,
      id: txtMap['id'],
      friendlyName: bestName,
      port: port,
      extra: txtMap,
      mdnsTypes: mdnsTypes, // 新增
    );
  }
}

// --- Best name picking for AirPlay/Chromecast ---
String pickBestName({
  required Map<String, String> txtMap,
  String? fallback,
  String? location,
  String? serviceName,
}) {
  // 1. 先嘗試從 location pattern 取名
  if (location != null) {
    final raopIdx = location.indexOf('._raop._tcp.local');
    final airplayIdx = location.indexOf('._airplay._tcp.local');
    if (raopIdx > 0 || airplayIdx > 0) {
      final endIdx = raopIdx > 0 ? raopIdx : airplayIdx;
      final atIdx = location.lastIndexOf('@', endIdx);
      if (atIdx >= 0 && endIdx > atIdx) {
        final name = location.substring(atIdx + 1, endIdx);
        if (name.trim().isNotEmpty) return name.trim();
      } else if (endIdx > 0) {
        // 沒有 @，直接取前綴
        final name = location.substring(0, endIdx);
        if (name.trim().isNotEmpty) return name.trim();
      }
    }
  }
  // 2. 其他 TXT 欄位
  final candidates = [
    txtMap['fn'],
    txtMap['friendlyName'],
    txtMap['cn'],
    txtMap['am'],
    txtMap['model'],
    txtMap['md'],
  ];
  for (final c in candidates) {
    if (c != null && c.trim().isNotEmpty && !_isMeaninglessName(c)) {
      return c.trim();
    }
  }
  // 3. fallback: 若 location 有 @，取 @ 後方
  if (location != null) {
    if (location.contains('@')) {
      final idx = location.indexOf('@');
      final afterAt = location.substring(idx + 1);
      if (afterAt.trim().isNotEmpty) return afterAt.trim();
    } else {
      return location.trim();
    }
  }
  // 4. fallback: serviceName
  if (serviceName != null && serviceName.trim().isNotEmpty) {
    return serviceName.trim();
  }
  // 5. fallback: 傳入 fallback
  return fallback ?? 'Unknown';
}

bool _isMeaninglessName(String name) {
  final n = name.trim();
  final regex = RegExp(r'^(\d+,?)+$');
  if (regex.hasMatch(n)) return true;
  return false;
}
