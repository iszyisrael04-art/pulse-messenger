# Feature status — Pulse 0.2

See [UPDATE_0.2.md](UPDATE_0.2.md) for setup, deployment and exact validation limits.

| Feature | Status |
|---|---|
| Email/password, username/password, persistent sessions | Implemented; email delivery requires configured SMTP |
| Phone OTP | Auth client implemented; SMS provider required |
| Profiles/private and group messaging, receipts/replies/reactions/files/offline queue | Implemented staged beta; native device testing required |
| Text status, groups | Implemented baseline; advanced community/media features pending |
| Channel announcements/admins/photos/following/reactions | Implemented; schema deployed |
| Channel livestream and follower live chat | Client/server implemented; LiveKit credentials and media tests required |
| Local Android/Windows message alerts | Implemented; OS/device testing required; running process only |
| Android closed-app FCM push | Client/queue/dispatcher code implemented; Firebase setup, scheduler and explicit deployment approval required |
| Windows closed-app push | Not implemented |
| Voice/video private or group calls | Not implemented |
| Premium/promo screens | Removed for now; old backend records preserved |
| Gifts/coins/payments | Deferred; not implemented |
| End-to-end encryption | Not implemented; no E2EE claim |
| Automatic updates/code signing/app store distribution | Not implemented; documented architecture only |

Do not market this beta as a complete production messaging platform.
