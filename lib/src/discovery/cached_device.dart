import 'device.dart';

class CachedDevice {
  final DiscoveredDevice device;
  DateTime lastSeen;
  bool lastScanOnline;
  CachedDevice({
    required this.device,
    required this.lastSeen,
    required this.lastScanOnline,
  });
}
