import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../protocol/drone_scanner.dart';
import '../services/drone_service.dart';
import '../services/settings_service.dart';
import '../theme/alatoo_theme.dart';

/// Lets the drone's address be set by hand and the result watched live. This
/// is how an unknown clone gets identified without rebuilding the app.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late final TextEditingController _host;
  late final TextEditingController _cmdPort;
  late final TextEditingController _videoPort;

  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    final drone = context.read<DroneService>();
    final fallback = drone.protocols.first.defaultEndpoint;

    _host = TextEditingController(
        text: settings.hostOverride ?? fallback.host);
    _cmdPort = TextEditingController(
        text: '${settings.cmdPortOverride ?? fallback.commandPort}');
    _videoPort = TextEditingController(
        text: '${settings.videoPortOverride ?? fallback.videoPort}');
  }

  @override
  void dispose() {
    _host.dispose();
    _cmdPort.dispose();
    _videoPort.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context.read<SettingsService>().setEndpointOverride(
          host: _host.text.trim(),
          cmdPort: int.tryParse(_cmdPort.text.trim()),
          videoPort: int.tryParse(_videoPort.text.trim()),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).t('ok'))),
      );
    }
  }

  Future<void> _test() async {
    await _save();
    if (!mounted) return;
    await context.read<DroneService>().connect();
  }

  /// Knocks on every port this drone family is known to use and writes the
  /// findings into the log, so an unidentified board can be worked out from
  /// what actually answered.
  Future<void> _scan() async {
    final drone = context.read<DroneService>();
    setState(() => _scanning = true);
    try {
      final host = _host.text.trim().isEmpty
          ? (drone.gateway ?? '192.168.1.1')
          : _host.text.trim();
      await DroneScanner(onLog: drone.addLog).scan(host);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _copyLog() async {
    final drone = context.read<DroneService>();
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    await Clipboard.setData(
      ClipboardData(text: drone.log.reversed.join('\n')),
    );
    if (mounted) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('log_copied'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final drone = context.watch<DroneService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('diagnostics')),
        actions: [
          IconButton(
            onPressed: _copyLog,
            icon: const Icon(Icons.copy_rounded),
            tooltip: s.t('copy_log'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _host,
                  decoration: InputDecoration(labelText: s.t('host')),
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cmdPort,
                        decoration:
                            InputDecoration(labelText: s.t('cmd_port')),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _videoPort,
                        decoration:
                            InputDecoration(labelText: s.t('video_port')),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _save,
                        child: Text(s.t('save')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _test,
                        child: Text(s.t('test_connection')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: _scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar_rounded, size: 18),
                  label: Text(
                      _scanning ? s.t('scanning') : s.t('scan_drone')),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                s.t('log').toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AlatooColors.navy.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AlatooColors.deep,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListView.builder(
                itemCount: drone.log.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    drone.log[i],
                    style: const TextStyle(
                      color: Color(0xFF9FD0A0),
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
