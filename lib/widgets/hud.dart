import 'package:flutter/material.dart';

import '../protocol/drone_protocol.dart';
import '../theme/alatoo_theme.dart';

/// Status strip along the top of the flight screen.
class HudBar extends StatelessWidget {
  const HudBar({
    super.key,
    required this.link,
    required this.telemetry,
    required this.onBack,
    required this.onSettings,
    this.recording = false,
    this.recordingLabel,
  });

  final LinkState link;
  final Telemetry telemetry;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final bool recording;
  final String? recordingLabel;

  Color get _linkColor => switch (link) {
        LinkState.connected => AlatooColors.ok,
        LinkState.connecting => AlatooColors.warn,
        _ => AlatooColors.crimson,
      };

  @override
  Widget build(BuildContext context) {
    final battery = telemetry.batteryPercent;
    final height = telemetry.heightMeters;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _IconButton(icon: Icons.chevron_left, onTap: onBack),
            const SizedBox(width: 4),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: _linkColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: _linkColor.withValues(alpha: 0.6), blurRadius: 8),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (battery != null) _Chip(
              icon: battery > 20
                  ? Icons.battery_5_bar_rounded
                  : Icons.battery_alert_rounded,
              text: '$battery%',
              tint: battery > 20 ? Colors.white : AlatooColors.crimson,
            ),
            if (height != null) ...[
              const SizedBox(width: 8),
              _Chip(
                icon: Icons.height_rounded,
                text: '${height.toStringAsFixed(1)} м',
              ),
            ],
            const Spacer(),
            if (recording) ...[
              _RecordingPill(label: recordingLabel ?? ''),
              const SizedBox(width: 8),
            ],
            _IconButton(icon: Icons.tune_rounded, onTap: onSettings),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.tint});

  final IconData icon;
  final String text;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RecordingPill extends StatelessWidget {
  const _RecordingPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AlatooColors.crimson,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fiber_manual_record, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}

/// Round translucent action used around the flight screen.
class CockpitButton extends StatelessWidget {
  const CockpitButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.size = 56,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fill = danger
        ? AlatooColors.crimson
        : active
            ? Colors.white
            : Colors.white.withValues(alpha: 0.12);
    final tint = danger
        ? Colors.white
        : active
            ? AlatooColors.navy
            : Colors.white;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: fill,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: tint, size: size * 0.44),
            ),
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: size + 16,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
