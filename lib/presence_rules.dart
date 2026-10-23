class PulseActiveStatus {
  const PulseActiveStatus(this.until, this.lastSeen);
  factory PulseActiveStatus.fromServer(Map data, DateTime checkedAt) {
    final seconds = data['online'] == true && data['expires_in'] is num
        ? (data['expires_in'] as num).toInt().clamp(0, 70)
        : 0;
    return PulseActiveStatus(
      checkedAt.add(Duration(seconds: seconds)),
      DateTime.tryParse(data['last_seen']?.toString() ?? ''),
    );
  }
  final DateTime until;
  final DateTime? lastSeen;
  bool online(DateTime now) => now.isBefore(until);
  String label(DateTime now) {
    if (online(now)) return 'Online now';
    final seen = lastSeen;
    if (seen == null) return '';
    final age = now.difference(seen);
    if (age.inMinutes < 1) return 'Last seen just now';
    if (age.inMinutes < 60) return 'Last seen ${age.inMinutes}m ago';
    if (age.inHours < 24) return 'Last seen ${age.inHours}h ago';
    if (age.inDays == 1) return 'Last seen yesterday';
    return 'Last seen ${age.inDays}d ago';
  }
}
