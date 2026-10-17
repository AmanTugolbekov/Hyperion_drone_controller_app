import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../protocol/protocol_registry.dart';
import '../services/drone_service.dart';
import '../services/settings_service.dart';
import '../theme/alatoo_theme.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = context.watch<SettingsService>();
    final drone = context.watch<DroneService>();

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: s.t('language')),
          Card(
            child: RadioGroup<AppLang>(
              groupValue: settings.lang,
              onChanged: (v) => v == null ? null : settings.setLang(v),
              child: Column(
                children: [
                  for (final lang in AppLang.values)
                    RadioListTile<AppLang>(
                      value: lang,
                      activeColor: AlatooColors.navy,
                      title: Text(lang.label),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _Section(title: s.t('protocol')),
          Card(
            child: RadioGroup<String>(
              groupValue: settings.protocolId,
              onChanged: (v) => v == null ? null : settings.setProtocolId(v),
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: ProtocolRegistry.autoId,
                    activeColor: AlatooColors.navy,
                    title: Text(s.t('protocol_auto')),
                    subtitle: Text(
                      drone.ssid?.replaceAll('"', '') ?? s.t('unknown_network'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  for (final p in drone.protocols)
                    RadioListTile<String>(
                      value: p.id,
                      activeColor: AlatooColors.navy,
                      title: Text(p.displayName),
                      subtitle: Text(p.defaultEndpoint.toString(),
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _Section(title: s.t('controls')),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.throttleOnLeft,
                  title: Text(s.t('left_stick_throttle')),
                  onChanged: settings.setThrottleOnLeft,
                ),
                SwitchListTile(
                  value: settings.haptics,
                  title: Text(s.t('haptics')),
                  onChanged: settings.setHaptics,
                ),
                SwitchListTile(
                  value: settings.keepScreenOn,
                  title: Text(s.t('keep_screen_on')),
                  onChanged: settings.setKeepScreenOn,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const Icon(Icons.bug_report_rounded,
                  color: AlatooColors.navy),
              title: Text(s.t('diagnostics')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Image.asset('assets/images/alatoo_logo.png', width: 56),
                const SizedBox(height: 10),
                Text(
                  s.t('about_text'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AlatooColors.ink.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: AlatooColors.navy.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
