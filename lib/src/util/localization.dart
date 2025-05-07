import 'dart:io' show File, Platform, Directory, stderr;
import 'dart:convert';
// Conditional imports to allow the compiler to ignore these in non-Flutter environments
import 'dart:async';

// 全局除錯模式設定
bool _debugMode = false;

/// 設置除錯模式
void setLocalizationDebugMode(bool enabled) {
  _debugMode = enabled;
}

// Check if running in command line mode
bool get isCommandLineMode => !_isWebPlatform;
bool get _isWebPlatform => identical(0, 0.0);

/// 簡化版本 - 取得系統語言設定
String getSystemLocale() {
  // 從命令列環境變數中取得語言設定
  return _getCommandLineLocale();
}

/// Get locale settings from command line environment variables
String _getCommandLineLocale() {
  // Try to get from environment variables (mainly for terminal mode)
  if (Platform.isLinux || Platform.isMacOS) {
    String? locale =
        Platform.environment['LANG'] ??
        Platform.environment['LC_ALL'] ??
        Platform.environment['LC_MESSAGES'];

    if (locale != null && locale.isNotEmpty) {
      // Typically in format "en_US.UTF-8"
      return _formatLocale(locale.split('.')[0]);
    }
  } else if (Platform.isWindows) {
    // Windows platform can be accessed through system calls, but simplified here
    String? locale =
        Platform.environment['LANG'] ??
        Platform.environment['LANGUAGE'] ??
        Platform.environment['LC_ALL'];
    if (locale != null && locale.isNotEmpty) {
      return _formatLocale(locale);
    }
  }

  // Try to get system language code (all platforms)
  try {
    return _formatLocale(Platform.localeName);
  } catch (e) {
    // Ignore errors, default to English
  }

  return 'en'; // Default language
}

/// Format locale string to standard format (e.g., zh-tw)
String _formatLocale(String locale) {
  // Remove irrelevant characters
  locale = locale.replaceAll('_', '-');

  // Ensure hyphen and lowercase
  if (locale.contains('-')) {
    final parts = locale.toLowerCase().split('-');
    // Some formats like zh-hant-tw processed to zh-tw
    if (parts.length > 2 && parts[0] == 'zh') {
      return '${parts[0]}-${parts[parts.length - 1]}';
    }
    return locale.toLowerCase();
  }

  return locale.toLowerCase();
}

/// 日誌輸出方法
void _log(String message, {String? tag, bool isError = false}) {
  if (_debugMode || isError) {
    final now = DateTime.now().toString().split('.')[0];
    final tagStr = tag != null ? '[$tag] ' : '';
    final prefix = isError ? '[ERROR] ' : '[DEBUG] ';
    stderr.writeln('[$now]$prefix$tagStr$message');
  }
}

/// Load translations for specified locale
Future<Map<String, dynamic>> loadTranslation(String locale) async {
  // Convert locale format to filename format (zh-tw → zh_TW.json)
  String fileLocale = locale.toLowerCase();
  if (fileLocale.contains('-')) {
    final parts = fileLocale.split('-');
    if (parts.length >= 2) {
      fileLocale = '${parts[0]}_${parts[1].toUpperCase()}';
    }
  }

  _log(
    'Loading translations for locale: $locale (file: $fileLocale.json)',
    tag: 'i18n',
  );

  try {
    // Try to load translation file from standard location
    final libPath = await _findLibPath();

    // 檢查是否使用內嵌資源
    if (libPath.endsWith('__embedded__')) {
      _log('Using embedded translations for $locale', tag: 'i18n');
      final embeddedTranslations = _getEmbeddedTranslations(locale);
      if (embeddedTranslations.isNotEmpty) {
        return embeddedTranslations;
      } else {
        // 如果找不到指定語言的內嵌翻譯，使用英文
        _log(
          'No embedded translations for $locale, falling back to English',
          tag: 'i18n',
        );
        return _getEmbeddedTranslations('en');
      }
    }

    final filePath = '$libPath/lib/src/locales/$fileLocale.json';
    final file = File(filePath);

    _log('Trying to load translation file from: $filePath', tag: 'i18n');

    // Check if file exists
    if (await file.exists()) {
      _log('Found translation file at: $filePath', tag: 'i18n');

      // Load and parse JSON file
      final jsonString = await file.readAsString();
      _log('Read JSON content (${jsonString.length} chars)', tag: 'i18n');

      try {
        // Directly parse as Map<String, dynamic> not Map<String, String>
        final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
        _log(
          'Successfully parsed JSON with ${jsonMap.length} top-level keys',
          tag: 'i18n',
        );
        return jsonMap;
      } catch (parseError) {
        _log('Error parsing JSON: $parseError', tag: 'i18n', isError: true);
        return {};
      }
    } else {
      // 不再輸出 error log，讓 fallback 機制安靜進行
      // fallback 行為交由上層處理
    }
  } catch (e) {
    // Return empty dictionary on error
    _log('Unable to load locale file: $e', tag: 'i18n', isError: true);
  }

  // 如果無法從檔案讀取，嘗試使用內嵌翻譯
  final embeddedTranslations = _getEmbeddedTranslations(locale);
  if (embeddedTranslations.isNotEmpty) {
    _log('Using embedded translations as last resort for $locale', tag: 'i18n');
    return embeddedTranslations;
  }

  // Return empty dictionary if all methods fail
  _log('Returning empty translation map', tag: 'i18n');
  return {};
}

/// Find lib path
Future<String> _findLibPath() async {
  // Try to locate the library file
  final currentDir = Directory.current.path;

  // 記錄各種可能的路徑，方便除錯
  final List<String> possiblePaths = [];

  // 1. 檢查當前目錄是否有 lib/src/locales 文件夾
  final currentLocalesPath = '$currentDir/lib/src/locales';
  possiblePaths.add(currentLocalesPath);
  if (await Directory(currentLocalesPath).exists()) {
    _log('Found locales directory at: $currentLocalesPath', tag: 'i18n');
    return currentDir;
  }

  // 2. 檢查從腳本路徑判斷的位置
  final scriptPath = Platform.script.toFilePath();
  final scriptDir = scriptPath.substring(
    0,
    scriptPath.lastIndexOf(Platform.pathSeparator),
  );
  final scriptLocalesPath = '$scriptDir/lib/src/locales';
  possiblePaths.add(scriptLocalesPath);

  if (await Directory(scriptLocalesPath).exists()) {
    _log('Found locales directory at: $scriptLocalesPath', tag: 'i18n');
    return scriptDir;
  }

  // 3. 嘗試向上一級尋找
  final parentDir = Directory(currentDir).parent.path;
  final parentLocalesPath = '$parentDir/lib/src/locales';
  possiblePaths.add(parentLocalesPath);

  if (await Directory(parentLocalesPath).exists()) {
    _log('Found locales directory at: $parentLocalesPath', tag: 'i18n');
    return parentDir;
  }

  // 4. 檢查依賴套件位置 (dependency mode)
  // 當套件被其他專案作為依賴引入時
  final dependencyPaths = [
    // Dart/Flutter 專案標準路徑
    '$currentDir/packages/chromecast_dlna_finder',
    '$parentDir/packages/chromecast_dlna_finder',
    // pub cache 下的依賴路徑
    '${Platform.environment['HOME'] ?? ''}/.pub-cache/hosted/pub.dev/chromecast_dlna_finder-1.0.3',
  ];

  // 也嘗試檢查 pubspec.lock 來定位確切路徑
  final pubspecLockPath = '$currentDir/pubspec.lock';
  if (await File(pubspecLockPath).exists()) {
    try {
      final content = await File(pubspecLockPath).readAsString();
      final regex = RegExp(
        r'chromecast_dlna_finder:.*?path: "([^"]+)"',
        dotAll: true,
      );
      final match = regex.firstMatch(content);
      if (match != null && match.groupCount >= 1) {
        final path = match.group(1);
        if (path != null) {
          dependencyPaths.add(path);
        }
      }
    } catch (e) {
      _log('Error parsing pubspec.lock: $e', tag: 'i18n');
    }
  }

  // 檢查所有可能的依賴路徑
  for (final path in dependencyPaths) {
    final localesPath = '$path/lib/src/locales';
    possiblePaths.add(localesPath);

    if (await Directory(localesPath).exists()) {
      _log(
        'Found locales directory in dependency path: $localesPath',
        tag: 'i18n',
      );
      return path;
    }
  }

  // 5. 檢查特定套件位置
  for (final path in [
    '$currentDir/packages/chromecast_dlna_finder',
    '${Platform.environment['HOME'] ?? ''}/packages/chromecast_dlna_finder',
    // 嘗試向上一級的相對路徑
    Directory(currentDir).parent.path,
    // 直接指定絕對路徑
    '/Volumes/Data/UserData/com.anydlna.app/chromecast_dlna_finder',
  ]) {
    final localesPath = '$path/lib/src/locales';
    possiblePaths.add(localesPath);

    if (await Directory(localesPath).exists()) {
      _log('Found locales directory at: $localesPath', tag: 'i18n');
      return path;
    }
  }

  // 6. 檢查全域安裝的路徑
  // Dart pub global 安裝目錄
  final homeDir = Platform.environment['HOME'] ?? '';
  final dartCacheDir = '$homeDir/.pub-cache';

  // 檢查全域安裝的不同可能路徑
  for (final globalPath in [
    // 透過 pub global activate 安裝的路徑
    '$dartCacheDir/global_packages/chromecast_dlna_finder',
    // 透過 pub global activate --source path 安裝的路徑
    '$dartCacheDir/linked/chromecast_dlna_finder',
    // 檢查版本子目錄
    '$dartCacheDir/hosted/pub.dartlang.org/chromecast_dlna_finder-1.0.3',
    '$dartCacheDir/hosted/pub.dev/chromecast_dlna_finder-1.0.3',
  ]) {
    final globalLocalesPath = '$globalPath/lib/src/locales';
    possiblePaths.add(globalLocalesPath);

    if (await Directory(globalLocalesPath).exists()) {
      _log(
        'Found locales directory at global path: $globalLocalesPath',
        tag: 'i18n',
      );
      return globalPath;
    }
  }

  // 7. 遞迴搜尋 pub cache 和 packages 目錄
  try {
    // 檢查 .pub-cache 目錄
    final cacheDir = Directory(dartCacheDir);
    if (await cacheDir.exists()) {
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is Directory &&
            entity.path.contains('chromecast_dlna_finder') &&
            await Directory('${entity.path}/lib/src/locales').exists()) {
          _log(
            'Found locales directory in cache: ${entity.path}/lib/src/locales',
            tag: 'i18n',
          );
          return entity.path;
        }
      }
    }

    // 檢查當前專案的 packages 目錄
    final packagesDir = Directory('$currentDir/packages');
    if (await packagesDir.exists()) {
      await for (final entity in packagesDir.list(recursive: true)) {
        if (entity is Directory &&
            entity.path.contains('chromecast_dlna_finder') &&
            await Directory('${entity.path}/lib/src/locales').exists()) {
          _log(
            'Found locales directory in packages: ${entity.path}/lib/src/locales',
            tag: 'i18n',
          );
          return entity.path;
        }
      }
    }
  } catch (e) {
    _log('Error during recursive search: $e', tag: 'i18n');
  }

  // 8. 檢查 Flutter 應用程序中的資產路徑
  // Flutter 應用中，資源通常在應用的資產目錄
  try {
    // 嘗試常見的 Flutter 資產路徑
    final flutterPaths = [
      // Android 標準路徑
      '/data/data/${_getPackageName()}/files/flutter_assets/packages/chromecast_dlna_finder/lib/src/locales',
      '/data/user/0/${_getPackageName()}/files/flutter_assets/packages/chromecast_dlna_finder/lib/src/locales',
      // iOS 標準路徑
      '$currentDir/Frameworks/App.framework/flutter_assets/packages/chromecast_dlna_finder/lib/src/locales',
      // Mac 應用標準路徑
      '$currentDir/Resources/flutter_assets/packages/chromecast_dlna_finder/lib/src/locales',
      // Windows/Linux 標準路徑
      '$currentDir/flutter_assets/packages/chromecast_dlna_finder/lib/src/locales',
      '$currentDir/data/flutter_assets/packages/chromecast_dlna_finder/lib/src/locales',
    ];

    for (final path in flutterPaths) {
      possiblePaths.add(path);
      if (await Directory(path).exists()) {
        _log('Found locales directory in Flutter assets: $path', tag: 'i18n');
        return path.substring(0, path.indexOf('/lib/src/locales'));
      }
    }

    // 嘗試從環境變數獲取 Flutter 資產路徑
    final flutterAssetsPath = Platform.environment['FLUTTER_ASSETS'];
    if (flutterAssetsPath != null) {
      final packageLocalesPath =
          '$flutterAssetsPath/packages/chromecast_dlna_finder/lib/src/locales';
      possiblePaths.add(packageLocalesPath);
      if (await Directory(packageLocalesPath).exists()) {
        _log(
          'Found locales from FLUTTER_ASSETS env: $packageLocalesPath',
          tag: 'i18n',
        );
        return packageLocalesPath.substring(
          0,
          packageLocalesPath.indexOf('/lib/src/locales'),
        );
      }
    }
  } catch (e) {
    _log('Error checking Flutter assets paths: $e', tag: 'i18n');
  }

  // 9. 最後嘗試內嵌翻譯資源
  // 嘗試直接從資源中讀取翻譯資料 (作為最後的備用方案)
  final embeddedEnglish = _getEmbeddedTranslations('en');
  if (embeddedEnglish.isNotEmpty) {
    _log('Using embedded translations as fallback', tag: 'i18n');
    // 返回一個臨時目錄，讓上層知道使用內嵌資源
    return '$currentDir/__embedded__';
  }

  // 如果上述路徑都找不到，返回當前目錄
  return currentDir;
}

/// 嘗試獲取當前應用程序包名
String _getPackageName() {
  try {
    // 嘗試從環境變數獲取
    if (Platform.environment.containsKey('APP_PACKAGE_NAME')) {
      return Platform.environment['APP_PACKAGE_NAME']!;
    }

    // 由於在 Dart 中無法直接獲取包名，我們依賴於 Flutter 框架或預先配置的環境變數
    // 這裡返回一個通用前綴，讓搜尋邏輯能部分匹配
    return 'com.example';
  } catch (e) {
    return 'com.example';
  }
}

/// 提供內嵌的翻譯資源作為備用方案
Map<String, dynamic> _getEmbeddedTranslations(String locale) {
  // 英文作為基本備用翻譯
  if (locale == 'en') {
    return {
      'info': {
        'start_device_scan': 'Starting device scan...',
        'start_chromecast_scan': 'Starting Chromecast scan...',
        'start_dlna_renderer_scan': 'Starting DLNA renderer scan...',
        'start_all_dlna_scan': 'Starting DLNA device scan...',
        'device_scan_completed': 'Device scan completed',
        'found_chromecast_device': 'Found Chromecast device: {name} ({ip})',
        'found_dlna_renderer': 'Found DLNA renderer: {name} ({ip})',
      },
      'errors': {
        'chromecast_scan_error': 'Error scanning for Chromecast devices',
        'dlna_scan_error': 'Error scanning for DLNA devices',
        'parse_control_urls_failed': 'Failed to parse control URLs',
      },
    };
  }
  // 其他語言可以在這裡添加
  return {}; // 空字典表示沒有內嵌翻譯
}
