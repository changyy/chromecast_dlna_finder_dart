// ios專用，需在pubspec.yaml條件匯入
import 'dart:io';

class PlatformInfo {
  static bool get isWeb => false;
  static bool get isAndroid => false;
  static bool get isIOS => Platform.isIOS;
  static bool get isMobile => Platform.isIOS || Platform.isAndroid;
  static bool get isWindows => Platform.isWindows;
  static bool get isLinux => Platform.isLinux;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  static bool get isSupportedPlatform => !Platform.isFuchsia && !isWeb;
}
