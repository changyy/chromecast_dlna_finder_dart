// Dart-only Flutter/桌面/行動App風格的 log 監聽範例
// 不依賴 flutter framework，純 Dart 可執行
import 'package:chromecast_dlna_finder/chromecast_dlna_finder.dart';
import 'package:chromecast_dlna_finder/src/util/logger.dart';

Future<void> main() async {
  final logger = AppLogger();
  logger.setOutputs({LoggerOutput.broadcast});
  await logger.init();

  final finder = ChromecastDlnaFinder(logger: logger);

  final subscription = logger.broadcastStream?.listen((record) {
    print('[APP LOG][${record.level}] ${record.message}');
  });

  await logger.info('App log broadcast example started');

  final devices = await finder.findDevices();
  print('搜尋到裝置：$devices');

  await finder.dispose();
  await logger.dispose();
  await subscription?.cancel();
}
