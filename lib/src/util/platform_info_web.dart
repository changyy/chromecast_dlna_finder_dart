class PlatformInfo {
  static bool get isWeb => true;
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMobile => false;
  static bool get isWindows => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;
  static bool get isDesktop => false;
  static bool get isSupportedPlatform => false; // web 不支援 raw socket
}
