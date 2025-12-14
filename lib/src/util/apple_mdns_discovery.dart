import '../discovery/device.dart';
import 'apple_mdns_discovery_stub.dart'
    if (dart.library.ui) 'apple_mdns_discovery_flutter.dart';

/// Factory: returns platform-aware implementation (Flutter on Apple -> Bonjour, else no-op).
AppleMdnsDiscovery createAppleMdnsDiscovery() => AppleMdnsDiscoveryImpl();

abstract class AppleMdnsDiscovery {
  bool get isApplePlatform;
  Future<List<DiscoveredDevice>> discover({
    Duration timeout,
    List<String> types,
  });
}
