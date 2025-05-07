// 條件匯入 web/stub 版本
export 'platform_info_stub.dart'
    if (dart.library.html) 'platform_info_web.dart';
