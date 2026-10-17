import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth.dart';
import 'back_guard.dart';
import 'account_gate.dart';
import 'control.dart';
import 'home.dart';
import 'security.dart';
import 'notifications.dart';
import 'push.dart';
import 'appearance.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 60;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 * 1024 * 1024;
  runApp(const PulseStartup());
}

class PulseStartup extends StatefulWidget {
  const PulseStartup({super.key});
  @override
  State<PulseStartup> createState() => _PulseStartupState();
}

class _PulseStartupState extends State<PulseStartup> {
  bool ready = false;
  String? error;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    try {
      await PulseAppearance.instance.restoreBootStyle();
      if (url.isEmpty || key.isEmpty)
        throw const FormatException(
          'Pulse needs backend configuration. Build with --dart-define-from-file=config.local.json.',
        );
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        authOptions: const FlutterAuthClientOptions(
          localStorage: SecureSessionStorage(),
        ),
      );
      await PulseAppearance.instance.load(
        Supabase.instance.client.auth.currentUser?.id,
      );
      if (!const bool.fromEnvironment('PULSE_STAFF')) {
        await PulseNotifications.instance.initialize();
        await PulsePush.instance.initialize();
      }
      if (mounted) setState(() => ready = true);
    } catch (e) {
      if (mounted)
        setState(
          () => error = e is FormatException
              ? e.message.toString()
              : 'Pulse could not initialize. Check local storage and restart the app.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => ready
      ? const PulseApp()
      : AnimatedBuilder(
          animation: PulseAppearance.instance,
          builder: (_, __) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: PulseAppearance.instance.theme(Brightness.light),
            darkTheme: PulseAppearance.instance.theme(Brightness.dark),
            themeMode: PulseAppearance.instance.mode,
            home: error == null
                ? const PulseSplash()
                : Scaffold(
                    body: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(error!),
                      ),
                    ),
                  ),
          ),
        );
}

class PulseApp extends StatefulWidget {
  const PulseApp({super.key});
  @override
  State<PulseApp> createState() => _PulseAppState();
}

class _PulseAppState extends State<PulseApp> {
  final appearance = PulseAppearance.instance;
  late final StreamSubscription<AuthState> auth;
  final navigator = GlobalKey<NavigatorState>();
  String? previousUid;
  Map<String, dynamic>? restriction;
  bool appealMode = false;
  static const staffApp = bool.fromEnvironment('PULSE_STAFF');
  @override
  void initState() {
    super.initState();
    previousUid = Supabase.instance.client.auth.currentUser?.id;
    auth = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      final currentUid = Supabase.instance.client.auth.currentUser?.id;
      if (currentUid != previousUid) {
        navigator.currentState?.popUntil((route) => route.isFirst);
        previousUid = currentUid;
        appearance.load(currentUid);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    auth.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appearance,
    builder: (_, __) => MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigator,
      title: staffApp
          ? 'Pulse Control'
          : Platform.isWindows
          ? 'Pulse'
          : 'PULSE',
      theme: appearance.theme(Brightness.light),
      darkTheme: appearance.theme(Brightness.dark),
      themeMode: appearance.mode,
      themeAnimationDuration:
          MediaQueryData.fromView(View.of(context)).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 250),
      home: PulseBackGuard(
        child: !appearance.ready
            ? const PulseSplash()
            : Supabase.instance.client.auth.currentSession == null
            ? restriction == null
                  ? AuthScreen(allowRegistration: !staffApp && !appealMode)
                  : PulseRestrictionNotice(
                      status: restriction!,
                      onAppeal: () => setState(() {
                        appealMode = true;
                        restriction = null;
                      }),
                      onBack: () => setState(() {
                        restriction = null;
                        appealMode = false;
                      }),
                    )
            : PulseAccountGate(
                key: ValueKey(
                  'access:${Supabase.instance.client.auth.currentUser!.id}:$appealMode',
                ),
                appealMode: appealMode,
                onRestricted: (s) async {
                  if (mounted)
                    setState(() {
                      restriction = s;
                      appealMode = false;
                    });
                  try {
                    await PulseNotifications.instance.clearAll();
                  } catch (_) {}
                  await Supabase.instance.client.auth.signOut(
                    scope: SignOutScope.local,
                  );
                },
                child: staffApp
                    ? const PulseControl()
                    : HomeScreen(
                        key: ValueKey(
                          Supabase.instance.client.auth.currentUser!.id,
                        ),
                        toggleTheme: () {
                          appearance
                              .set(
                                appearance.settings.copy(
                                  mode: appearance.settings.mode == 'dark'
                                      ? 'light'
                                      : 'dark',
                                ),
                              )
                              .catchError((_) {});
                        },
                      ),
              ),
      ),
    ),
  );
}
