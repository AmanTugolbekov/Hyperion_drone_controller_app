import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/strings.dart';
import 'services/drone_service.dart';
import 'services/media_service.dart';
import 'services/settings_service.dart';
import 'screens/splash_screen.dart';
import 'theme/alatoo_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Required before any Player is constructed for the RTSP camera.
  MediaKit.ensureInitialized();

  final settings = SettingsService();
  await settings.load();

  runApp(AlatooDroneApp(settings: settings));
}

class AlatooDroneApp extends StatelessWidget {
  const AlatooDroneApp({super.key, required this.settings});

  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => DroneService(settings)),
        ChangeNotifierProxyProvider<DroneService, MediaService>(
          create: (ctx) => MediaService(ctx.read<DroneService>()),
          update: (_, drone, previous) => previous ?? MediaService(drone),
        ),
      ],
      child: Consumer<SettingsService>(
        builder: (_, s, __) => MaterialApp(
          title: 'Ala-Too Drone',
          debugShowCheckedModeBanner: false,
          theme: AlatooTheme.light(),
          // Material's own widgets only ship Russian and English here; the
          // app's strings are resolved from settings by `S`, so Kyrgyz maps
          // onto the Russian chrome.
          locale: s.lang == AppLang.en
              ? const Locale('en')
              : const Locale('ru'),
          supportedLocales: const [Locale('ru'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
