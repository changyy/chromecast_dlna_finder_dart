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
    String? locale = Platform.environment['LANG'] ?? 
                  Platform.environment['LC_ALL'] ?? 
                  Platform.environment['LC_MESSAGES'];
                  
    if (locale != null && locale.isNotEmpty) {
      // Typically in format "en_US.UTF-8"
      return _formatLocale(locale.split('.')[0]);
    }
  } else if (Platform.isWindows) {
    // Windows platform can be accessed through system calls, but simplified here
    String? locale = Platform.environment['LANG'] ?? 
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
  
  _log('Loading translations for locale: $locale (file: $fileLocale.json)', tag: 'i18n');
  
  try {
    // Try to load translation file from standard location
    final libPath = await _findLibPath();
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
        _log('Successfully parsed JSON with ${jsonMap.length} top-level keys', tag: 'i18n');
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
  final scriptDir = scriptPath.substring(0, scriptPath.lastIndexOf(Platform.pathSeparator));
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
  
  // 4. 檢查特定套件位置
  for (final path in [
    '$currentDir/packages/chromecast_dlna_finder',
    '${Platform.environment['HOME'] ?? ''}/packages/chromecast_dlna_finder',
    // 嘗試向上一級的相對路徑
    Directory(currentDir).parent.path,
    // 直接指定絕對路徑
    '/Volumes/Data/UserData/com.anydlna.app/chromecast_dlna_finder'
  ]) {
    final localesPath = '$path/lib/src/locales';
    possiblePaths.add(localesPath);
    
    if (await Directory(localesPath).exists()) {
      _log('Found locales directory at: $localesPath', tag: 'i18n');
      return path;
    }
  }
  
  // 如果找不到，記錄所有嘗試過的路徑，然後回傳當前目錄
  _log('Tried all the following paths but could not find locales directory:', tag: 'i18n', isError: true);
  for (final path in possiblePaths) {
    _log(' - $path', tag: 'i18n');
  }
  
  // 如果上述路徑都找不到，返回當前目錄
  return currentDir;
}