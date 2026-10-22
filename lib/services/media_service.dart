import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'drone_service.dart';
import 'mjpeg_avi_writer.dart';

/// Captures stills and clips from the drone's video feed and files them in the
/// phone's gallery under an "Ala-Too Drone" album.
class MediaService extends ChangeNotifier {
  MediaService(this._drone);

  final DroneService _drone;
  static const album = 'Ala-Too Drone';

  MjpegAviWriter? _recorder;
  DateTime? _recordingStarted;
  Timer? _recordTicker;

  /// Pulls a frame when the drone's video does not arrive as decoded JPEG on
  /// the protocol — over RTSP the frames live inside the player, so recording
  /// asks it for them instead.
  Future<Uint8List?> Function()? _frameSource;

  /// Guards against a slow capture overlapping the next tick.
  bool _capturing = false;

  bool get isRecording => _recorder != null;

  Duration get recordingLength => _recordingStarted == null
      ? Duration.zero
      : DateTime.now().difference(_recordingStarted!);

  /// Files an already-decoded picture, such as one grabbed from the RTSP
  /// player. Returns null when the player had no frame to give.
  Future<File?> savePhotoBytes(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    final file = await _writeTemp(bytes, 'png');
    await Gal.putImage(file.path, album: album);
    return file;
  }

  /// Saves the most recent frame. Returns the file, or null if no frame has
  /// arrived yet.
  Future<File?> takePhoto() async {
    final frame = _drone.lastFrame;
    if (frame == null) return null;

    final file = await _writeTemp(frame, 'jpg');
    await Gal.putImage(file.path, album: album);
    return file;
  }

  /// Starts a clip. [width] and [height] size the container; [frameSource]
  /// overrides where frames come from, which RTSP needs because nothing
  /// reaches the protocol layer.
  void startRecording({
    int width = 640,
    int height = 480,
    int fps = 10,
    Future<Uint8List?> Function()? frameSource,
  }) {
    if (isRecording) return;
    _recorder = MjpegAviWriter(width: width, height: height, fps: fps);
    _frameSource = frameSource;
    _recordingStarted = DateTime.now();

    // Sampling on a timer rather than on every frame keeps the clip at a
    // steady rate even when the drone's feed stutters.
    final period = Duration(milliseconds: (1000 / fps).round());
    _recordTicker = Timer.periodic(period, (_) async {
      final source = _frameSource;
      if (source == null) {
        final frame = _drone.lastFrame;
        if (frame != null) _recorder?.addFrame(frame);
      } else {
        if (_capturing) return;
        _capturing = true;
        try {
          final frame = await source();
          if (frame != null && frame.isNotEmpty) _recorder?.addFrame(frame);
        } finally {
          _capturing = false;
        }
      }
      notifyListeners();
    });
    notifyListeners();
  }

  /// Finishes the clip and files it. Returns null if nothing was captured.
  Future<File?> stopRecording() async {
    final recorder = _recorder;
    _recordTicker?.cancel();
    _recordTicker = null;
    _recorder = null;
    _frameSource = null;
    _recordingStarted = null;
    notifyListeners();

    if (recorder == null || recorder.frameCount == 0) return null;

    final dir = await getApplicationDocumentsDirectory();
    final path =
        '${dir.path}/alatoo_${DateTime.now().millisecondsSinceEpoch}.avi';
    final file = await recorder.writeTo(path);
    await Gal.putVideo(file.path, album: album);
    return file;
  }

  Future<File> _writeTemp(Uint8List bytes, String ext) async {
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/alatoo_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  @override
  void dispose() {
    _recordTicker?.cancel();
    super.dispose();
  }
}
