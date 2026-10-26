# Wildlife gifts, plain notifications and one-unit combos

Build 52 replaces gift renderers with static flat icons/animal thumbnails and licensed wildlife MP4s. All previous cinema/effect/hat runtime media, original source GLBs and magic WebP artwork are removed from the current tree. Procedural gift mesh/story/filter Dart modules and their obsolete tests are removed. Historical catalog rows, receipts, prices, wallet balances, earnings and gifter ranks are preserved. Old synthetic character/effect/filter gifts and Pulse Universe are disabled for new sends; lion, gorilla, royal lions, falcon and butterfly are restored. Butterfly costs 50 and is notification-only. Old installed binaries retain their bundled media until updated.

The uploaded TikTok compilation was inspected as a reference only; it is not embedded, cropped to hide branding or republished. Four 5-second landscape MP4s use real lion, gorilla and falcon footage; these are wildlife recordings, not animated characters. Lion and Royal Lions use two excerpts from the same licensed safari video. Original audio is preserved where present; silent source footage is not falsely presented as a roar. No generated particles, 3D, face filters or synthetic gift effects run.

All gifts show a plain left-side notification above LIVE chat: sender avatar/name, gift image and count. Gifts below 300 coins (including Rose, Heart and Crown) never play video, regardless of combo total. Non-video gifts remain notification-only even if more expensive. Video choice is a code allowlist, not a URL supplied by an event. Reduced-motion and decoder failures use the same plain notice. Playback pauses offscreen/background, decoder errors fall back and an 8-second deadline releases the queue. The host camera is never wrapped in gift face tracking.

Gallery selection and free Preview do not spend. Send 1 now immediately submits quantity=1 with a new UUID. There is no quantity/confirmation dialog. Each acknowledged send offers a 12-second +1 button for the same recipient/gift and shows the per-gift coin cost and combo count. While sending the button is disabled. Unknown/failed responses keep the original pending UUID; retry uses that ID, and other sends are blocked until resolved/dismissed. The existing locked server transaction owns balance checks and deductions; local state never grants coins or P-coins. Test coins remain separate.

Viewer notices group consecutive same-sender/same-recipient/same-gift/same-test-state events within 12 seconds. Grouping is presentation-only; every real +1 has its own paid server event. The LIVE queue updates an existing combo notice rather than replaying a separate movie for every tap. Server feed now includes unit coin price, preserving active-account, live-read, cursor and block guards.

## Footage credits and licenses

- Lion and Royal Lions: Coverr, Lions in the wild, CC0 1.0. https://commons.wikimedia.org/wiki/File:Lions_in_the_wild.webm ; https://creativecommons.org/publicdomain/zero/1.0/
- Gorilla: TheLeftCoast, Wild Western Lowland gorilla and his family foraging for figs, CC BY 4.0. https://commons.wikimedia.org/wiki/File:Wild_Western_Lowland_gorilla_and_his_family_foraging_for_figs.webm ; https://creativecommons.org/licenses/by/4.0/
- Falcon: Paul Hurtado, Peregrine falcon in West Reno, Nevada, USA, CC BY-SA 2.0. https://commons.wikimedia.org/wiki/File:Peregrine_falcon_(Falco_peregrinus)_in_West_Reno,_Nevada,_USA.webm ; https://creativecommons.org/licenses/by-sa/2.0/

All were trimmed, resized and re-encoded; thumbnails extracted. Falcon MP4/thumbnail derivatives remain CC BY-SA 2.0. No endorsement by these creators is implied. Full source URLs, licenses, source/output SHA-256 hashes and sizes are recorded in art/gift_sources/wildlife.json and displayed through Shop → Footage credits; preview pages include source/license links. The encoder script reproduces outputs from pinned source hashes.

## Verification

Python validates exact asset inventory, hashes, MP4 headers, thumbnail dimensions, attribution and removal of obsolete runtime modules. Full isolated backend tests cover restored/retired catalog entries, duplicate send retry, two one-unit debits, insufficient balance and feed unit prices. Flutter tests cover notification layout, the under-300 boundary, safe media allowlisting, gallery preview/send separation, combo grouping and lost-ack retry without duplicate debit. GitHub Actions performs Flutter analysis/tests and native builds. No real-user gift purchase or debit was used in these tests.
