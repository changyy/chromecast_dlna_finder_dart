import 'mdns_channel_interface.dart';

/// Dart CLI/IO implementation: not supported, just throw
class MdnsChannelIo implements MdnsChannel {
  @override
  Future<List<Map<String, dynamic>>> discoverServices(String type) async {
    throw UnsupportedError('mDNS discovery is only available on iOS/Flutter.');
  }
}

final MdnsChannel mdnsChannel = MdnsChannelIo();
