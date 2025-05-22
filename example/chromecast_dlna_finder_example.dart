import 'package:chromecast_dlna_finder/chromecast_dlna_finder.dart';

Future<void> main() async {
  final finder = ChromecastDlnaFinder();
  // Disable logger output
  await finder.configureLogger(outputs: {});
  final devices = await finder.findDevices(scanDuration: Duration(seconds: 5));
  for (final device in devices['chromecast'] ?? []) {
    print('Chromecast: [32m${device.name}[0m (${device.ip})');
  }
  for (final device in devices['dlna'] ?? []) {
    print('DLNA: [34m${device.name}[0m (${device.ip})');
  }
  for (final device in devices['airplay_rx'] ?? []) {
    print('AirPlay RX: [35m${device.name}[0m (${device.ip})');
  }
  for (final device in devices['airplay_tx'] ?? []) {
    print('AirPlay TX: [36m${device.name}[0m (${device.ip})');
  }
  await finder.dispose();
}
