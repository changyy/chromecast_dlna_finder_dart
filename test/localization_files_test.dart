import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('Localization resource file tests', () {
    test('English language file integrity test', () async {
      final file = File('${Directory.current.path}/lib/src/locales/en.json');
      expect(
        await file.exists(),
        isTrue,
        reason: 'English language file should exist',
      );

      final content = await file.readAsString();
      expect(content, isNotEmpty);

      // Validate JSON format is correct
      final Map<String, dynamic> json = jsonDecode(content);
      expect(json, isNotEmpty);

      // Validate required keys exist
      expect(json.containsKey('info'), isTrue);
      expect(json.containsKey('errors'), isTrue);

      // Validate specific message keys exist
      final info = json['info'] as Map<String, dynamic>;
      expect(info.containsKey('start_device_scan'), isTrue);
      expect(info.containsKey('device_scan_completed'), isTrue);

      final errors = json['errors'] as Map<String, dynamic>;
      expect(errors.containsKey('chromecast_scan_error'), isTrue);
      expect(errors.containsKey('dlna_scan_error'), isTrue);
    });

    test('Traditional Chinese language file integrity test', () async {
      final file = File('${Directory.current.path}/lib/src/locales/zh_TW.json');
      expect(
        await file.exists(),
        isTrue,
        reason: 'Traditional Chinese language file should exist',
      );

      final content = await file.readAsString();
      expect(content, isNotEmpty);

      // Validate JSON format is correct
      final Map<String, dynamic> json = jsonDecode(content);
      expect(json, isNotEmpty);

      // Validate required keys exist
      expect(json.containsKey('info'), isTrue);
      expect(json.containsKey('errors'), isTrue);

      // Validate specific message keys exist
      final info = json['info'] as Map<String, dynamic>;
      expect(info.containsKey('start_device_scan'), isTrue);
      expect(info.containsKey('device_scan_completed'), isTrue);

      final errors = json['errors'] as Map<String, dynamic>;
      expect(errors.containsKey('chromecast_scan_error'), isTrue);
      expect(errors.containsKey('dlna_scan_error'), isTrue);
    });

    test('English and Chinese key consistency test', () async {
      final enFile = File('${Directory.current.path}/lib/src/locales/en.json');
      final zhTwFile = File(
        '${Directory.current.path}/lib/src/locales/zh_TW.json',
      );

      final enContent = await enFile.readAsString();
      final zhTwContent = await zhTwFile.readAsString();

      final Map<String, dynamic> enJson = jsonDecode(enContent);
      final Map<String, dynamic> zhTwJson = jsonDecode(zhTwContent);

      // Check all top-level keys in English file also exist in Chinese file
      for (final key in enJson.keys) {
        expect(
          zhTwJson.containsKey(key),
          isTrue,
          reason: 'Traditional Chinese file missing top-level key: $key',
        );
      }

      // Check all keys in the info section of English file also exist in Chinese file
      final enInfo = enJson['info'] as Map<String, dynamic>;
      final zhTwInfo = zhTwJson['info'] as Map<String, dynamic>;

      for (final key in enInfo.keys) {
        expect(
          zhTwInfo.containsKey(key),
          isTrue,
          reason: 'Traditional Chinese file missing info section key: $key',
        );
      }

      // Check all keys in the errors section of English file also exist in Chinese file
      final enErrors = enJson['errors'] as Map<String, dynamic>;
      final zhTwErrors = zhTwJson['errors'] as Map<String, dynamic>;

      for (final key in enErrors.keys) {
        expect(
          zhTwErrors.containsKey(key),
          isTrue,
          reason: 'Traditional Chinese file missing errors section key: $key',
        );
      }
    });
  });
}
