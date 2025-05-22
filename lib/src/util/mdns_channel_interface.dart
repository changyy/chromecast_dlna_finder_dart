/// mDNS channel interface for platform abstraction
abstract class MdnsChannel {
  Future<List<Map<String, dynamic>>> discoverServices(String type);
}
