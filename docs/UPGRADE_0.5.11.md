# Pulse 0.5.11

- Green online indicators appear on direct-chat, profile, feed, Reels, search and share-recipient avatars when the server permits visibility. Group pictures never inherit the owner's online status. Missing profile photos still support presence.
- Direct chat headers and profiles show Online now or last seen. Unknown, hidden or unauthorized presence shows no status.
- Settings > Active status > Share active status controls online and last seen together. Default visibility is accepted direct-chat contacts and approved followers. Pending message requests, strangers, blocks and restricted accounts are excluded on the server.
- Foreground clients send a heartbeat and reconcile status roughly every 25 seconds. Background/exit sends an offline update for that device. Multiple devices are independent. Interrupted connections expire after a 70-second server lease; older or reordered heartbeats cannot resurrect a closed device. Offline fetch failures clear local status rather than guessing that someone remains online. No presence cache is persisted.
- Device activity and privacy preferences live in private, RLS-protected tables with no direct client grants. Device timestamps older than seven days are pruned when that account next sends a heartbeat.

## Validation

Isolated SQL security tests cover device isolation, multi-device activity, stale leases, out-of-order heartbeats, pending-request privacy, blocked users, hidden status and anonymous/direct-table denial. Offline Dart tests and analysis cover lease bounds and last-seen labels. Lifecycle/privacy race tests are added for Flutter CI. Full Flutter analysis, widget tests, Android/Windows builds and two-device foreground/background smoke tests remain pending.

027_active_status.sql is ready; applying it to the connected backend is pending migration approval. Existing account/chat/post records are preserved.
