import 'dart:io';

import 'package:flutter/services.dart';

/// Pins every socket the app opens to the Wi-Fi network.
///
/// Without this, Android sees that the drone's access point has no internet
/// and routes UDP over mobile data instead, so the control stream never
/// reaches the drone. This is the single most common reason a drone app
/// "connects" and then does nothing.
class NetworkBinder {
  static const _channel =
      MethodChannel('kg.edu.alatoo.alatoo_drone/network');

  /// Returns true when the process is now pinned to Wi-Fi. Always false off
  /// Android, where the platform side does not exist.
  static Future<bool> bindToWifi() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('bindToWifi') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> unbind() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('unbind');
    } on PlatformException {
      // Nothing to undo.
    } on MissingPluginException {
      // Nothing to undo.
    }
  }

  static Future<bool> isBound() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isBound') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
