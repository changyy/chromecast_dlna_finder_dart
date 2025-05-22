export 'mdns_channel_io.dart'
    if (dart.library.html) 'mdns_channel_web.dart'
    if (dart.library.js) 'mdns_channel_web.dart';
