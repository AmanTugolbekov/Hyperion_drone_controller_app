import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../protocol/drone_protocol.dart';
import '../services/drone_service.dart';
import '../theme/alatoo_theme.dart';
import 'flight_screen.dart';
import 'settings_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  /// Android needs location permission before it will reveal the Wi-Fi name,
  /// which is how the protocol is guessed.
  Future<void> _prepare() async {
    await Permission.locationWhenInUse.request();
    if (!mounted) return;
    await context.read<DroneService>().refreshSsid();
  }

  Future<void> _connect() async {
    final drone = context.read<DroneService>();
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);

    final ok = await drone.connect();
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FlightScreen()),
      );
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(s.t('conn_failed')),
        backgroundColor: AlatooColors.crimson,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final drone = context.watch<DroneService>();
    final connecting = drone.link == LinkState.connecting;

    return Scaffold(
      body: Column(
        children: [
          _Header(subtitle: s.t('app_subtitle'), title: s.t('app_title')),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.wifi_rounded,
                                  color: AlatooColors.navy),
                              const SizedBox(width: 10),
                              Text(s.t('current_network'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            drone.ssid?.replaceAll('"', '') ??
                                s.t('unknown_network'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AlatooColors.navy,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            s.t('connect_hint'),
                            style: TextStyle(
                                color: AlatooColors.ink.withValues(alpha: 0.65),
                                height: 1.4),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: () => openAppSettings(),
                            icon: const Icon(Icons.settings_rounded, size: 18),
                            label: Text(s.t('open_wifi')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: connecting ? null : _connect,
                    icon: connecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.link_rounded),
                    label: Text(
                        connecting ? s.t('searching') : s.t('connect_btn')),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(s.t('settings')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AlatooColors.brandGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Image.asset('assets/images/alatoo_logo.png',
                  width: 46, height: 46),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
