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

  void startRecording() {
    if (isRecording) return;
    _recorder = MjpegAviWriter(width: 640, height: 480);
    _recordingStarted = DateTime.now();

    // Sampling on a timer rather than on every frame keeps the clip at a
    // steady rate even when the drone's feed stutters.
    _recordTicker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final frame = _drone.lastFrame;
      if (frame != null) _recorder?.addFrame(frame);
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
