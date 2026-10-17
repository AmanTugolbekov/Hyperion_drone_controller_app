import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'jpeg_framer.dart';

/// Listens for the drone's camera stream on its own UDP port.
///
/// Clones disagree about how the stream is started: some push frames at
/// whoever is listening, others stay silent until they receive any datagram on
/// the video port. This sends a short wake-up packet and then listens, which
/// satisfies both.
class VideoReceiver {
  VideoReceiver({required this.onFrame, required this.onLog});

  final void Function(Uint8List frame) onFrame;
  final void Function(String message) onLog;

  /// Ports seen across the common RC UFO-compatible families, tried in order
  /// of how often they turn up.
  static const List<int> commonPorts = [8888, 7060, 8080, 6000, 1234, 9000];

  /// Sent to the drone's video port to wake a stream that waits to be asked.
  static final Uint8List _wakeUp = Uint8List.fromList([0x42, 0x76, 0x00, 0x00]);

  RawDatagramSocket? _socket;
  Timer? _keepAlive;
  final JpegFramer _framer = JpegFramer();

  int? _port;
  int _frameCount = 0;

  int? get port => _port;
  int get frameCount => _frameCount;
  bool get isRunning => _socket != null;

  /// Opens [port] and starts delivering frames. Returns false if the port
  /// could not be bound — usually because another app holds it.
  Future<bool> start(InternetAddress droneAddress, int port) async {
    await stop();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
    } on SocketException catch (e) {
      onLog('video port $port unavailable: ${e.message}');
      return false;
    }

    _port = port;
    _socket!.listen(_onEvent);
    onLog('video listening on $port');

    _poke(droneAddress, port);
    // Some drones stop streaming when they stop hearing from the phone.
    _keepAlive = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _poke(droneAddress, port),
    );
    return true;
  }

  void _poke(InternetAddress address, int port) {
    try {
      _socket?.send(_wakeUp, address, port);
    } on SocketException {
      // The drone may ignore this entirely; frames can still arrive.
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;

    for (final frame in _framer.add(datagram.data)) {
      _frameCount++;
      onFrame(frame);
    }
  }

  /// Tries each candidate port in turn and keeps the first that delivers a
  /// real frame. [preferred] is tried first when given.
  ///
  /// Returns the winning port, or null when nothing answered — in which case
  /// the drone either has no camera or uses a transport this app cannot read.
  Future<int?> probe(
    InternetAddress droneAddress, {
    int? preferred,
    Duration perPort = const Duration(milliseconds: 1200),
  }) async {
    final candidates = <int>[
      if (preferred != null) preferred,
      ...commonPorts.where((p) => p != preferred),
    ];

    for (final port in candidates) {
      onLog('probing video port $port…');
      final before = _frameCount;
      if (!await start(droneAddress, port)) continue;

      final deadline = DateTime.now().add(perPort);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (_frameCount > before) {
          onLog('video found on port $port');
          return port;
        }
      }
      await stop();
    }

    onLog('no video stream found on any known port');
    return null;
  }

  Future<void> stop() async {
    _keepAlive?.cancel();
    _keepAlive = null;
    _socket?.close();
    _socket = null;
    _framer.reset();
  }
}
