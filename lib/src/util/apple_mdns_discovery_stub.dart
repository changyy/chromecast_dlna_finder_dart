import '../discovery/device.dart';
import 'apple_mdns_discovery.dart';

/// Stub implementation for non-Apple or non-Flutter platforms.
class AppleMdnsDiscoveryImpl implements AppleMdnsDiscovery {
  @override
  bool get isApplePlatform => false;

  @override
  Future<List<DiscoveredDevice>> discover({
    Duration timeout = const Duration(seconds: 5),
    List<String> types = const [],
  }) async {
    return [];
  }
}
