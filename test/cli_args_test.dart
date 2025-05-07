import 'package:args/args.dart';
import 'package:test/test.dart';

void main() {
  group('Command line interface tests', () {
    late ArgParser parser;

    setUp(() {
      // Create command line arguments setup identical to the main program
      parser =
          ArgParser()
            ..addFlag(
              'help',
              abbr: 'h',
              negatable: false,
              help: 'Display help message',
            )
            ..addFlag(
              'minify',
              abbr: 'm',
              negatable: false,
              help: 'Output minified JSON format (not pretty)',
            )
            ..addFlag(
              'quiet',
              abbr: 'q',
              negatable: false,
              help:
                  'Quiet mode, only output JSON result without any debug messages',
            )
            ..addFlag(
              'debug',
              abbr: 'd',
              negatable: false,
              help: 'Enable debug level logging',
            )
            ..addOption(
              'lang',
              abbr: 'l',
              help: 'Specify language (en, zh-tw)',
              defaultsTo: '',
            )
            ..addOption(
              'timeout',
              abbr: 't',
              help: 'Scan timeout in seconds',
              defaultsTo: '15',
            );
    });

    test('Empty parameters test', () {
      final results = parser.parse([]);

      expect(results['help'], isFalse);
      expect(results['minify'], isFalse);
      expect(results['quiet'], isFalse);
      expect(results['debug'], isFalse);
      expect(results['lang'], isEmpty);
      expect(results['timeout'], equals('15'));
    });

    test('Timeout parameter test', () {
      final results = parser.parse(['--timeout', '10']);

      expect(results['timeout'], equals('10'));
    });

    test('Language parameter test', () {
      final results = parser.parse(['--lang', 'zh-tw']);

      expect(results['lang'], equals('zh-tw'));
    });

    test('Short form parameter test', () {
      final results = parser.parse(['-t', '20', '-l', 'en', '-q', '-d']);

      expect(results['timeout'], equals('20'));
      expect(results['lang'], equals('en'));
      expect(results['quiet'], isTrue);
      expect(results['debug'], isTrue);
    });

    test('Option combination test', () {
      final results = parser.parse([
        '--debug',
        '--quiet',
        '--minify',
        '--timeout',
        '30',
      ]);

      expect(results['debug'], isTrue);
      expect(results['quiet'], isTrue);
      expect(results['minify'], isTrue);
      expect(results['timeout'], equals('30'));
    });

    test('Invalid parameter test', () {
      expect(
        () => parser.parse(['--invalid']),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
