import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import '../protocol/drone_protocol.dart';
import '../protocol/protocol_registry.dart';

class SettingsService extends ChangeNotifier {
  SharedPreferences? _prefs;

  AppLang _lang = AppLang.ru;
  String _protocolId = ProtocolRegistry.autoId;
  bool _throttleOnLeft = true;
  bool _haptics = true;
  bool _keepScreenOn = true;

  String? _hostOverride;
  int? _cmdPortOverride;
  int? _videoPortOverride;

  AppLang get lang => _lang;
  String get protocolId => _protocolId;
  bool get throttleOnLeft => _throttleOnLeft;
  bool get haptics => _haptics;
  bool get keepScreenOn => _keepScreenOn;

  String? get hostOverride => _hostOverride;
  int? get cmdPortOverride => _cmdPortOverride;
  int? get videoPortOverride => _videoPortOverride;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    _lang = AppLangX.fromCode(p.getString('lang'));
    _protocolId = p.getString('protocol') ?? ProtocolRegistry.autoId;
    _throttleOnLeft = p.getBool('throttle_left') ?? true;
    _haptics = p.getBool('haptics') ?? true;
    _keepScreenOn = p.getBool('keep_screen_on') ?? true;
    _hostOverride = p.getString('host');
    _cmdPortOverride = p.getInt('cmd_port');
    _videoPortOverride = p.getInt('video_port');
    notifyListeners();
  }

  Future<void> setLang(AppLang v) async {
    _lang = v;
    await _prefs?.setString('lang', v.code);
    notifyListeners();
  }

  Future<void> setProtocolId(String v) async {
    _protocolId = v;
    await _prefs?.setString('protocol', v);
    notifyListeners();
  }

  Future<void> setThrottleOnLeft(bool v) async {
    _throttleOnLeft = v;
    await _prefs?.setBool('throttle_left', v);
    notifyListeners();
  }

  Future<void> setHaptics(bool v) async {
    _haptics = v;
    await _prefs?.setBool('haptics', v);
    notifyListeners();
  }

  Future<void> setKeepScreenOn(bool v) async {
    _keepScreenOn = v;
    await _prefs?.setBool('keep_screen_on', v);
    notifyListeners();
  }

  /// Stores manual network coordinates. A null or empty value clears the
  /// override so the protocol's own defaults apply again.
  Future<void> setEndpointOverride({
    String? host,
    int? cmdPort,
    int? videoPort,
  }) async {
    final p = _prefs;
    _hostOverride = (host == null || host.isEmpty) ? null : host;
    _cmdPortOverride = cmdPort;
    _videoPortOverride = videoPort;

    if (_hostOverride == null) {
      await p?.remove('host');
    } else {
      await p?.setString('host', _hostOverride!);
    }
    if (cmdPort == null) {
      await p?.remove('cmd_port');
    } else {
      await p?.setInt('cmd_port', cmdPort);
    }
    if (videoPort == null) {
      await p?.remove('video_port');
    } else {
      await p?.setInt('video_port', videoPort);
    }
    notifyListeners();
  }

  /// Applies any manual override on top of a protocol's defaults.
  DroneEndpoint endpointFor(DroneProtocol protocol) =>
      protocol.defaultEndpoint.copyWith(
        host: _hostOverride,
        commandPort: _cmdPortOverride,
        videoPort: _videoPortOverride,
      );
}
