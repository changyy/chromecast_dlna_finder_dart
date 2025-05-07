import 'dart:io';
import 'dart:async';
import 'package:logcraft/logcraft.dart';
import 'localization_manager.dart';

/// 日誌級別設定
enum AppLogLevel {
  debug,  // 調試模式
  info,   // 信息
  warning, // 警告
  error   // 錯誤
}

/// 日誌輸出通道
enum LoggerOutput { stderr, stdout, broadcast }

/// stderr輸出的LogSink，確保同步輸出並使用更明顯的格式
class StderrSink implements LogSink {
  // ANSI 顏色代碼
  static const String _resetColor = '\x1b[0m';
  static const String _debugColor = '\x1b[36m'; // 青色
  static const String _infoColor = '\x1b[32m';  // 綠色
  static const String _warningColor = '\x1b[33m'; // 黃色 
  static const String _errorColor = '\x1b[31m'; // 紅色

  @override
  Future<void> write(String message, LogLevel level) async {
    String color;
    
    // 根據日誌級別設置顏色
    switch (level) {
      case LogLevel.debug:
        color = _debugColor;
        break;
      case LogLevel.info:
        color = _infoColor;
        break;
      case LogLevel.warning:
        color = _warningColor;
        break;
      case LogLevel.error:
        color = _errorColor;
        break;
      default:
        color = _resetColor;
    }
    //
    // 同步輸出到stderr
    //stderr.writeln('$color$prefix$_resetColor $message');
    stderr.writeln('$color$message$_resetColor');
  }
  
  @override
  Future<void> dispose() async {
    // 無需處理
  }
}

/// 廣播型 LogSink，可讓外部監聽 log 訊息
class BroadcastSink implements LogSink {
  final StreamController<LogRecord> _controller = StreamController.broadcast();

  @override
  Future<void> write(String message, LogLevel level) async {
    _controller.add(LogRecord(message, level));
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  /// 提供外部監聽 log stream
  Stream<LogRecord> get stream => _controller.stream;
}

/// Log 訊息資料結構
class LogRecord {
  final String message;
  final LogLevel level;
  LogRecord(this.message, this.level);
}

/// 應用日誌輸出模式（未來可擴展到移動平台）
class AppSink implements LogSink {
  @override
  Future<void> write(String message, LogLevel level) async {
    // 在移動平台上，這裡可以改為使用平台特定的日誌系統
    // 例如Android的Log.d/i/w/e或iOS的NSLog
    // 目前暫時使用stdout
    stdout.writeln(message);
  }
  
  @override
  Future<void> dispose() async {
    // 無需處理
  }
}

/// 全局日誌服務
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;

  // 當前啟用的輸出通道
  Set<LoggerOutput> _outputs = {LoggerOutput.stderr};
  
  // 最低日誌級別
  AppLogLevel _minLevel = AppLogLevel.info;
  
  // 是否為移動平台
  bool _isMobilePlatform = false;
  
  // 是否已初始化
  bool _initialized = false;
  
  // 本地化管理器實例
  final _localization = LocalizationManager();

  // 廣播型 LogSink
  BroadcastSink? _broadcastSink;
  
  AppLogger._internal() {
    // 根據平台設置標識
    try {
      _isMobilePlatform = Platform.isAndroid || Platform.isIOS;
    } catch (e) {
      // 如果無法確定平台，默認為非移動平台
      _isMobilePlatform = false;
    }
  }
  
  /// 初始化日誌系統
  Future<void> init() async {
    if (_initialized) {
      // 如果已初始化，先釋放資源
      await dispose();
    }
    
    // 初始化本地化管理器
    await _localization.init();
    
    List<LogSink> sinks = [];
    
    if (_outputs.contains(LoggerOutput.stderr)) {
      sinks.add(StderrSink());
    }
    if (_outputs.contains(LoggerOutput.stdout)) {
      sinks.add(AppSink());
    }
    if (_outputs.contains(LoggerOutput.broadcast)) {
      _broadcastSink ??= BroadcastSink();
      sinks.add(_broadcastSink!);
    }
    
    LogLevel minLogcraftLevel;
    switch (_minLevel) {
      case AppLogLevel.debug:
        minLogcraftLevel = LogLevel.debug;
        break;
      case AppLogLevel.info:
        minLogcraftLevel = LogLevel.info;
        break;
      case AppLogLevel.warning:
        minLogcraftLevel = LogLevel.warning;
        break;
      case AppLogLevel.error:
        minLogcraftLevel = LogLevel.error;
        break;
    }
    
    await Logger.init(LoggerConfig(
      sinks: sinks,
      initialLevel: minLogcraftLevel,
      environment: Environment.development,
    ));
    
    _initialized = true;
  }
  
  /// 設定啟用哪些輸出通道
  void setOutputs(Set<LoggerOutput> outputs) {
    _outputs = outputs;
    _reinitializeIfNeeded();
  }

  /// 查詢目前啟用的輸出通道
  Set<LoggerOutput> get outputs => _outputs;

  /// 設定最低日誌級別
  void setMinLevel(AppLogLevel level) {
    _minLevel = level;
    _reinitializeIfNeeded();
  }

  /// 取得 log 廣播 stream（可 null）
  Stream<LogRecord>? get broadcastStream => _broadcastSink?.stream;
  
  /// 如果已初始化，重新初始化日誌系統
  void _reinitializeIfNeeded() {
    if (_initialized) {
      Logger.dispose().then((_) {
        _initialized = false;
        init();
      });
    }
  }
  
  /// 獲取當前最低日誌級別
  AppLogLevel get minLevel => _minLevel;
  
  /// 確保日誌系統已初始化
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }
  
  /// 記錄調試信息
  Future<void> debug(String message, {String? tag, Map<String, dynamic>? params}) async {
    await _ensureInitialized();
    
    if (_minLevel.index > AppLogLevel.debug.index) return;
    
    // 如果訊息是本地化鍵，先翻譯它
    String translatedMessage = message;
    if (message.contains('.') && !message.contains(' ')) {
      // 確保本地化管理器已初始化
      if (!LocalizationManager().isInitialized) {
        await LocalizationManager().init();
      }
      translatedMessage = LocalizationManager().get(message, params: params);
    } else if (params != null && params.isNotEmpty) {
      // 如果提供了參數但訊息不是本地化鍵，直接格式化
      translatedMessage = _formatMessage(message, params);
    }
    
    final taggedMessage = tag != null ? '[$tag] $translatedMessage' : translatedMessage;
    await Logger.debug(taggedMessage);
  }
  
  /// 記錄一般信息
  Future<void> info(String message, {String? tag, Map<String, dynamic>? params}) async {
    await _ensureInitialized();
    
    if (_minLevel.index > AppLogLevel.info.index) return;
    
    // 如果訊息是本地化鍵，先翻譯它
    String translatedMessage = message;
    if (message.contains('.') && !message.contains(' ')) {
      // 確保本地化管理器已初始化
      if (!LocalizationManager().isInitialized) {
        await LocalizationManager().init();
      }
      translatedMessage = LocalizationManager().get(message, params: params);
    } else if (params != null && params.isNotEmpty) {
      // 如果提供了參數但訊息不是本地化鍵，直接格式化
      translatedMessage = _formatMessage(message, params);
    }
    
    final taggedMessage = tag != null ? '[$tag] $translatedMessage' : translatedMessage;
    await Logger.info(taggedMessage);
  }
  
  /// 記錄警告信息
  Future<void> warning(String message, {String? tag, Map<String, dynamic>? params}) async {
    await _ensureInitialized();
    
    if (_minLevel.index > AppLogLevel.warning.index) return;
    
    // 如果訊息是本地化鍵，先翻譯它
    String translatedMessage = message;
    if (message.contains('.') && !message.contains(' ')) {
      // 確保本地化管理器已初始化
      if (!LocalizationManager().isInitialized) {
        await LocalizationManager().init();
      }
      translatedMessage = LocalizationManager().get(message, params: params);
    } else if (params != null && params.isNotEmpty) {
      // 如果提供了參數但訊息不是本地化鍵，直接格式化
      translatedMessage = _formatMessage(message, params);
    }
    
    final taggedMessage = tag != null ? '[$tag] $translatedMessage' : translatedMessage;
    await Logger.warning(taggedMessage);
  }
  
  /// 記錄錯誤信息
  Future<void> error(String message, {String? tag, Object? error, StackTrace? stackTrace, Map<String, dynamic>? params}) async {
    await _ensureInitialized();
    
    if (_minLevel.index > AppLogLevel.error.index) return;
    
    // 如果訊息是本地化鍵，先翻譯它
    String translatedMessage = message;
    if (message.contains('.') && !message.contains(' ')) {
      // 確保本地化管理器已初始化
      if (!LocalizationManager().isInitialized) {
        await LocalizationManager().init();
      }
      translatedMessage = LocalizationManager().get(message, params: params);
    } else if (params != null && params.isNotEmpty) {
      // 如果提供了參數但訊息不是本地化鍵，直接格式化
      translatedMessage = _formatMessage(message, params);
    }
    
    // 如果有錯誤對象，將其添加到參數中
    if (error != null) {
      translatedMessage = '$translatedMessage: $error';
    }
    
    final taggedMessage = tag != null ? '[$tag] $translatedMessage' : translatedMessage;
    await Logger.error(taggedMessage, error, stackTrace);
  }
  
  /// 簡單的訊息格式化方法
  String _formatMessage(String message, Map<String, dynamic> params) {
    String result = message;
    params.forEach((key, value) {
      result = result.replaceAll('{$key}', value?.toString() ?? '');
    });
    return result;
  }
  
  /// 輸出JSON數據到標準輸出
  void outputJson(String jsonString) {
    // JSON輸出總是發送到stdout，無論處於什麼模式
    stdout.writeln(jsonString);
  }
  
  /// 釋放資源
  Future<void> dispose() async {
    if (_initialized) {
      await Logger.dispose();
      _initialized = false;
    }
    await _broadcastSink?.dispose();
    _broadcastSink = null;
  }
  
  /// 是否為移動平台
  bool get isMobilePlatform => _isMobilePlatform;
}