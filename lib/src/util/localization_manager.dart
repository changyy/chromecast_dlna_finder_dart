import 'dart:async';
import 'localization.dart';

/// 本地化管理類，負責加載和提供本地化的訊息
class LocalizationManager {
  static final LocalizationManager _instance = LocalizationManager._internal();
  factory LocalizationManager() => _instance;

  /// 當前使用的語言
  String _currentLocale = 'en';

  /// 翻譯文本快取
  Map<String, dynamic> _translations = {};

  /// 用於保存以防找不到翻譯時的原文字串
  final Set<String> _missingTranslations = {};

  /// 是否已完成初始化
  bool _initialized = false;
  Completer<void> _initCompleter = Completer<void>();

  /// 是否啟用詳細的除錯模式
  bool _debugMode = false;

  LocalizationManager._internal();

  /// 設置除錯模式
  void setDebugMode(bool enabled) {
    _debugMode = enabled;
  }

  /// 簡單的日誌輸出方法，避免循環依賴
  void _log(String message, {String? tag, bool isError = false}) {
    /*
    if (_debugMode || isError) {
      final now = DateTime.now().toString().split('.')[0];
      final tagStr = tag != null ? '[$tag] ' : '';
      final prefix = isError ? '[ERROR] ' : '[DEBUG] ';
      stderr.writeln('[$now]$prefix$tagStr$message');
    }
    */
  }

  /// 初始化本地化管理器
  Future<void> init({String? locale}) async {
    if (_initialized) {
      return;
    }

    _currentLocale =
        locale == null || locale.isEmpty || locale == 'auto'
            ? getSystemLocale()
            : locale;

    // 加載翻譯文件
    await _loadTranslations();

    _initialized = true;
    _initCompleter.complete();
  }

  /// 確保已初始化
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      if (!_initCompleter.isCompleted) {
        await _initCompleter.future;
      } else {
        _initCompleter = Completer<void>();
        await init();
      }
    }
  }

  /// 加載翻譯文件，支援 fallback: 語言-地區-變體 > 語言-地區 > 語言
  Future<void> _loadTranslations() async {
    try {
      _log('Loading translations for locale: $_currentLocale', tag: 'i18n');
      // fallback 順序
      List<String> fallbackLocales = [];
      String base = _currentLocale.replaceAll('-', '_');
      fallbackLocales.add(base);
      final parts = base.split('_');
      if (parts.length >= 2) {
        fallbackLocales.add(
          "${parts[0].toLowerCase()}_${parts[1].toUpperCase()}",
        );
      }
      fallbackLocales.add(parts.first.toLowerCase());
      fallbackLocales.add('en');
      _log('Fallback locales: $fallbackLocales', tag: 'i18n');
      Set<String> tried = {};
      for (final loc in fallbackLocales) {
        if (tried.contains(loc)) continue;
        tried.add(loc);
        try {
          final jsonMap = await loadTranslation(loc);
          _translations = jsonMap;
          if (_translations.isEmpty) {
            _log('No translations found for locale: $loc', tag: 'i18n');
            continue;
          }
          // 測試一個範例鍵，確認翻譯載入成功
          if (_translations.containsKey('info') &&
              (_translations['info'] as Map<String, dynamic>).containsKey(
                'start_chromecast_scan',
              )) {
            final sampleTranslation =
                (_translations['info']
                    as Map<String, dynamic>)['start_chromecast_scan'];
            _log(
              'Translation loaded successfully, sample: info.start_chromecast_scan = "$sampleTranslation"',
              tag: 'i18n',
            );
          }
          return;
        } catch (_) {
          // ignore, try next fallback
        }
      }
      // 全部失敗
      _translations = {};
    } catch (e) {
      _log('Failed to load translations: $e', tag: 'i18n', isError: true);
      _translations = {};
    }
  }

  /// 設置當前語言，並重新加載翻譯
  Future<void> setLocale(String locale) async {
    if (_currentLocale != locale) {
      _currentLocale = locale;
      await _loadTranslations();
    }
  }

  /// 獲取本地化的訊息
  String get(String key, {Map<String, dynamic>? params}) {
    // 使用點表示法讀取嵌套的鍵值
    List<String> keys = key.split('.');

    if (keys.isEmpty) {
      return _formatWithParams(key, params);
    }

    dynamic value = _translations;

    // 依序訪問各級鍵值
    for (var k in keys) {
      if (value is Map && value.containsKey(k)) {
        value = value[k];
      } else {
        // 鍵不存在，記錄缺失的翻譯並返回原始鍵值
        _recordMissingTranslation(key);
        return _formatWithParams(key, params);
      }
    }

    if (value is String) {
      return _formatWithParams(value, params);
    } else {
      // 值不是字串，記錄缺失的翻譯並返回原始鍵值
      _recordMissingTranslation(key);
      return _formatWithParams(key, params);
    }
  }

  /// 使用參數格式化訊息字串
  String _formatWithParams(String text, Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) {
      return text;
    }

    String result = text;
    params.forEach((key, value) {
      result = result.replaceAll('{$key}', value?.toString() ?? '');
    });

    return result;
  }

  /// 記錄缺失的翻譯
  void _recordMissingTranslation(String key) {
    _missingTranslations.add(key);
    if (_debugMode) {
      _log('Missing translation: $key', tag: 'i18n');
    }
  }

  /// 獲取當前設置的語言
  String get currentLocale => _currentLocale;

  /// 獲取所有缺失的翻譯
  Set<String> get missingTranslations => Set.from(_missingTranslations);

  /// 清除缺失翻譯的紀錄
  void clearMissingTranslations() {
    _missingTranslations.clear();
  }

  /// 檢查是否已初始化（公開方法）
  bool get isInitialized => _initialized;
}

/// 提供簡易訪問本地化訊息的全局方法
Future<String> tr(String key, {Map<String, dynamic>? params}) async {
  await LocalizationManager()._ensureInitialized();
  return LocalizationManager().get(key, params: params);
}

/// 同步版本的翻譯方法，如果尚未初始化則使用鍵名
String trSync(String key, {Map<String, dynamic>? params}) {
  if (!LocalizationManager().isInitialized) {
    // 如果尚未初始化，直接返回帶參數的鍵名
    if (params != null && params.isNotEmpty) {
      String result = key;
      params.forEach((k, v) {
        result = result.replaceAll('{$k}', v?.toString() ?? '');
      });
      return result;
    }
    return key;
  }
  return LocalizationManager().get(key, params: params);
}
