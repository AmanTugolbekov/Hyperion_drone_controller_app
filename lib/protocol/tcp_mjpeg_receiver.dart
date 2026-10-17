import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'jpeg_framer.dart';

/// Reads an MJPEG camera stream delivered over TCP.
///
/// Most E88/E58-family cameras open a plain TCP socket and push JPEG frames
/// back to back, with no HTTP layer and no length prefixes — so the frames are
/// found by their own markers, exactly as with the UDP transport.
class TcpMjpegReceiver {
  TcpMjpegReceiver({required this.onFrame, required this.onLog});

  final void Function(Uint8List frame) onFrame;
  final void Function(String message) onLog;

  /// Some boards stay silent until asked. This is the same wake-up used on the
  /// UDP transport and is harmless to a board that ignores it.
  static final Uint8List _wakeUp = Uint8List.fromList([0x42, 0x76, 0x00, 0x00]);

  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  final JpegFramer _framer = JpegFramer();

  int _frameCount = 0;
  int? _port;

  int get frameCount => _frameCount;
  int? get port => _port;
  bool get isRunning => _socket != null;

  /// Connects and waits briefly for a real frame. Returns false if the port
  /// refuses the connection or stays silent, so the caller can try another.
  Future<bool> start(
    InternetAddress address,
    int port, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    await stop();
    _port = port;

    try {
      _socket = await Socket.connect(address, port, timeout: timeout);
    } on SocketException catch (e) {
      onLog('TCP video $port: ${e.message}');
      return false;
    }

    onLog('TCP video connected on $port');
    final before = _frameCount;

    _subscription = _socket!.listen(
      _onData,
      onError: (Object e) => onLog('TCP video error: $e'),
      onDone: () => onLog('TCP video closed by drone'),
      cancelOnError: false,
    );

    try {
      _socket!.add(_wakeUp);
    } on SocketException {
      // The board may not need asking.
    }

    // A connection that never delivers a frame is not a camera.
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (_frameCount > before) {
        onLog('TCP video streaming from $port');
        return true;
      }
    }

    onLog('TCP video $port opened but sent no frames');
    await stop();
    return false;
  }

  void _onData(Uint8List chunk) {
    for (final frame in _framer.add(chunk)) {
      _frameCount++;
      onFrame(frame);
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _framer.reset();
  }
}
