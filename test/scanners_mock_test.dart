import 'dart:async';
import 'package:chromecast_dlna_finder/src/discovery/device.dart';
import 'package:test/test.dart';

// Mock device list
final mockChromecastDevices = [
  DiscoveredDevice(
    name: 'Living Room Chromecast',
    ip: '192.168.1.101',
    type: DeviceType.chromecastDongle,
    model: 'Chromecast',
    id: 'abcdef123456',
    friendlyName: 'Living Room TV',
  ),
  DiscoveredDevice(
    name: 'Kitchen Speaker',
    ip: '192.168.1.102',
    type: DeviceType.chromecastAudio,
    model: 'Chromecast Audio',
    id: '123456abcdef',
    friendlyName: 'Kitchen Speaker',
  ),
];

final mockDlnaRenderers = [
  DiscoveredDevice(
    name: 'Living Room TV',
    ip: '192.168.1.103',
    type: DeviceType.dlnaRenderer,
    model: 'Smart TV',
    location: 'http://192.168.1.103:8000/desc.xml',
    avTransportControlUrl: 'http://192.168.1.103:8000/control',
    renderingControlUrl: 'http://192.168.1.103:8000/rendering',
  ),
];

final mockDlnaMediaServers = [
  DiscoveredDevice(
    name: 'Media NAS',
    ip: '192.168.1.104',
    type: DeviceType.dlnaMediaServer,
    model: 'NAS Server',
    location: 'http://192.168.1.104:8000/desc.xml',
  ),
];

// Mock scanChromecastDevices function
Future<List<DiscoveredDevice>> mockScanChromecastDevices() async {
  return mockChromecastDevices;
}

// Mock scanDlnaRendererDevices function
Future<List<DiscoveredDevice>> mockScanDlnaRendererDevices({Duration timeout = const Duration(seconds: 3)}) async {
  return mockDlnaRenderers;
}

// Mock scanDlnaMediaServerDevices function
Future<List<DiscoveredDevice>> mockScanDlnaMediaServerDevices({Duration timeout = const Duration(seconds: 3)}) async {
  return mockDlnaMediaServers;
}

// Mock scanAllDlnaDevices function
Future<List<DiscoveredDevice>> mockScanAllDlnaDevices({Duration timeout = const Duration(seconds: 3)}) async {
  return [...mockDlnaRenderers, ...mockDlnaMediaServers];
}

void main() {
  group('Scanner functionality tests', () {
    setUp(() async {
      // 移除未使用的 AppLogger 初始化
    });
    
    test('Chromecast scan test', () async {
      final devices = await mockScanChromecastDevices();
      
      expect(devices.length, equals(2));
      expect(devices[0].name, equals('Living Room Chromecast'));
      expect(devices[0].type, equals(DeviceType.chromecastDongle));
      expect(devices[1].name, equals('Kitchen Speaker'));
      expect(devices[1].type, equals(DeviceType.chromecastAudio));
    });
    
    test('DLNA Renderer scan test', () async {
      final devices = await mockScanDlnaRendererDevices();
      
      expect(devices.length, equals(1));
      expect(devices[0].name, equals('Living Room TV'));
      expect(devices[0].type, equals(DeviceType.dlnaRenderer));
      expect(devices[0].avTransportControlUrl, isNotNull);
      expect(devices[0].renderingControlUrl, isNotNull);
    });
    
    test('DLNA Media Server scan test', () async {
      final devices = await mockScanDlnaMediaServerDevices();
      
      expect(devices.length, equals(1));
      expect(devices[0].name, equals('Media NAS'));
      expect(devices[0].type, equals(DeviceType.dlnaMediaServer));
      expect(devices[0].location, isNotNull);
    });
    
    test('All DLNA devices scan test', () async {
      final devices = await mockScanAllDlnaDevices();
      
      expect(devices.length, equals(2));
      expect(devices.where((d) => d.type == DeviceType.dlnaRenderer).length, equals(1));
      expect(devices.where((d) => d.type == DeviceType.dlnaMediaServer).length, equals(1));
    });
    
    test('Device type validation test', () async {
      final chromecastDevices = await mockScanChromecastDevices();
      final dlnaRenderers = await mockScanDlnaRendererDevices();
      final dlnaMediaServers = await mockScanDlnaMediaServerDevices();
      
      // Test Chromecast type checks
      expect(chromecastDevices[0].isChromecast, isTrue);
      expect(chromecastDevices[0].isChromecastDongle, isTrue);
      expect(chromecastDevices[0].isChromecastAudio, isFalse);
      
      expect(chromecastDevices[1].isChromecast, isTrue);
      expect(chromecastDevices[1].isChromecastDongle, isFalse);
      expect(chromecastDevices[1].isChromecastAudio, isTrue);
      
      // Test DLNA type checks
      expect(dlnaRenderers[0].isDlnaRenderer, isTrue);
      expect(dlnaRenderers[0].isDlnaMediaServer, isFalse);
      
      expect(dlnaMediaServers[0].isDlnaRenderer, isFalse);
      expect(dlnaMediaServers[0].isDlnaMediaServer, isTrue);
    });
  });
}