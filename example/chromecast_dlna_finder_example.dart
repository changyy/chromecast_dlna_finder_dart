import 'package:chromecast_dlna_finder/chromecast_dlna_finder.dart';

Future<void> main() async {
  final finder = ChromecastDlnaFinder();
  // 關閉 logger 輸出
  await finder.configureLogger(outputs: {});
  final devices = await finder.findDevices(timeout: Duration(seconds: 5));
  for (final device in devices['chromecast'] ?? []) {
    print('${device.name} (${device.ip})');
  }
  for (final device in devices['dlna'] ?? []) {
    print('${device.name} (${device.ip})');
  }
  await finder.dispose();
}
