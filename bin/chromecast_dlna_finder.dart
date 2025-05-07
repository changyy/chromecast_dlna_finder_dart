import 'dart:io';
import 'package:args/args.dart';
import 'package:chromecast_dlna_finder/chromecast_dlna_finder.dart';
import 'package:chromecast_dlna_finder/src/util/logger.dart';
import 'package:chromecast_dlna_finder/src/util/localization.dart';
import 'package:chromecast_dlna_finder/src/util/localization_manager.dart';

void main(List<String> arguments) async {
  // Default timeout setting
  int timeoutSeconds = 15;

  // Command line argument parsing
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Display help message')
    ..addFlag('minify', abbr: 'm', negatable: false, help: 'Output minified JSON format (not pretty)')
    ..addFlag('quiet', abbr: 'q', negatable: false, help: 'Quiet mode, only output JSON result without any debug messages')
    ..addFlag('debug', abbr: 'd', negatable: false, help: 'Enable debug level logging')
    ..addOption('lang', abbr: 'l', help: 'Specify language (en, zh-tw)', defaultsTo: 'auto')
    ..addOption('timeout', abbr: 't', help: 'Scan timeout in seconds', defaultsTo: '$timeoutSeconds')
    ;

  try {
    final results = parser.parse(arguments);
    
    // 設置除錯模式
    final bool isDebug = results['debug'];
    final bool isQuiet = results['quiet'];
    
    // 啟用或禁用本地化系統的除錯輸出
    setLocalizationDebugMode(isDebug && !isQuiet);
    
    // Set language to English by default
    String lang = results['lang'];

    // 先設置 LocalizationManager 的除錯模式，避免循環依賴
    final locManager = LocalizationManager();
    locManager.setDebugMode(isDebug && !isQuiet);
    
    // Initialize the localization manager with the specified language
    await locManager.init(locale: lang);
    
    // Show help information
    if (results['help']) {
      printUsage(parser);
      return;
    }
    
    try {
      timeoutSeconds = int.parse(results['timeout']);
      if (timeoutSeconds < 1) timeoutSeconds = 1;
      if (timeoutSeconds > 30) timeoutSeconds = 30;
    } catch (e) {
      stderr.writeln('Invalid timeout setting, using default value of $timeoutSeconds seconds');
    }
    
    // Pretty output by default, unless --minify is specified
    final bool pretty = !results['minify'];

    // 先決定 logLevel
    AppLogLevel logLevel = isDebug ? AppLogLevel.debug : AppLogLevel.info;

    // 根據 --quiet 決定 log 輸出通道
    final outputs = isQuiet ? <LoggerOutput>{} : {LoggerOutput.stderr};

    // Initialize scanner
    final finder = ChromecastDlnaFinder();
    await finder.configureLogger(
      outputs: outputs,
      minLevel: logLevel,
    );
    
    // 現在再初始化 AppLogger
    final logger = AppLogger();
    logger.setOutputs(outputs);
    logger.setMinLevel(logLevel);
    await logger.init();
    
    // Log the language being used
    await logger.debug('Detected system language: $lang', tag: 'Localization');
    
    // Log start message - 使用本地化鍵，先 tr 再 log
    await logger.info(await tr('info.start_device_scan', params: {'timeout': timeoutSeconds}), tag: 'Finder');
    
    // Start scanning
    final jsonString = await finder.findDevicesAsJsonString(
      timeout: Duration(seconds: timeoutSeconds),
      pretty: pretty,
    );
    
    // Output JSON result to stdout
    stdout.writeln(jsonString);
    
    // Log completion message - 使用本地化鍵，先 tr 再 log
    await logger.info(await tr('info.device_scan_completed'), tag: 'Finder');
    
    // Release resources
    await finder.dispose();
    
  } catch (e, stack) {
    stderr.writeln('Error: $e');
    stderr.writeln(stack);
    printUsage(parser);
    exit(1);
  }
}

void printUsage(ArgParser parser) {
  stdout.writeln('Chromecast & DLNA Device Scanner');
  stdout.writeln('');
  stdout.writeln('Usage: chromecast_dlna_finder [options]');
  stdout.writeln('');
  stdout.writeln('Options:');
  stdout.writeln(parser.usage);
  stdout.writeln('');
  stdout.writeln('Output is in JSON format with the following structure:');
  stdout.writeln('''
{
  "status": true,               // Operation success status
  "error": [],                  // List of error messages
  "chromecast": [],             // All Chromecast devices
  "chromecast_dongle": [],      // Chromecast video devices
  "chromecast_audio": [],       // Chromecast audio devices
  "dlna": [],                   // All DLNA devices
  "dlna_renderer": [],          // DLNA renderer devices
  "dlna_media_server": []       // DLNA media servers
}
''');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln('  chromecast_dlna_finder                     # Default: pretty JSON output with progress messages');
  stdout.writeln('  chromecast_dlna_finder --minify            # Output minified JSON');
  stdout.writeln('  chromecast_dlna_finder --timeout 10        # Set scan timeout to 10 seconds');
  stdout.writeln('  chromecast_dlna_finder --quiet             # Only output JSON result without any log messages');
  stdout.writeln('  chromecast_dlna_finder --debug             # Enable debug level logging');
}