// Dart-only Flutter/桌面/行動App風格的 log 和裝置事件監聽範例
// 不依賴 flutter framework，純 Dart 可執行
import 'package:chromecast_dlna_finder/chromecast_dlna_finder.dart';
import 'package:chromecast_dlna_finder/src/util/logger.dart';
import 'package:chromecast_dlna_finder/src/discovery/discovery_events.dart';

Future<void> main() async {
  // 初始化 logger 並設置為廣播模式
  final logger = AppLogger();
  logger.setOutputs({LoggerOutput.broadcast});
  await logger.init();

  // 建立支援裝置發現的物件
  final finder = ChromecastDlnaFinder(logger: logger);

  // 監聽一般日誌訊息
  final logSubscription = logger.broadcastStream?.listen((record) {
    print('[APP LOG][${record.level}] ${record.message}');
  });

  // 監聽裝置發現事件 - 這是新增的功能
  final deviceEventSubscription = finder.deviceEvents?.listen((event) {
    if (event is DeviceFoundEvent) {
      // 處理裝置發現事件
      print('╔═════════════════════════════════════════════');
      print('║ 發現新裝置! ${event.device.name} (${event.device.ip})');
      print('║ 類型: ${_getDeviceTypeString(event.device)}');
      if (event.device.model != null) {
        print('║ 型號: ${event.device.model}');
      }
      print('╚═════════════════════════════════════════════');
    } else if (event is SearchStartedEvent) {
      // 搜尋開始事件
      print('▶ 開始搜尋 ${event.deviceType} 裝置...');
    } else if (event is SearchCompleteEvent) {
      // 搜尋完成事件
      print('✓ ${event.deviceType} 裝置搜尋完成，找到 ${event.deviceCount} 個裝置');
    } else if (event is SearchErrorEvent) {
      // 搜尋錯誤事件
      print('✗ ${event.deviceType} 裝置搜尋失敗: ${event.error}');
    }
  });

  await logger.info('App log broadcast example started');

  print('\n開始搜尋裝置，搜尋過程中會即時顯示裝置發現事件...\n');

  // 開始搜尋裝置，事件將透過上面的監聽器即時顯示
  final devices = await finder.findDevices();

  // 顯示最終結果
  print('\n搜尋完成! 結果摘要:');
  print('- Chromecast 裝置: ${devices['chromecast']?.length ?? 0}');
  print('- DLNA 播放器: ${devices['dlna_renderer']?.length ?? 0}');
  print('- DLNA 媒體伺服器: ${devices['dlna_media_server']?.length ?? 0}');

  // 釋放資源
  await deviceEventSubscription?.cancel();
  await finder.dispose();
  await logger.dispose();
  await logSubscription?.cancel();
}

// 將裝置類型轉換為易讀的文字
String _getDeviceTypeString(DiscoveredDevice device) {
  if (device.isChromecastDongle) return 'Chromecast';
  if (device.isChromecastAudio) return 'Chromecast Audio';
  if (device.isDlnaRenderer) return 'DLNA 播放器';
  if (device.isDlnaMediaServer) return 'DLNA 媒體伺服器';
  return '未知裝置';
}
