import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'drone_protocol.dart';

/// DJI Ryze Tello and the EDU variant. Plain-text UDP commands on port 8889,
/// telemetry broadcast on 8890, H.264 video on 11111.
class TelloProtocol implements DroneProtocol {
  RawDatagramSocket? _cmd;
  RawDatagramSocket? _state;
  InternetAddress? _address;
  DroneEndpoint? _endpoint;

  final _telemetry = StreamController<Telemetry>.broadcast();
  final _video = StreamController<List<int>>.broadcast();
  final _log = StreamController<String>.broadcast();

  Completer<String>? _awaitingReply;

  /// Tello rejects a new `rc` frame if one is still in flight, so controls are
  /// rate-limited rather than sent at full joystick speed.
  DateTime _lastRc = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String get id => 'tello';

  @override
  String get displayName => 'DJI Tello / Tello EDU';

  @override
  List<String> get ssidHints => const ['tello', 'rmtt'];

  @override
  DroneEndpoint get defaultEndpoint => const DroneEndpoint(
        host: '192.168.10.1',
        commandPort: 8889,
        videoPort: 11111,
      );

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
    await disconnect();
    _endpoint = endpoint;
    _address = InternetAddress(endpoint.host);

    _cmd = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8889);
    _cmd!.listen(_onCommandEvent);

    _state = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8890);
    _state!.listen(_onStateEvent);

    final reply = await _send('command', awaitReply: true);
    final ok = reply == 'ok';
    _log.add(ok ? 'Tello entered SDK mode' : 'Tello handshake failed: $reply');
    return ok;
  }

  void _onCommandEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _cmd?.receive();
    if (dg == null) return;
    final text = utf8.decode(dg.data, allowMalformed: true).trim();
    _log.add('< $text');
    final pending = _awaitingReply;
    if (pending != null && !pending.isCompleted) pending.complete(text);
  }

  void _onStateEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _state?.receive();
    if (dg == null) return;

    // "pitch:0;roll:0;...;bat:87;...;h:0;..."
    final fields = <String, String>{};
    for (final pair in utf8.decode(dg.data, allowMalformed: true).split(';')) {
      final i = pair.indexOf(':');
      if (i > 0) fields[pair.substring(0, i)] = pair.substring(i + 1);
    }

    final height = int.tryParse(fields['h'] ?? '');
    _telemetry.add(Telemetry(
      batteryPercent: int.tryParse(fields['bat'] ?? ''),
      heightMeters: height == null ? null : height / 100.0,
      flying: height != null && height > 0,
      signalPercent: 100,
    ));
  }

  Future<String?> _send(String command, {bool awaitReply = false}) async {
    final socket = _cmd;
    final address = _address;
    final endpoint = _endpoint;
    if (socket == null || address == null || endpoint == null) return null;

    _log.add('> $command');
    socket.send(utf8.encode(command), address, endpoint.commandPort);
    if (!awaitReply) return null;

    final completer = Completer<String>();
    _awaitingReply = completer;
    try {
      return await completer.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      return null;
    } finally {
      _awaitingReply = null;
    }
  }

  @override
  void sendControl(ControlInput input) {
    final now = DateTime.now();
    if (now.difference(_lastRc) < const Duration(milliseconds: 50)) return;
    _lastRc = now;

    // Tello takes -100..100 on each axis; throttle is bidirectional because it
    // holds altitude on its own.
    int axis(double v) => (v.clamp(-1.0, 1.0) * 100).round();
    final scale = switch (input.speedRate) { 0 => 0.4, 2 => 1.0, _ => 0.7 };

    _send('rc ${axis(input.roll * scale)} ${axis(input.pitch * scale)} '
        '${axis(input.throttle * scale)} ${axis(input.yaw * scale)}');
  }

  @override
  Future<void> takeOff() async => _send('takeoff');

  @override
  Future<void> land() async => _send('land');

  @override
  Future<void> emergencyStop() async => _send('emergency');

  @override
  Future<void> calibrateGyro() async {
    // The Tello calibrates its IMU itself on power-up; there is no SDK command.
    _log.add('Tello calibrates automatically');
  }

  @override
  Future<void> flip() async => _send('flip f');

  @override
  Future<void> setVideoEnabled(bool enabled) async =>
      _send(enabled ? 'streamon' : 'streamoff');

  @override
  Future<void> disconnect() async {
    _cmd?.close();
    _state?.close();
    _cmd = null;
    _state = null;
    _address = null;
  }
}
