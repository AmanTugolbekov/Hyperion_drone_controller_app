import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../theme/alatoo_theme.dart';

/// Plays the drone's RTSP camera.
///
/// The feed is MJPEG carried over RTP, which no pure-Dart reader can decode,
/// so this hands the URL to FFmpeg and tunes it for latency rather than
/// smoothness: on an FPV feed a late frame is worse than a dropped one.
class RtspView extends StatefulWidget {
  const RtspView({
    super.key,
    required this.url,
    required this.placeholder,
  });

  final String url;

  /// Shown until the first frame decodes, and whenever the link drops.
  final Widget placeholder;

  @override
  State<RtspView> createState() => RtspViewState();
}

class RtspViewState extends State<RtspView> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(
      // A large buffer would add seconds of lag to a live feed.
      bufferSize: 512 * 1024,
      title: 'Ala-Too Drone',
    ),
  );
  late final VideoController _controller = VideoController(_player);

  bool _hasVideo = false;
  int? _width;
  int? _height;

  /// The drone tags its stream portrait even though the camera is mounted
  /// landscape, so the frame arrives on its side. Deciding from the reported
  /// size rather than hard-coding an angle keeps this correct if a different
  /// board reports it the right way round.
  bool get _needsRotation =>
      _width != null && _height != null && _height! > _width!;

  @override
  void initState() {
    super.initState();
    _configure();
    _open();
  }

  void _configure() {
    final native = _player.platform;
    if (native is! NativePlayer) return;

    // UDP transport is what the drone's own app negotiates; TCP interleaving
    // stalls on this firmware.
    native.setProperty('rtsp-transport', 'udp');
    native.setProperty('profile', 'low-latency');
    native.setProperty('cache', 'no');
    native.setProperty('untimed', 'yes');
    // Never let the decoder wait for a late frame.
    native.setProperty('framedrop', 'decoder+vo');
  }

  Future<void> _open() async {
    _player.stream.width.listen((w) {
      if (!mounted) return;
      setState(() {
        _width = w;
        _hasVideo = w != null && w > 0;
      });
      debugPrint('[rtsp] video width=$w height=$_height');
    });
    _player.stream.height.listen((h) {
      if (!mounted) return;
      setState(() => _height = h);
      debugPrint('[rtsp] video width=$_width height=$h');
    });
    _player.stream.error.listen((e) => debugPrint('[rtsp] error: $e'));
    await _player.open(Media(widget.url), play: true);
  }

  @override
  void didUpdateWidget(RtspView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _player.open(Media(widget.url), play: true);
    }
  }

  /// Grabs the frame currently on screen, for the shutter button.
  Future<Uint8List?> screenshot() => _player.screenshot();

  /// Reconnects, for when the drone's camera drops out mid-flight.
  Future<void> restart() async {
    await _player.stop();
    await _player.open(Media(widget.url), play: true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // contain, not cover: on an FPV feed the pilot needs the whole frame,
        // and cropping it to fill a 21:9 phone hides most of the view.
        RotatedBox(
          quarterTurns: _needsRotation ? 1 : 0,
          child: Video(
            controller: _controller,
            controls: NoVideoControls,
            fit: BoxFit.contain,
            fill: AlatooColors.deep,
          ),
        ),
        if (!_hasVideo) widget.placeholder,
      ],
    );
  }
}
