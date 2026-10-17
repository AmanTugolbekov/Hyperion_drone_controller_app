import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../protocol/drone_protocol.dart';
import '../protocol/protocol_registry.dart';
import 'network_binder.dart';
import 'settings_service.dart';

/// Owns the link to the drone: picks a protocol, keeps the control stream
/// running at the rate the drone expects, and republishes telemetry and video
/// for the UI.
class DroneService extends ChangeNotifier {
  DroneService(this._settings) {
    _protocols = ProtocolRegistry.build();
  }

  final SettingsService _settings;
  late final List<DroneProtocol> _protocols;

  DroneProtocol? _active;
  Timer? _controlTimer;
  final _subscriptions = <StreamSubscription<dynamic>>[];

  LinkState _link = LinkState.idle;
  Telemetry _telemetry = const Telemetry();
  ControlInput _input = const ControlInput();
  Uint8List? _lastFrame;
  String? _ssid;
  String? _gateway;
  bool _wifiBound = false;
  final List<String> _log = [];

  LinkState get link => _link;
  Telemetry get telemetry => _telemetry;
  ControlInput get input => _input;
  Uint8List? get lastFrame => _lastFrame;
  String? get ssid => _ssid;

  /// The Wi-Fi gateway, which on a drone's own access point is the drone.
  String? get gateway => _gateway;

  /// Set when the active drone serves its camera as an RTSP stream, which the
  /// player widget opens directly instead of going through [lastFrame].
  String? get rtspUrl => _active?.videoTransport == VideoTransport.rtsp
      ? _active?.videoUrl
      : null;

  /// Whether the app's sockets are pinned to Wi-Fi. False means traffic may be
  /// leaking to mobile data, which the flight screen warns about.
  bool get wifiBound => _wifiBound;
  List<DroneProtocol> get protocols => List.unmodifiable(_protocols);
  DroneProtocol? get activeProtocol => _active;
  List<String> get log => List.unmodifiable(_log);
  bool get isConnected => _link == LinkState.connected;
  bool get isFlying => _telemetry.flying ?? false;

  /// Reads the Wi-Fi network name so the right protocol can be guessed, and
  /// the gateway address, which on a drone's own access point is the drone.
  Future<void> refreshSsid() async {
    final info = NetworkInfo();
    try {
      _ssid = await info.getWifiName();
    } on Exception catch (e) {
      _ssid = null;
      _addLog('SSID unavailable: $e');
    }
    try {
      _gateway = await info.getWifiGatewayIP();
    } on Exception {
      _gateway = null;
    }
    notifyListeners();
  }

  DroneProtocol _chooseProtocol() {
    final id = _settings.protocolId;
    if (id == ProtocolRegistry.autoId) {
      return ProtocolRegistry.pickForSsid(_ssid, _protocols);
    }
    return ProtocolRegistry.byId(id, _protocols);
  }

  Future<bool> connect() async {
    await disconnect();
    await refreshSsid();

    _link = LinkState.connecting;
    notifyListeners();

    // Must happen before any socket is opened: the drone's access point has no
    // internet, so Android would otherwise route the control stream over
    // mobile data and the drone would never hear from us.
    _wifiBound = await NetworkBinder.bindToWifi();
    _addLog(_wifiBound
        ? 'Sockets pinned to Wi-Fi'
        : 'Could not pin sockets to Wi-Fi — turn mobile data off if the drone '
            'does not respond');

    final protocol = _chooseProtocol();
    _active = protocol;
    _addLog('Using ${protocol.displayName}');

    _subscriptions.addAll([
      protocol.telemetry.listen((t) {
        _telemetry = _telemetry.merge(t);
        notifyListeners();
      }),
      protocol.videoFrames.listen((frame) {
        _lastFrame = Uint8List.fromList(frame);
        notifyListeners();
      }),
      protocol.log.listen(_addLog),
    ]);

    // On a drone's own access point the gateway is the drone, so it beats any
    // hard-coded default when the user has not set an address by hand.
    var endpoint = _settings.endpointFor(protocol);
    final gateway = _gateway;
    if (_settings.hostOverride == null &&
        gateway != null &&
        gateway.isNotEmpty &&
        gateway != '0.0.0.0') {
      if (gateway != endpoint.host) {
        _addLog('Using gateway $gateway instead of ${endpoint.host}');
      }
      endpoint = endpoint.copyWith(host: gateway);
    }

    bool ok;
    try {
      ok = await protocol.connect(endpoint);
    } on Exception catch (e) {
      _addLog('connect failed: $e');
      ok = false;
    }

    if (!ok) {
      await disconnect();
      _link = LinkState.failed;
      notifyListeners();
      return false;
    }

    _link = LinkState.connected;
    _startControlLoop(protocol);
    notifyListeners();
    return true;
  }

  void _startControlLoop(DroneProtocol protocol) {
    _controlTimer?.cancel();
    final period = Duration(milliseconds: (1000 / protocol.controlHz).round());
    _controlTimer = Timer.periodic(period, (_) => protocol.sendControl(_input));
  }

  Future<void> disconnect() async {
    _controlTimer?.cancel();
    _controlTimer = null;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _active?.disconnect();
    _active = null;
    await NetworkBinder.unbind();
    _wifiBound = false;
    _telemetry = const Telemetry();
    _input = const ControlInput();
    _lastFrame = null;
    _link = LinkState.idle;
    notifyListeners();
  }

  /// Updates the stick values. The control loop picks them up on its next
  /// tick, so this stays cheap enough to call on every touch move.
  void updateInput(ControlInput input) {
    _input = input;
    notifyListeners();
  }

  void setSticks({double? roll, double? pitch, double? yaw, double? throttle}) {
    updateInput(_input.copyWith(
      roll: roll,
      pitch: pitch,
      yaw: yaw,
      throttle: throttle,
    ));
  }

  void setTrim({double? roll, double? pitch, double? yaw}) {
    updateInput(_input.copyWith(
      rollTrim: roll,
      pitchTrim: pitch,
      yawTrim: yaw,
    ));
  }

  void setSpeedRate(int rate) =>
      updateInput(_input.copyWith(speedRate: rate.clamp(0, 2)));

  void setHeadless(bool on) => updateInput(_input.copyWith(headless: on));

  Future<void> takeOff() async => _active?.takeOff();
  Future<void> land() async => _active?.land();
  Future<void> flip() async => _active?.flip();
  Future<void> calibrateGyro() async => _active?.calibrateGyro();
  Future<void> setVideoEnabled(bool on) async =>
      _active?.setVideoEnabled(on);

  /// Zeroes the sticks first so a stale joystick value cannot be re-sent after
  /// the motors are cut.
  Future<void> emergencyStop() async {
    _input = const ControlInput();
    await _active?.emergencyStop();
    notifyListeners();
  }

  /// Lets diagnostics tools write into the same log the protocols use.
  void addLog(String line) => _addLog(line);

  void _addLog(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    _log.insert(0, '$stamp  $line');
    if (_log.length > 200) _log.removeLast();
    notifyListeners();
  }

  @override
  void dispose() {
    _controlTimer?.cancel();
    _active?.disconnect();
    super.dispose();
  }
}
