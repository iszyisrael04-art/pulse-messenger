"""Encode the original Blender frames and credited public-domain roar.
Usage: python scripts/encode_lion_gift.py <frames-dir> <source-roar.ogg> <output.mp4>
Requires Python stdlib and ffmpeg. See docs/lion-gift-credits.md.
"""
import array
import math
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import wave

frames, roar, destination = map(Path, sys.argv[1:4])
rng = random.Random(23)
sample_rate = 24000
samples = array.array('h')
for i in range(sample_rate * 7):
    t = i / sample_rate
    wind = rng.gauss(0, .002)
    stride = (t - .15) % .21
    footfall = 0
    if .15 <= t < 3.2 and stride < .13:
        footfall = math.exp(-stride * 38) * (
            .06 * math.sin(2 * math.pi * 72 * stride) + rng.gauss(0, .014))
    samples.append(round(max(-1, min(1, wind + footfall)) * 32767))
if sys.byteorder != 'little':
    samples.byteswap()
with tempfile.TemporaryDirectory() as work:
    bed = Path(work) / 'footfalls.wav'
    with wave.open(str(bed), 'wb') as out:
        out.setparams((1, 2, sample_rate, 0, 'NONE', 'not compressed'))
        out.writeframes(samples.tobytes())
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        'ffmpeg', '-y', '-v', 'warning', '-framerate', '24',
        '-i', str(frames / 'frame_%04d.png'), '-i', str(roar),
        '-i', str(bed), '-filter_complex',
        '[1:a]atrim=0:2.5,asetpts=PTS-STARTPTS,afade=t=in:d=0.12,'
        'afade=t=out:st=2:d=0.5,volume=0.7,adelay=3500:all=1[roar];'
        '[roar][2:a]amix=inputs=2:normalize=0,alimiter=limit=0.85[a]',
        '-map', '0:v:0', '-map', '[a]', '-t', '7',
        '-c:v', 'libx264', '-preset', 'slow', '-crf', '25',
        '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-ac', '1', '-b:a', '64k',
        '-movflags', '+faststart', str(destination),
    ], check=True)
