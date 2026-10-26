# Magic gifts and chat previews

Wizard and witch are available in two forms: cinematic scenes (The Archmage and Moonlight Witch), and wearable Wizard/Witch Head Filters. Original art was made with built-in image generation; exact prompts and SHA256 receipts are in art/magic. Scene characters are detailed 2D artwork with animated spell particles, mist, sigils and camera motion, not skeletal 3D characters. Runtime hats are alpha-preserving 512px WebP overlays.

Head filters reuse the existing on-device face sampler with contained-video/mirror/roll mapping, 350ms throttling, foreground-only sampling and deletion of temporary snapshots. No new upload, identification or face database. Hat overlays stay on the host for 12 seconds and hide when face tracking is lost. LIVE gift events show a short non-blocking sender notice while the host stays visible. Free Shop/tray previews use separate artwork demonstration clips; these do not claim to track a face. Real device acceptance remains necessary.

Chat summaries were missing from production. Migration 046 restores the guarded member-only RPC, latest non-hidden/non-deleted message, sender identity, and sent/delivered/read state. Group double ticks require delivery to all other current members; blue ticks require all to read. Incoming messages never show outgoing ticks. Blocking and account restrictions remain enforced. No existing messages are removed.

The preview website needs no app installation. Native changes ship in 0.1.0+49. Retired abstract gifts are disabled for new sends, with historical events/media retained. New gift prices are 15,999/18,999 (filters) and 79,999/84,999 (scenes); existing gift economics otherwise remain unchanged.
