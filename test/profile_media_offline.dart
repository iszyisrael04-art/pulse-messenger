import '../lib/profile_media_rules.dart';
import '../lib/activity_alerts.dart';
import '../lib/live_diagnostics.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  for (final duration in [1, 250, 4999, 5000, 5001, 20000, 180000]) {
    for (final start in [-100, 0, 1000, duration - 1, duration + 5000]) {
      final clip = profileVideoRange(duration, start);
      check(
        clip.start >= 0 &&
            clip.end <= duration &&
            clip.end > clip.start &&
            clip.end - clip.start <= 5000,
        'Profile trim bounds',
      );
    }
  }
  check(
    profileVideoRange(20000, 7000) == (start: 7000, end: 12000),
    'Selected clip start is preserved',
  );
  check(isProfileVideo('owner/clip.MP4'), 'MP4 detection');
  check(
    profilePosterPath('owner/clip.mp4') == 'owner/clip-poster.jpg',
    'Static poster path',
  );
  final alerts = PulseActivityAlerts();
  Map<String, dynamic> event(String id, {bool read = false}) => {
    'id': id,
    'kind': 'like',
    'read': read,
  };
  check(alerts.collect([event('old')]).isEmpty, 'Do not replay old alerts');
  check(
    alerts.collect([event('new'), event('old')])['like'] == 1,
    'Notify new like',
  );
  check(alerts.collect([event('new')]).isEmpty, 'No duplicate notification');
  check(
    alerts.collect([event('seen')], viewing: true).isEmpty,
    'Suppress while activity is open',
  );
  check(
    alerts.collect([event('read', read: true)]).isEmpty,
    'Suppress read items',
  );
  final cutoff = PulseActivityAlerts();
  cutoff.collect([], asOf: '2026-10-23T12:00:00Z');
  check(
    cutoff.collect([
      {'id': 'earlier', 'kind': 'like', 'created_at': '2026-10-22T12:00:00Z'},
    ]).isEmpty,
    'Enabling a category does not replay old events',
  );
  check(
    cutoff.collect([
          {
            'id': 'later',
            'kind': 'comment',
            'created_at': '2026-10-23T12:01:00Z',
          },
        ])['comment'] ==
        1,
    'Events after session baseline notify',
  );
  check(
    pulseActivityAlertBody('follow', 2) == '2 new followers',
    'Follower alert',
  );
  check(
    pulseLiveCheckMessage({'control_plane': true}).contains('two devices'),
    'Server check is not a media test',
  );
  check(
    pulseLiveCheckMessage({
      'code': 'not_configured',
    }, status: 503).contains('not configured'),
    'Configuration guidance',
  );
  check(
    pulseLiveCheckMessage(null, status: 401).contains('Sign in'),
    'Authentication guidance',
  );
  print(
    'PASS: profile trim bounds, posters, alert deduplication and LIVE diagnostics',
  );
}
