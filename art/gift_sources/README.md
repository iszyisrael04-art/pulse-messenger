# Licensed production inputs

`manifest.json` pins each source asset's author, per-item license page, download,
size and SHA-256 digest. Run `python scripts/fetch_gift_sources.py` from the repo
root before art production. The downloader refuses altered source bytes.

Raw GLBs and Blender masters are production inputs, not app assets. The mobile
app uses the ten movies and ten square thumbnails locked by `rendered.json`.
The full renderer, bone/skin/keyframe authoring and original sound synthesis are
in `scripts/render_cinema_gifts.py` and `scripts/encode_cinema_gifts.py`.
See `docs/live-gift-studio-45.md` for reproduction and credits.
