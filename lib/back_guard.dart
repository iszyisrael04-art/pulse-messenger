import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'profile_rules.dart';

/// Wrap only the root route; pushed screens and dialogs keep normal Back behavior.
class PulseBackGuard extends StatefulWidget {
  const PulseBackGuard({super.key, required this.child});
  final Widget child;
  @override
  State<PulseBackGuard> createState() => _PulseBackGuardState();
}

class _PulseBackGuardState extends State<PulseBackGuard>
    with WidgetsBindingObserver {
  final presses = PulseExitPresses();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) presses.reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !Platform.isAndroid,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop || !Platform.isAndroid) return;
      if (MediaQuery.viewInsetsOf(context).bottom > 0) {
        FocusManager.instance.primaryFocus?.unfocus();
        presses.reset();
        return;
      }
      if (presses.press(DateTime.now())) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        SystemNavigator.pop();
      } else {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Press Back again to close Pulse'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    },
    child: widget.child,
  );
}
