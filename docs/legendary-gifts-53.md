# Pulse legendary gifts — Build 53

Adds nine user-supplied legendary gift videos to the existing live gift queue. Prices range from Lion King at 1,000 coins to Pulse Universe at 60,000 coins; coin recharge pricing stays unchanged.

Foreground alpha is prepared offline. Android Impeller uses one packed H264/AAC stream with a synchronized matte shader; Windows and unsupported renderers use alpha WebP with separate audio. Both paths retain the uploaded source timelines (about five seconds), opaque subject cores, transparent borders, sender notices, and combo updates without restarting playback. Final bundled media decode cleanly even where the original generated source contained corrupt packets. Source warning records are retained in art/gift_sources/legendary.json.

Preview never sends a gift. Tapping a gift sends one; the existing +1 control makes another server-authorized purchase. Basic gifts below 300 coins remain notification-only. The existing transaction and idempotency guards are unchanged.

The additive catalog script is supabase/schema/049_legendary_gifts.sql. Backend coverage verifies prices, duplicate-send idempotency, and insufficient-funds rejection. The Windows wildlife provenance test uses portable POSIX paths.

Real-device validation of GPU compositing, audio timing, low-end performance, and two-viewer live synchronization remains necessary.
