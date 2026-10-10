import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth.dart';
import 'home.dart';
import 'security.dart';
import 'notifications.dart';
import 'push.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  if (url.isEmpty || key.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Pulse needs backend configuration.\nBuild with --dart-define-from-file=config.local.json.',
            ),
          ),
        ),
      ),
    );
    return;
  }
  try {
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      authOptions: const FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(),
      ),
    );
    await PulseNotifications.instance.initialize();
    await PulsePush.instance.initialize();
    runApp(const PulseApp());
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Pulse could not initialize secure storage. Restart the app.',
            ),
          ),
        ),
      ),
    );
  }
}

class PulseApp extends StatefulWidget {
  const PulseApp({super.key});
  @override
  State<PulseApp> createState() => _PulseAppState();
}

class _PulseAppState extends State<PulseApp> {
  ThemeMode mode = ThemeMode.dark;
  late final StreamSubscription<AuthState> auth;
  @override
  void initState() {
    super.initState();
    auth = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    auth.cancel();
    super.dispose();
  }

  ThemeData theme(Brightness b) => ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff00bfa6),
      secondary: const Color(0xffff7c68),
      tertiary: const Color(0xffa58bff),
      brightness: b,
    ),
    scaffoldBackgroundColor: b == Brightness.dark
        ? const Color(0xff102026)
        : const Color(0xfff3faf8),
    navigationBarTheme: const NavigationBarThemeData(
      indicatorColor: Color(0xff00bfa6),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      indicatorColor: Color(0xff00bfa6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Pulse Messenger',
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: mode,
    home: Supabase.instance.client.auth.currentSession == null
        ? const AuthScreen()
        : HomeScreen(
            key: ValueKey(Supabase.instance.client.auth.currentUser!.id),
            toggleTheme: () {
              setState(
                () => mode = mode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark,
              );
            },
          ),
  );
}
