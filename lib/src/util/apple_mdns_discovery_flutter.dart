// ignore_for_file: depend_on_referenced_packages, uri_does_not_exist, undefined_class, non_type_in_catch_clause, creation_with_non_type
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

import '../discovery/device.dart';
import '../util/logger.dart';
import 'apple_mdns_discovery.dart';

class AppleMdnsDiscoveryImpl implements AppleMdnsDiscovery {
  static const _channelName = 'chromecast_dlna_finder/mdns';
  static const _methodBrowse = 'browse';
  static const _defaultTypes = <String>[
    '_googlecast._tcp',
    '_airplay._tcp',
    '_raop._tcp',
    '_chromecast._tcp',
    '_http._tcp',
  ];

  final MethodChannel _channel = const MethodChannel(_channelName);
  final AppLogger _logger = AppLogger();

  @override
  bool get isApplePlatform {
    try {
      return Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<DiscoveredDevice>> discover({
    Duration timeout = const Duration(seconds: 5),
    List<String> types = _defaultTypes,
  }) async {
    if (!isApplePlatform) return [];
    try {
      final jsonString = await _channel.invokeMethod<String>(_methodBrowse, {
        'types': types,
        'timeoutMs': timeout.inMilliseconds,
      });
      if (jsonString == null) return [];
      final List<dynamic> decoded = jsonDecode(jsonString) as List<dynamic>;
      final devices =
          decoded.map((item) {
            final map = item as Map<String, dynamic>;
            final typeStr = map['type'] as String? ?? '';
            final host = map['host'] as String? ?? '';
            final port = map['port'] as int? ?? 0;
            final name = map['name'] as String? ?? host;
            return _toDiscoveredDevice(
              name: name,
              host: host,
              port: port,
              typeStr: typeStr,
            );
          }).toList();
      await _logger.info(
        '[AppleMdns] found ${devices.length} devices',
        tag: 'mDNS',
      );
      return devices;
    } on PlatformException catch (e) {
      await _logger.error(
        '[AppleMdns] platform_error ${e.code}',
        tag: 'mDNS',
        error: e,
        params: {'message': e.message},
      );
      if (e.code == 'permission_denied') {
        await _logger.error(
          'errors.permission_denied',
          tag: 'mDNS',
          params: {'hint': 'Check Local Network permission / entitlements'},
        );
      }
      return [];
    } catch (e) {
      await _logger.error(
        '[AppleMdns] unexpected_error',
        tag: 'mDNS',
        error: e,
      );
      return [];
    }
  }

  DiscoveredDevice _toDiscoveredDevice({
    required String name,
    required String host,
    required int port,
    required String typeStr,
  }) {
    final lower = typeStr.toLowerCase();
    if (lower.contains('googlecast') || lower.contains('chromecast')) {
      return DiscoveredDevice.fromChromecast(
        ip: host,
        port: port,
        serviceName: '$name.$typeStr',
        txtMap: const {},
      );
    }
    if (lower.contains('airplay') || lower.contains('raop')) {
      return DiscoveredDevice.fromAirplay(
        ip: host,
        port: port,
        serviceName: '$name.$typeStr',
        txtMap: const {},
        mdnsTypes: [typeStr],
        location: null,
      );
    }
    return DiscoveredDevice(
      name: name,
      ip: host,
      port: port,
      type: DeviceType.unknown,
      model: null,
      location: null,
      avTransportControlUrl: null,
      renderingControlUrl: null,
      id: null,
      friendlyName: null,
      extra: const {},
      mdnsTypes: [typeStr],
    );
  }
}
