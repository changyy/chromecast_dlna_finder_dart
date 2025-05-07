import 'package:chromecast_dlna_finder/chromecast_dlna_finder.dart';
import 'package:chromecast_dlna_finder/src/util/localization_manager.dart';
import 'package:chromecast_dlna_finder/src/util/logger.dart';
import 'package:test/test.dart';

void main() {
  group('ChromecastDlnaFinder core functionality tests', () {
    late ChromecastDlnaFinder finder;

    setUp(() {
      finder = ChromecastDlnaFinder();
    });

    tearDown(() async {
      await finder.dispose();
    });

    test('Initialization test', () {
      expect(finder, isNotNull);
    });

    test('Logger configuration test', () async {
      await finder.configureLogger(outputs: {}, minLevel: AppLogLevel.debug);
      // No exceptions should be thrown
      expect(true, isTrue);
    });
  });

  group('Device model tests', () {
    test('DiscoveredDevice serialization test', () {
      final device = DiscoveredDevice(
        name: 'Test Device',
        ip: '192.168.1.100',
        port: 8000,
        type: DeviceType.dlnaRenderer,
        model: 'Test Model',
        location: 'http://192.168.1.100:8000/desc.xml',
        avTransportControlUrl: 'http://192.168.1.100:8000/control',
        renderingControlUrl: 'http://192.168.1.100:8000/rendering',
      );

      final json = device.toJson();

      expect(json['name'], equals('Test Device'));
      expect(json['ip'], equals('192.168.1.100'));
      expect(json['port'], equals(8000));
      expect(json['type'], equals('dlnaRenderer'));
      expect(json['model'], equals('Test Model'));
      expect(json['location'], equals('http://192.168.1.100:8000/desc.xml'));
      expect(
        json['avTransportControlUrl'],
        equals('http://192.168.1.100:8000/control'),
      );
      expect(
        json['renderingControlUrl'],
        equals('http://192.168.1.100:8000/rendering'),
      );
    });

    test('DeviceType conversion test', () {
      expect(
        DeviceType.chromecastDongle.toString().split('.').last,
        equals('chromecastDongle'),
      );
      expect(
        DeviceType.chromecastAudio.toString().split('.').last,
        equals('chromecastAudio'),
      );
      expect(
        DeviceType.dlnaRenderer.toString().split('.').last,
        equals('dlnaRenderer'),
      );
      expect(
        DeviceType.dlnaMediaServer.toString().split('.').last,
        equals('dlnaMediaServer'),
      );
      expect(DeviceType.unknown.toString().split('.').last, equals('unknown'));
    });
  });

  group('Localization tests', () {
    late LocalizationManager locManager;

    setUp(() async {
      locManager = LocalizationManager();
      await locManager.init(locale: 'en');
      // Force English language
      await locManager.setLocale('en');
    });

    test('Loading localization files test', () {
      expect(locManager.currentLocale, equals('en'));
      expect(locManager.isInitialized, isTrue);
    });

    test('Getting localized text test', () {
      final text = locManager.get(
        'info.start_device_scan',
        params: {'timeout': 10},
      );
      expect(text, isNotEmpty);
      expect(text, contains('10'));
    });

    test('Changing language test', () async {
      await locManager.setLocale('zh-tw');
      expect(locManager.currentLocale, equals('zh-tw'));

      // Switch back to English
      await locManager.setLocale('en');
    });
  });

  group('DiscoveryService mock tests', () {
    test('JSON format conversion test', () {
      final discoveryService = DiscoveryService();

      // Create mock device data
      final devices = {
        'chromecast': <DiscoveredDevice>[
          DiscoveredDevice(
            name: 'Living Room TV',
            ip: '192.168.1.101',
            type: DeviceType.chromecastDongle,
          ),
        ],
        'chromecast_dongle': <DiscoveredDevice>[
          DiscoveredDevice(
            name: 'Living Room TV',
            ip: '192.168.1.101',
            type: DeviceType.chromecastDongle,
          ),
        ],
        'chromecast_audio': <DiscoveredDevice>[],
        'dlna': <DiscoveredDevice>[
          DiscoveredDevice(
            name: 'Media Server',
            ip: '192.168.1.102',
            type: DeviceType.dlnaMediaServer,
          ),
        ],
        'dlna_renderer': <DiscoveredDevice>[],
        'dlna_media_server': <DiscoveredDevice>[
          DiscoveredDevice(
            name: 'Media Server',
            ip: '192.168.1.102',
            type: DeviceType.dlnaMediaServer,
          ),
        ],
        'errors': <DiscoveredDevice>[],
      };

      final json = discoveryService.toJson(devices);

      expect(json['status'], isTrue);
      expect(json['error'], isEmpty);
      expect(json['chromecast'], hasLength(1));
      expect(json['chromecast_dongle'], hasLength(1));
      expect(json['chromecast_audio'], isEmpty);
      expect(json['dlna'], hasLength(1));
      expect(json['dlna_renderer'], isEmpty);
      expect(json['dlna_media_server'], hasLength(1));
    });
  });
}
