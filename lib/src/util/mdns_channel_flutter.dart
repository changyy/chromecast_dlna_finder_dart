// 此檔案已移除，請於 Flutter 專案中實作 MdnsChannelFlutter
/*
import 'package:flutter/services.dart';
import 'dart:io';
import 'mdns_channel.dart';

class MdnsChannelFlutter implements MdnsChannel {
  static const MethodChannel _channel = MethodChannel(
    'chromecast_dlna_finder/mdns',
  );

  @override
  Future<List<Map<String, dynamic>>> discoverServices(String type) async {
    if (!Platform.isIOS) throw UnsupportedError('Only available on iOS');
    final List result = await _channel.invokeMethod('discoverServices', {
      'type': type,
    });
    return result.cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}

final MdnsChannel mdnsChannel = MdnsChannelFlutter();
*/
