import 'package:flutter/foundation.dart';

/// 平台能力集中判斷，避免 `Platform.isX` / `defaultTargetPlatform`
/// 散落在各個狀態類中，難以維護。
class PlatformCapabilities {
  PlatformCapabilities._();

  /// 是否為桌面平台（Windows / macOS / Linux）
  static bool get isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  /// 是否為行動平台（Android / iOS）
  static bool get isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;
  static bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;
  static bool get isWindows => defaultTargetPlatform == TargetPlatform.windows;
  static bool get isMacOS => defaultTargetPlatform == TargetPlatform.macOS;
  static bool get isLinux => defaultTargetPlatform == TargetPlatform.linux;

  /// 是否支援「視窗置頂」（Windows / macOS）
  static bool get supportsAlwaysOnTop => isDesktop;

  /// 是否支援前景服務（Android）
  static bool get supportsForegroundTask => isAndroid;

  /// 是否支援區網同步（Android）
  static bool get supportsLANSync => isAndroid;

  /// 是否支援畫中畫（Android / iOS / 桌面）
  static bool get supportsPictureInPicture =>
      isAndroid || isIOS || isDesktop;
}
