# Pulse LIVE and gift studio — build 45

The camera remains the main surface: compact creator/profile/Follow capsule,
viewer pill, real LIVE-like count and a dedicated Leave target at the top. A battle score strip appears only during an active, server-scored battle. The bottom dock keeps chat,
Send, gifts and the LIVE menu; the menu still owns moderation, guest requests,
seats, camera/mic, pause/resume, gift audio and existing battles. A pending seat
request badges the menu. Share is visible on wide phones and available in the
menu on every width. It shares the creator's name and Pulse's public site; no
unsupported app deep link is advertised.

The gift picker is a scrollable grid with All and Cinema filters, recipient
selection, wallet/recharge, free previews and a separate quantity confirmation.
Currency artwork is an original 12 px embossed gold P, also used in the shop.
Preview only opens local bundled media: it never sends an RPC that spends coins.
Real sends retain server prices, room/recipient membership, balance checks,
idempotency UUID, and the retry path. Tests do not spend money or call real users.

## Ten cinematic stories

- Pulse Dream: a rigged floating astronaut in front of an orbiting world.
- Solar Phoenix: skeletal wingbeats through a solar portal and embers.
- Dragon Flame: a 100-joint dragon flight over volcanic rocks and a bone-attached flame plume.
- Golden Sports Car: metallic coupe passing along a neon night road.
- Lion: a rigged jungle approach and head/jaw motion with the credited roar.
- Jungle Silverback: a rigged jungle approach, head and limb motion.
- Royal Lions: two lions, a crown and jungle approach.
- Pulse Stars: lion and gorilla ensemble with star fountain.
- Thunder Falcon: skeletal flight, storm forks and a blue portal.
- Pulse Universe: layered worlds, orbital rings and original extruded Pulse lettering.

These are Pulse's original stylized scenes, not downloaded TikTok gift movies
or a claim of identical film-quality fur/physics. The crown head filter, rocket
moon landing and castle king from build 43 remain available. Reduced-motion mode
uses silent still artwork; decoder failures fall back and the queue has a fixed
deadline. Gift overlays ignore touch and cannot cover the Leave target's input.
The original favicon is unchanged.

Each new movie is 6 seconds, H.264/yuv420p, 360×640 at 18 fps with AAC audio.
Bundled clips avoid runtime model downloads/rigging and limit camera/LIVE CPU
load on 4 GB devices. Playback pauses when backgrounded; gift sound can be muted.
A physical multi-device LIVE/audio/low-memory check remains necessary.

## Sources, bones and reproduction

The exact original download URLs, authors, license identifiers, byte lengths and
SHA-256 digests are in `art/gift_sources/manifest.json`. No paid generation or
paid model downloads were used. The downloaded AFK dragon/bird already have
100/55 weighted joints and named flight clips. The Innerscene lion/gorilla and
NASA astronaut were static; the renderer adds named bones, skin weights and
keyframes. The car, lettering and environment props use object animation.

Run `python scripts/fetch_gift_sources.py` to fetch the pinned sources. It refuses
changed bytes. Run Blender 4.5.3 with:

```
blender -b --threads 3 --python scripts/render_cinema_gifts.py -- dragon /tmp/render-dragon
```

Replace `dragon` with each allowed SKU. The output includes an editable `.blend`
master with armatures/keyframes and PNG frames. The large production sources are
not mobile app downloads. Then run:

```
python scripts/encode_cinema_gifts.py /tmp
```

The encoder needs ffmpeg and Pillow. `art/gift_sources/rendered.json` locks the
resulting bundled video/thumbnail bytes. CI checks those bytes, picker behavior,
large text, compact controls and additive catalogue rules.

## Licenses and audio credits

- Dragon and bird: AFK.ai's linked **animation-template downloads**, CC0-1.0,
  from `https://afk.ai/auto-rig/dragon` and `/auto-rig/bird`. These are not the
  separately credited CC BY artist samples on its rig upload page.
- Gorilla, male lion and generic grand tourer coupe: Innerscene original models,
  CC0-1.0, with per-item primary pages in the source manifest.
- Astronaut: NASA 3D Resources via Innerscene, identified as a US Government
  public-domain work. No NASA endorsement is claimed.
- Lion roar: தகவலுழவன் / Info-farmer, 4 September 2010, public-domain dedication:
  https://commons.wikimedia.org/wiki/File:Lion_raring-sound1TamilNadu178.ogg
  Trimmed to 2.5 seconds and delayed to the lion/royal-lion climax.
- Other scene audio: original deterministic synthesis in the encoder, not
  TikTok music or third-party commercial recordings.

Schema 042 adds eight gift SKUs and renames the existing `galaxy` display title
to Pulse Universe. Existing coin balances, existing prices/payouts, purchases,
withdrawal policy and gifter ranks are unchanged. New gift prices follow the
reference tiers; new rewards use the Rose's 0.05 P-coin per normal coin rate.
The existing Universe/galaxy SKU remains 2,500 coins and Lion remains 5,000;
their prices were not silently changed to the screenshot's unrelated prices.
