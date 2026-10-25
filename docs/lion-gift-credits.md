# Pulse jungle lion gift

The lion model, jungle, lighting, animation and footfall/wind bed were authored for Pulse. This is an original stylized 3D cinematic, not a TikTok asset. It runs through the jungle, settles, opens its jaw and roars. Rendering to bundled H.264 keeps the LIVE camera free from a real-time 3D engine.

Scene source: `scripts/render_lion_gift.py` (Blender 4.5 LTS, Cycles CPU). 432 × 768, 24 fps, 168 frames. Run the script with an output directory; append `preview` for frame 112. The output frames are encoded to `assets/gifts/lion_jungle.mp4`. Preserve 7 seconds of presentation when encoding. Use `scripts/encode_lion_gift.py <frames-dir> <source-roar.ogg> <output.mp4>` to rebuild the audio bed and final clip with ffmpeg.

Roar source: [Lion raring-sound1TamilNadu178.ogg](https://commons.wikimedia.org/wiki/File:Lion_raring-sound1TamilNadu178.ogg), own recording by தகவலுழவன் (Info-farmer), 2010, dedicated to the public domain on the source page. Original download: https://upload.wikimedia.org/wikipedia/commons/7/7d/Lion_raring-sound1TamilNadu178.ogg. The first 2.5 seconds are trimmed, faded and delayed to 3.5 seconds, then mixed quietly with the original footfall/wind bed. No music is used.

The LIVE menu can mute gift sounds. Reduced-motion mode uses the existing silent mesh presentation. Decoder failure falls back to that mesh, and an independent deadline releases the gift queue after ten seconds. Gifts ignore pointer input and remain below the persistent LIVE exit/menu controls.
