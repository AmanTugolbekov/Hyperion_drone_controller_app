import 'dart:async';
import 'dart:math';

import 'drone_protocol.dart';

/// A drone that only exists in software. Lets the whole UI — joysticks,
/// telemetry, take-off, flips — be exercised on an emulator or with no
/// hardware in the room.
class MockProtocol implements DroneProtocol {
  final _telemetry = StreamController<Telemetry>.broadcast();
  final _video = StreamController<List<int>>.broadcast();
  final _log = StreamController<String>.broadcast();

  Timer? _ticker;
  double _battery = 100;
  double _height = 0;
  bool _flying = false;
  ControlInput _last = const ControlInput();
  final _rng = Random();

  @override
  String get id => 'mock';

  @override
  String get displayName => 'Симулятор / Simulator';

  @override
  List<String> get ssidHints => const [];

  @override
  DroneEndpoint get defaultEndpoint =>
      const DroneEndpoint(host: '0.0.0.0', commandPort: 0, videoPort: 0);

  @override
  VideoTransport get videoTransport => VideoTransport.none;

  @override
  String? get videoUrl => null;

  @override
  bool get throttleIsBidirectional => true;

  @override
  int get controlHz => 20;

  @override
  Stream<Telemetry> get telemetry => _telemetry.stream;

  @override
  Stream<List<int>> get videoFrames => _video.stream;

  @override
  Stream<String> get log => _log.stream;

  @override
  Future<bool> connect(DroneEndpoint endpoint) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _log.add('Simulator connected');
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    return true;
  }

  void _tick() {
    if (_flying) {
      _battery = max(0, _battery - 0.08);
      _height = (_height + _last.throttle * 0.3).clamp(0.0, 30.0);
    }
    _telemetry.add(Telemetry(
      batteryPercent: _battery.round(),
      heightMeters: _height,
      flying: _flying,
      signalPercent: 90 + _rng.nextInt(10),
    ));
  }

  @override
  void sendControl(ControlInput input) => _last = input;

  @override
  Future<void> takeOff() async {
    _flying = true;
    _height = 1.2;
    _log.add('takeoff');
  }

  @override
  Future<void> land() async {
    _flying = false;
    _height = 0;
    _log.add('land');
  }

  @override
  Future<void> emergencyStop() async {
    _flying = false;
    _height = 0;
    _log.add('EMERGENCY STOP');
  }

  @override
  Future<void> calibrateGyro() async => _log.add('gyro calibrated');

  @override
  Future<void> flip() async => _log.add('flip');

  @override
  Future<void> setVideoEnabled(bool enabled) async =>
      _log.add('video ${enabled ? 'on' : 'off'}');

  @override
  Future<void> disconnect() async {
    _ticker?.cancel();
    _ticker = null;
    _flying = false;
  }
}
