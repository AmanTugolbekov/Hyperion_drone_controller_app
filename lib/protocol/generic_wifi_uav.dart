import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'drone_protocol.dart';
import 'jpeg_framer.dart';
import 'video_receiver.dart';

/// The dialect used by most cheap "FPV / WIFI UFO" quadcopters — the family
/// RC UFO itself talks to. The drone is a Wi-Fi AP at 192.168.1.1 and expects
/// a fixed-length UDP frame several times a second; it stops responding to
/// controls if the stream pauses, so the service must keep feeding it.
///
/// Frame layout (8 bytes), which is shared by the SYMA/JJRC/Tianqu clones:
///   0  0x66            header
///   1  roll      0..255 (128 = centre)
///   2  pitch     0..255 (128 = centre)
///   3  throttle  0..255 (0 = idle)
///   4  yaw       0..255 (128 = centre)
///   5  command bits
///   6  checksum  XOR of bytes 1..5
///   7  0x99            footer
class GenericWifiUavProtocol implements DroneProtocol {
  static const int _header = 0x66;
  static const int _footer = 0x99;

  // Byte 5 command bits.
  static const int _bitSpeedHigh = 0x01;
  static const int _bitFlip = 0x02;
  static const int _bitHeadless = 0x04;
  static const int _bitCalibrate = 0x08;
  static const int _bitTakeOff = 0x10;
  static const int _bitLand = 0x20;
  static const int _bitEmergency = 0x40;

  RawDatagramSocket? _socket;
  InternetAddress? _address;
  DroneEndpoint? _endpoint;

  final _telemetry = StreamController<Telemetry>.broadcast();
  final _video = StreamController<List<int>>.broadcast();
  final _log = StreamController<String>.broadcast();

  late final VideoReceiver _videoReceiver = VideoReceiver(
    onFrame: _video.add,
    onLog: _log.add,
  );

  /// Frames that arrive on the control socket instead of the video port, which
  /// is how a few of these clones behave.
  final JpegFramer _inlineFramer = JpegFramer();

  /// Set once a video port has been found, so a reconnect skips the probe.
  int? _knownVideoPort;

  /// Bits that must ride along on the next few frames. Toy drones drop single
  /// packets constantly, so a one-shot command is repeated instead of sent once.
  int _pendingBits = 0;
  int _pendingRepeats = 0;

  DateTime _lastReply = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  String get id => 'generic_wifi_uav';

  @override
  String get displayName => 'Generic Wi-Fi UAV (RC UFO)';

  @override
  List<String> get ssidHints =>
      const ['ufo', 'fpv', 'wifi-uav', 'rc', 'drone', 'sky', 'jjrc', 'syma'];

  @override
  DroneEndpoint get defaultEndpoint => const DroneEndpoint(
        host: '192.168.1.1',
        commandPort: 8080,
        videoPort: 8888,
      );

  @override
  VideoTransport get videoTransport => VideoTransport.udpJpeg;

  @override
  String? get videoUrl => null;

  @override
  bool get throttleIsBidirectional => false;

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

    try {
      _address = InternetAddress(endpoint.host);
    } on ArgumentError {
      final resolved = await InternetAddress.lookup(endpoint.host);
      if (resolved.isEmpty) {
        _log.add('Cannot resolve ${endpoint.host}');
        return false;
      }
      _address = resolved.first;
    }

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.listen(_onSocketEvent);
    _log.add('UDP socket bound, talking to $endpoint');

    // Handshake: a few idle frames, then wait for any reply.
    for (var i = 0; i < 10; i++) {
      sendControl(const ControlInput());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (isAlive) {
        _log.add('Drone answered');
        return true;
      }
    }

    // Many clones never answer at all. Treat a working socket as good enough
    // and let the link indicator fall back to "no telemetry".
    _log.add('No reply from drone; continuing in one-way mode');
    return true;
  }

  bool get isAlive =>
      DateTime.now().difference(_lastReply) < const Duration(seconds: 2);

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;

    _lastReply = DateTime.now();
    final data = dg.data;

    // Some clones push camera frames down the control socket itself.
    if (data.length > 4 && data[0] == 0xFF && data[1] == 0xD8) {
      for (final frame in _inlineFramer.add(data)) {
        _video.add(frame);
      }
      return;
    }

    if (data.length >= 8 && data[0] == _header) {
      // Status frames reuse the control layout: byte 3 carries battery level
      // as 0..100, byte 5 bit 0x10 means "in flight".
      final battery = data[3];
      _telemetry.add(Telemetry(
        batteryPercent: battery <= 100 ? battery : null,
        flying: (data[5] & _bitTakeOff) != 0,
        signalPercent: 100,
      ));
    }
  }

  int _axis(double value, double trim) {
    final scaled = ((value + trim).clamp(-1.0, 1.0) * 127) + 128;
    return scaled.round().clamp(0, 255);
  }

  @override
  void sendControl(ControlInput input) {
    final socket = _socket;
    final address = _address;
    final endpoint = _endpoint;
    if (socket == null || address == null || endpoint == null) return;

    var bits = 0;
    if (input.speedRate >= 2) bits |= _bitSpeedHigh;
    if (input.headless) bits |= _bitHeadless;

    if (_pendingRepeats > 0) {
      bits |= _pendingBits;
      _pendingRepeats--;
      if (_pendingRepeats == 0) _pendingBits = 0;
    }

    final frame = Uint8List(8);
    frame[0] = _header;
    frame[1] = _axis(input.roll, input.rollTrim);
    frame[2] = _axis(input.pitch, input.pitchTrim);
    frame[3] = (input.throttle.clamp(0.0, 1.0) * 255).round();
    frame[4] = _axis(input.yaw, input.yawTrim);
    frame[5] = bits;
    frame[6] = frame[1] ^ frame[2] ^ frame[3] ^ frame[4] ^ frame[5];
    frame[7] = _footer;

    try {
      socket.send(frame, address, endpoint.commandPort);
    } on SocketException catch (e) {
      _log.add('send failed: $e');
    }
  }

  /// Queues [bits] onto the next [repeats] control frames.
  void _queue(int bits, {int repeats = 8}) {
    _pendingBits |= bits;
    _pendingRepeats = repeats;
  }

  @override
  Future<void> takeOff() async => _queue(_bitTakeOff);

  @override
  Future<void> land() async => _queue(_bitLand);

  @override
  Future<void> emergencyStop() async {
    // Bypass the queue: send the kill frame straight away, several times.
    _queue(_bitEmergency, repeats: 20);
    for (var i = 0; i < 5; i++) {
      sendControl(const ControlInput());
    }
  }

  @override
  Future<void> calibrateGyro() async => _queue(_bitCalibrate, repeats: 20);

  @override
  Future<void> flip() async => _queue(_bitFlip);

  @override
  Future<void> setVideoEnabled(bool enabled) async {
    final address = _address;
    final endpoint = _endpoint;
    if (address == null || endpoint == null) return;

    if (!enabled) {
      await _videoReceiver.stop();
      return;
    }

    // Reuse the port found earlier in the session; only hunt for it the first
    // time, since probing costs a second per candidate.
    final known = _knownVideoPort;
    if (known != null) {
      await _videoReceiver.start(address, known);
      return;
    }

    _knownVideoPort = await _videoReceiver.probe(
      address,
      preferred: endpoint.videoPort,
    );
  }

  @override
  Future<void> disconnect() async {
    await _videoReceiver.stop();
    _inlineFramer.reset();
    _socket?.close();
    _socket = null;
    _address = null;
    _pendingBits = 0;
    _pendingRepeats = 0;
  }
}
