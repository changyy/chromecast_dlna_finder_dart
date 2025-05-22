import 'mdns_channel.dart';
import 'mdns_channel_io.dart'
    if (dart.library.flutter) 'mdns_channel_flutter.dart';
import 'mdns_channel_interface.dart';

MdnsChannel getMdnsChannel() => mdnsChannel;
