import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/strings.dart';
import '../services/drone_service.dart';
import '../services/media_service.dart';
import '../services/settings_service.dart';
import '../theme/alatoo_theme.dart';
import '../widgets/hud.dart';
import '../widgets/joystick.dart';
import '../widgets/rtsp_view.dart';
import 'settings_screen.dart';

class FlightScreen extends StatefulWidget {
  const FlightScreen({super.key});

  @override
  State<FlightScreen> createState() => _FlightScreenState();
}

class _FlightScreenState extends State<FlightScreen> {
  StreamSubscription<AccelerometerEvent>? _tiltSub;
  Timer? _recTicker;

  final GlobalKey<RtspViewState> _rtspKey = GlobalKey<RtspViewState>();

  bool _tiltMode = false;
  bool _headless = false;
  int _speedRate = 1;
  bool _showTrim = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final settings = context.read<SettingsService>();
    if (settings.keepScreenOn) WakelockPlus.enable();
    context.read<DroneService>().setVideoEnabled(true);
  }

  @override
  void dispose() {
    _tiltSub?.cancel();
    _recTicker?.cancel();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _buzz() {
    if (context.read<SettingsService>().haptics) HapticFeedback.mediumImpact();
  }

  void _toggleTilt() {
    final drone = context.read<DroneService>();
    setState(() => _tiltMode = !_tiltMode);

    if (!_tiltMode) {
      _tiltSub?.cancel();
      _tiltSub = null;
      drone.setSticks(roll: 0, pitch: 0);
      return;
    }

    // Phone held in landscape: x is the nose axis, y is the wing axis.
    // 4 m/s² of tilt maps to full stick, which is roughly 24°.
    _tiltSub = accelerometerEventStream().listen((e) {
      drone.setSticks(
        roll: (e.y / 4).clamp(-1.0, 1.0),
        pitch: (-e.x / 4).clamp(-1.0, 1.0),
      );
    });
  }

  Future<void> _takePhoto() async {
    _buzz();
    final media = context.read<MediaService>();
    final drone = context.read<DroneService>();
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);

    // With RTSP the frames live inside FFmpeg, so the shutter asks the player
    // for the picture instead of reading a decoded frame from the protocol.
    final file = drone.rtspUrl != null
        ? await media.savePhotoBytes(await _rtspKey.currentState?.screenshot())
        : await media.takePhoto();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(file == null ? s.t('no_video') : s.t('photo_saved')),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _toggleRecording() async {
    _buzz();
    final media = context.read<MediaService>();
    final drone = context.read<DroneService>();
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final overRtsp = drone.rtspUrl != null;

    if (media.isRecording) {
      _recTicker?.cancel();
      _recTicker = null;

      final file = await media.stopRecording();

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(file == null ? s.t('no_video') : s.t('video_saved')),
        duration: const Duration(seconds: 2),
      ));
    } else {
      if (overRtsp) {
        // The decoded frames never reach the protocol layer, so the clip is
        // built from what the player can hand back.
        final view = _rtspKey.currentState;
        if (view == null || view.videoWidth == null) {
          if (!mounted) return;
          messenger.showSnackBar(SnackBar(
            content: Text(s.t('no_video')),
            duration: const Duration(seconds: 2),
          ));
          return;
        }
        media.startRecording(
          width: view.videoWidth!,
          height: view.videoHeight ?? view.videoWidth!,
          frameSource: view.screenshot,
        );
      } else {
        media.startRecording();
      }
      _recTicker = Timer.periodic(
          const Duration(seconds: 1), (_) => setState(() {}));
    }
    if (mounted) setState(() {});
  }

  Future<void> _confirmExit() async {
    final drone = context.read<DroneService>();
    if (drone.isFlying) {
      await drone.land();
    }
    await drone.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final drone = context.watch<DroneService>();
    final media = context.watch<MediaService>();
    final settings = context.watch<SettingsService>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: AlatooColors.deep,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (drone.rtspUrl != null)
              RtspView(
                key: _rtspKey,
                url: drone.rtspUrl!,
                placeholder:
                    _VideoLayer(frame: null, emptyLabel: s.t('connecting')),
              )
            else
              _VideoLayer(
                  frame: drone.lastFrame, emptyLabel: s.t('no_video')),
            Column(
              children: [
                HudBar(
                  link: drone.link,
                  telemetry: drone.telemetry,
                  onBack: _confirmExit,
                  onSettings: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  recording: media.isRecording,
                  recordingLabel: _formatDuration(media.recordingLength),
                ),
                if (!drone.wifiBound) _WifiWarning(text: s.t('wifi_not_bound')),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // The cockpit needs the width of a landscape phone.
                        // The orientation lock takes a frame or two to apply,
                        // so this also covers the portrait frames in between
                        // rather than letting them overflow.
                        if (constraints.maxWidth < 560) {
                          return _RotateHint(text: s.t('rotate_phone'));
                        }

                        // Sticks shrink on small phones so the controls in the
                        // middle always keep room.
                        final stickSize = (constraints.maxWidth * 0.22)
                            .clamp(110.0, 180.0)
                            .toDouble();

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _leftStick(drone, settings, stickSize),
                            Expanded(
                                child: _centreColumn(drone, media, s)),
                            _rightStick(drone, settings, s, stickSize),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            if (_showTrim)
              _TrimPanel(
                onClose: () => setState(() => _showTrim = false),
                title: s.t('trim'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _leftStick(
      DroneService drone, SettingsService settings, double stickSize) {
    // On a drone that holds its own altitude the throttle stick means
    // climb/descend and must spring back; on one without it, throttle is raw
    // motor power and has to stay where the pilot left it.
    final isThrottle = settings.throttleOnLeft;
    final springs = drone.activeProtocol?.throttleIsBidirectional ?? true;
    return Joystick(
      key: ValueKey('left-$isThrottle-$springs'),
      size: stickSize,
      haptics: settings.haptics,
      returnBehavior: isThrottle && !springs
          ? JoystickReturn.horizontalOnly
          : JoystickReturn.both,
      labelY: isThrottle ? 'THR' : 'PITCH',
      labelX: isThrottle ? 'YAW' : 'ROLL',
      onChanged: (x, y) => isThrottle
          ? drone.setSticks(yaw: x, throttle: (y + 1) / 2)
          : drone.setSticks(roll: x, pitch: y),
    );
  }

  Widget _rightStick(DroneService drone, SettingsService settings, S s,
      double stickSize) {
    final isThrottle = !settings.throttleOnLeft;
    final springs = drone.activeProtocol?.throttleIsBidirectional ?? true;
    if (_tiltMode && !isThrottle) {
      return SizedBox(
        width: stickSize,
        height: stickSize,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.screen_rotation_alt_rounded,
                  size: 44, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(height: 10),
              Text(s.t('gyro_mode'),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
            ],
          ),
        ),
      );
    }

    return Joystick(
      key: ValueKey('right-$isThrottle-$springs'),
      size: stickSize,
      haptics: settings.haptics,
      returnBehavior: isThrottle && !springs
          ? JoystickReturn.horizontalOnly
          : JoystickReturn.both,
      labelY: isThrottle ? 'THR' : 'PITCH',
      labelX: isThrottle ? 'YAW' : 'ROLL',
      onChanged: (x, y) => isThrottle
          ? drone.setSticks(yaw: x, throttle: (y + 1) / 2)
          : drone.setSticks(roll: x, pitch: y),
    );
  }

  Widget _centreColumn(DroneService drone, MediaService media, S s) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Scrollable so a narrow phone or a longer translation can never push
        // a control off the edge.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CockpitButton(
              icon: Icons.photo_camera_rounded,
              label: s.t('photo'),
              onTap: _takePhoto,
              size: 48,
            ),
            const SizedBox(width: 10),
            CockpitButton(
              icon: media.isRecording
                  ? Icons.stop_rounded
                  : Icons.videocam_rounded,
              label: s.t('video'),
              onTap: _toggleRecording,
              active: media.isRecording,
              size: 48,
            ),
            const SizedBox(width: 10),
            CockpitButton(
              icon: Icons.threesixty_rounded,
              label: s.t('flip'),
              onTap: () {
                _buzz();
                drone.flip();
              },
              size: 48,
            ),
            const SizedBox(width: 10),
            CockpitButton(
              icon: Icons.explore_rounded,
              label: s.t('headless'),
              active: _headless,
              size: 48,
              onTap: () {
                _buzz();
                setState(() => _headless = !_headless);
                drone.setHeadless(_headless);
              },
            ),
            const SizedBox(width: 10),
            CockpitButton(
              icon: Icons.screen_rotation_alt_rounded,
              label: s.t('gyro_mode'),
              active: _tiltMode,
              size: 48,
              onTap: () {
                _buzz();
                _toggleTilt();
              },
            ),
            const SizedBox(width: 10),
            CockpitButton(
              icon: Icons.tune_rounded,
              label: s.t('trim'),
              active: _showTrim,
              size: 48,
              onTap: () => setState(() => _showTrim = !_showTrim),
            ),
          ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SpeedSelector(
              rate: _speedRate,
              onChanged: (r) {
                _buzz();
                setState(() => _speedRate = r);
                drone.setSpeedRate(r);
              },
            ),
            const SizedBox(width: 18),
            CockpitButton(
              icon: drone.isFlying
                  ? Icons.flight_land_rounded
                  : Icons.flight_takeoff_rounded,
              label: drone.isFlying ? s.t('land') : s.t('takeoff'),
              onTap: () {
                _buzz();
                drone.isFlying ? drone.land() : drone.takeOff();
              },
            ),
            const SizedBox(width: 18),
            CockpitButton(
              icon: Icons.power_settings_new_rounded,
              label: s.t('stop'),
              danger: true,
              onTap: () {
                HapticFeedback.heavyImpact();
                drone.emergencyStop();
              },
            ),
          ],
        ),
      ],
    );
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }
}

/// Stands in for the cockpit while the screen is too narrow for it, which
/// happens for the frame or two before the landscape lock takes effect.
class _RotateHint extends StatelessWidget {
  const _RotateHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.screen_rotation_rounded,
              size: 44, color: Colors.white.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the sockets could not be pinned to Wi-Fi, which on Android
/// usually means the control stream is leaking to mobile data.
class _WifiWarning extends StatelessWidget {
  const _WifiWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AlatooColors.warn.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: AlatooColors.ink),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AlatooColors.ink,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoLayer extends StatelessWidget {
  const _VideoLayer({required this.frame, required this.emptyLabel});

  final Uint8List? frame;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (frame != null) {
      return Image.memory(
        frame!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AlatooColors.navy, AlatooColors.deep],
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: 0.18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/alatoo_logo.png', width: 96),
              const SizedBox(height: 14),
              Text(emptyLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedSelector extends StatelessWidget {
  const _SpeedSelector({required this.rate, required this.onChanged});

  final int rate;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['30%', '60%', '100%'];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final selected = i == rate;
          return GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  color: selected ? AlatooColors.navy : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Fine offsets that cancel a drone's natural drift.
class _TrimPanel extends StatelessWidget {
  const _TrimPanel({required this.onClose, required this.title});

  final VoidCallback onClose;
  final String title;

  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneService>();
    final input = drone.input;

    return Positioned.fill(
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 340,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AlatooColors.panel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white70),
                      ),
                    ],
                  ),
                  _TrimRow(
                    label: 'ROLL',
                    value: input.rollTrim,
                    onChanged: (v) => drone.setTrim(roll: v),
                  ),
                  _TrimRow(
                    label: 'PITCH',
                    value: input.pitchTrim,
                    onChanged: (v) => drone.setTrim(pitch: v),
                  ),
                  _TrimRow(
                    label: 'YAW',
                    value: input.yawTrim,
                    onChanged: (v) => drone.setTrim(yaw: v),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => drone.calibrateGyro(),
                    icon: const Icon(Icons.compass_calibration_rounded,
                        size: 18, color: Colors.white),
                    label: Text(S.of(context).t('calibrate'),
                        style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrimRow extends StatelessWidget {
  const _TrimRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(-0.3, 0.3),
            min: -0.3,
            max: 0.3,
            divisions: 12,
            activeColor: AlatooColors.crimson,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ],
    );
  }
}
