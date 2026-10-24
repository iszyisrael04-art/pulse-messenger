import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_messenger/social_download.dart';

void main() {
  testWidgets('download progress leaves navigation usable and can cancel', (
    tester,
  ) async {
    var cancelled = false, navigated = false;
    pulseDownloads.value = {
      'post': PulseDownloadState('Downloading', .4, () => cancelled = true),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Text('Video description'),
              const PulseDownloadProgress(postId: 'post'),
              TextButton(
                onPressed: () => navigated = true,
                child: const Text('Next video'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Downloading · 40%'), findsOneWidget);
    await tester.tap(find.text('Next video'));
    expect(navigated, isTrue);
    await tester.tap(find.byTooltip('Cancel download'));
    expect(cancelled, isTrue);
    pulseDownloads.value = {};
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
