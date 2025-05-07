// 非 web 平台專用，不 import dart:html
class PlatformInfo {
  static bool get isWeb => false;
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMobile => false;
  static bool get isWindows => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;
  static bool get isDesktop => false;
  static bool get isSupportedPlatform => true;
}
