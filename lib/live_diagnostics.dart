String pulseLiveCheckMessage(Object? response, {int? status}) {
  final data = response is Map ? response : const {};
  if (data['control_plane'] == true)
    return 'LiveKit server connected. Verify camera and microphone with two devices before calling LIVE confirmed.';
  if (data['code'] == 'not_configured' || status == 503)
    return 'LIVE is not configured on the server. The owner must set a valid LiveKit URL, API key and API secret.';
  if (status == 401) return 'Sign in again before checking LIVE.';
  if (status == 403)
    return 'An active Pulse account is required to check LIVE.';
  if (status == 429) return 'Too many checks. Wait a minute, then retry.';
  return 'Could not connect to the LiveKit server. Check the server address, credentials and network, then retry.';
}
