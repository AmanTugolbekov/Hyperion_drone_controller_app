import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'drone_protocol.dart';
import 'jpeg_framer.dart';

/// Which dialect of the E88 family a particular drone speaks. The board inside
/// an "E88" varies by production batch, so this is detected at connect time
/// rather than assumed.
enum E88Variant {
  /// `03 66 …` 9-byte frames on UDP 7099, answered with telemetry.
  legacy7099,

  /// `03 66 14 …` 21-byte frames on UDP 7099, used by newer GL boards.
  gl7099,

  /// `66 …` 8-byte frames on UDP 8090, unlocked by a mode switch on 8080.
  /// One-way: these boards send nothing back.
  wifi8k,
}

/// Eachine E88 / E58 / LSRC-style drones.
///
/// Two things make this family different from the generic clones, and either
/// one alone is enough to make the drone ignore everything:
///
///  * Control does not live on the port the app connects to. Depending on the
///    board it is UDP 7099 or UDP 8090 — never 8080, which only carries the
///    mode switch.
///  * The drone boots bound to its physical RF remote and discards Wi-Fi
///    control until it is explicitly switched over.
class E88Protocol implements DroneProtocol {
  // Mode switch, sent to port 8080 on wifi8k boards.
  static final Uint8List _enterWifiMode = Uint8List.fromList([0x42, 0x76]);
  static final Uint8List _exitWifiMode = Uint8List.fromList([0x42, 0x77]);

  // Heartbeat for the 7099 boards; also what provokes the first telemetry
  // packet, which is how the variant is identified.
  static final Uint8List _heartbeat = Uint8List.fromList([0x01, 0x01]);

  static const int _portModeSwitch = 8080;
  static const int _portWifi8kControl = 8090;
  static const int _port7099 = 7099;

  /// Device ids that identify a GL board, from the telemetry's first byte.
  static bool _isGlDevice(int id) =>
      (id >= 90 && id <= 101) || id == 82 || id == 85 || id == 88 || id == 103;

  RawDatagramSocket? _socket;
  InternetAddress? _address;
  DroneEndpoint? _endpoint;

  final _telemetry = StreamController<Telemetry>.broadcast();
  final _video = StreamController<List<int>>.broadcast();
  final _log = StreamController<String>.broadcast();

  final JpegFramer _inlineFramer = JpegFramer();

  Timer? _heartbeatTimer;

  E88Variant _variant = E88Variant.legacy7099;
  bool _sawReply = false;

  /// Last status packet seen, so repeats are not logged.
  String? _lastTelemetryHex;
  bool _motorsUnlocked = false;

  int _pendingFlags1 = 0;
  int _pendingFlags2 = 0;
  int _pendingRepeats = 0;

  E88Variant get variant => _variant;

  @override
  String get id => 'e88';

  @override
  String get displayName => 'Eachine E88 / E58 / LSRC';

  @override
  List<String> get ssidHints =>
      const ['e88', 'e58', 'lsrc', 'hfun', 'jy', 'wifi-8k', 'wifi_8k', 'gd'];

  @override
  DroneEndpoint get defaultEndpoint => const DroneEndpoint(
        host: '192.168.1.1',
        commandPort: _port7099,
        videoPort: 8888,
      );

  /// The RC UFO app plays `rtsp://192.168.1.1:7070/webcam` through FFmpeg, and
  /// the drone serves MJPEG over RTP there. That is the only camera path on
  /// this family — there is no raw-JPEG UDP stream to listen for.
  static const int _rtspPort = 7070;
  static const String _rtspPath = 'webcam';

  @override
  VideoTransport get videoTransport => VideoTransport.rtsp;

  @override
  String? get videoUrl {
    final host = _endpoint?.host;
    if (host == null) return null;
    return 'rtsp://$host:$_rtspPort/$_rtspPath';
  }

  @override
  bool get throttleIsBidirectional => true;

  @override
  int get controlHz => 25;

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
    _sawReply = false;
    _motorsUnlocked = false;

    try {
      _address = InternetAddress(endpoint.host);
    } on ArgumentError {
      _log.add('Bad drone address: ${endpoint.host}');
      return false;
    }

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.listen(_onSocketEvent);

    // The 7099 boards answer, so try them first: a reply is proof, while the
    // wifi8k path can only ever be assumed.
    if (await _probe7099()) {
      _startHeartbeat();
      _log.add('E88 variant: ${_variant.name}');
      return true;
    }

    _log.add('No answer on $_port7099, trying the 8080/8090 mode switch');
    _variant = E88Variant.wifi8k;
    await _enterWifi8kMode();
    _startHeartbeat();

    // These boards stay silent even when they are working, so a missing reply
    // is not proof of failure. Report success and let the pilot judge.
    _log.add(_sawReply
        ? 'Drone answered on the mode-switch path'
        : 'No telemetry (normal for this board) — try the sticks');
    return true;
  }

  /// Sends heartbeats and waits for the telemetry that identifies the board.
  Future<bool> _probe7099() async {
    final address = _address;
    if (address == null) return false;

    _log.add('Probing UDP $_port7099…');
    for (var i = 0; i < 12; i++) {
      _send(_heartbeat, _port7099);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (_sawReply) return true;
    }
    return false;
  }

  Future<void> _enterWifi8kMode() async {
    _log.add('Switching drone from RF remote to Wi-Fi control');
    // Repeated because the drone drops packets while it switches radios.
    for (var i = 0; i < 6; i++) {
      _send(_enterWifiMode, _portModeSwitch);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    if (_variant == E88Variant.wifi8k) {
      // Idle keepalive: same envelope as a control frame, throttle at zero.
      final keepAlive = Uint8List.fromList(
          [0xAA, 0x80, 0x80, 0x00, 0x80, 0x00, 0x80, 0x55]);
      _heartbeatTimer = Timer.periodic(
        const Duration(milliseconds: 790),
        (_) => _send(keepAlive, _portWifi8kControl),
      );
    } else {
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _send(_heartbeat, _port7099),
      );
    }
  }

  void _send(Uint8List bytes, int port) {
    final socket = _socket;
    final address = _address;
    if (socket == null || address == null) return;
    try {
      socket.send(bytes, address, port);
    } on SocketException catch (e) {
      _log.add('send failed: ${e.message}');
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;

    final data = datagram.data;

    // A few boards push camera frames down the control socket.
    if (data.length > 4 && data[0] == 0xFF && data[1] == 0xD8) {
      for (final frame in _inlineFramer.add(data)) {
        _video.add(frame);
      }
      return;
    }

    if (data.isEmpty) return;

    // These boards repeat the same status packet several times a second, so
    // only a change is worth recording. Logging every one buries the rest of
    // the diagnostics.
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    if (hex != _lastTelemetryHex) {
      _lastTelemetryHex = hex;
      _log.add('RX ${data.length}B: $hex');
      debugPrint('[tlm] ${data.length}B $hex');
    }

    if (!_sawReply) {
      _sawReply = true;
      _variant =
          _isGlDevice(data[0]) ? E88Variant.gl7099 : E88Variant.legacy7099;
      _log.add('Telemetry from device id ${data[0]} → ${_variant.name}');
    }

    // Byte 2 reports the physical remote's shutter buttons; the drone expects
    // an acknowledgement or it keeps resending.
    if (data.length > 2) {
      if (data[2] == 0x4D) {
        _send(Uint8List.fromList([0x09, 0x01]), _port7099);
      } else if (data[2] == 0x58) {
        _send(Uint8List.fromList([0x09, 0x02]), _port7099);
      }
    }

    _telemetry.add(Telemetry(signalPercent: 100, flying: _motorsUnlocked));
  }

  int _axis(double value, double trim) {
    final scaled = ((value + trim).clamp(-1.0, 1.0) * 127) + 128;
    return scaled.round().clamp(1, 255);
  }

  @override
  void sendControl(ControlInput input) {
    if (_socket == null || _address == null) return;

    final roll = _axis(input.roll, input.rollTrim);
    final pitch = _axis(input.pitch, input.pitchTrim);
    final yaw = _axis(input.yaw, input.yawTrim);
    // Throttle arrives as 0..1 with 0.5 meaning "hold altitude".
    final throttle = (input.throttle.clamp(0.0, 1.0) * 254).round() + 1;

    var flags1 = _pendingFlags1;
    var flags2 = _pendingFlags2;
    if (_pendingRepeats > 0) {
      _pendingRepeats--;
      if (_pendingRepeats == 0) {
        _pendingFlags1 = 0;
        _pendingFlags2 = 0;
      }
    } else {
      flags1 = 0;
      flags2 = 0;
    }

    switch (_variant) {
      case E88Variant.legacy7099:
        if (input.headless) flags1 |= 0x10;
        final frame = Uint8List.fromList([
          0x03, 0x66, roll, pitch, throttle, yaw, flags1, 0, 0x99,
        ]);
        frame[7] = roll ^ pitch ^ throttle ^ yaw ^ flags1;
        _send(frame, _port7099);

      case E88Variant.gl7099:
        if (input.headless) flags2 |= 0x01;
        flags2 |= 0x02; // altitude hold, which these boards expect to be on
        final frame = Uint8List(21);
        frame[0] = 0x03;
        frame[1] = 0x66;
        frame[2] = 0x14;
        frame[3] = roll;
        frame[4] = pitch;
        frame[5] = throttle;
        frame[6] = yaw;
        frame[7] = flags1;
        frame[8] = flags2;
        frame[19] = flags1 ^ pitch ^ roll ^ throttle ^ yaw ^ flags2;
        frame[20] = 0x99;
        _send(frame, _port7099);

      case E88Variant.wifi8k:
        if (input.headless) flags1 |= 0x10;
        final frame = Uint8List.fromList([
          0x66, roll, pitch, throttle, yaw, flags1, 0, 0x99,
        ]);
        // Note the narrower checksum: the flags byte is excluded here.
        frame[6] = roll ^ pitch ^ throttle ^ yaw;
        _send(frame, _portWifi8kControl);
    }
  }

  /// Rides [flags1]/[flags2] on the next [repeats] control frames, because a
  /// single command packet is routinely lost.
  void _queue(int flags1, {int flags2 = 0, int repeats = 10}) {
    _pendingFlags1 |= flags1;
    _pendingFlags2 |= flags2;
    _pendingRepeats = repeats;
  }

  @override
  Future<void> takeOff() async {
    switch (_variant) {
      case E88Variant.wifi8k:
        // This board arms the motors separately before it will lift off.
        _queue(0x40, repeats: 6);
        _motorsUnlocked = true;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        _queue(0x01);
      case E88Variant.gl7099:
        _motorsUnlocked = true;
        _queue(0x01); // takeoff and land share this bit on GL boards
      case E88Variant.legacy7099:
        _motorsUnlocked = true;
        _queue(0x01);
    }
  }

  @override
  Future<void> land() async {
    _motorsUnlocked = false;
    switch (_variant) {
      case E88Variant.gl7099:
        _queue(0x01);
      case E88Variant.legacy7099:
      case E88Variant.wifi8k:
        _queue(0x02);
    }
  }

  @override
  Future<void> emergencyStop() async {
    _motorsUnlocked = false;
    switch (_variant) {
      case E88Variant.gl7099:
        _queue(0x02, repeats: 25);
      case E88Variant.legacy7099:
      case E88Variant.wifi8k:
        _queue(0x04, repeats: 25);
    }
    // Also send the dedicated stop command, which the 7099 boards honour even
    // when a control frame is lost.
    if (_variant != E88Variant.wifi8k) {
      _send(Uint8List.fromList([0x08, 0x01]), _port7099);
    }
  }

  @override
  Future<void> calibrateGyro() async {
    switch (_variant) {
      case E88Variant.gl7099:
        _queue(0x04, repeats: 20);
      case E88Variant.legacy7099:
      case E88Variant.wifi8k:
        _queue(0x80, repeats: 20);
    }
  }

  @override
  Future<void> flip() async => _queue(0x08);

  @override
  Future<void> setVideoEnabled(bool enabled) async {
    // Nothing to open or probe: the RTSP player owns the stream.
    _log.add(enabled ? 'Camera: ${videoUrl ?? "unknown"}' : 'Camera off');
  }

  @override
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _inlineFramer.reset();

    if (_variant == E88Variant.wifi8k && _socket != null) {
      _send(_exitWifiMode, _portModeSwitch);
    }

    _socket?.close();
    _socket = null;
    _address = null;
    _pendingFlags1 = 0;
    _pendingFlags2 = 0;
    _pendingRepeats = 0;
  }
}
