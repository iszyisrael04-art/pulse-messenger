"""Size-bound the alpha-video fallback for low-end phones without trimming time.
Run after prepare_legendary_gifts.py. No whole-frame opacity reduction is applied.
"""
from pathlib import Path
from PIL import Image,ImageSequence
import json,hashlib,numpy as np
ROOT=Path(__file__).resolve().parents[1]
def optimize(sku):
 receipt=ROOT/'art/gift_sources/legendary.json';data=json.loads(receipt.read_text())
 gift=next(g for g in data['gifts'] if g['sku']==sku);path=ROOT/'assets/gifts'/f'{sku}.webp'
 frames=[];raw_durations=[];duration=gift['duration_ms']
 with Image.open(path) as im:
  for i in range(im.n_frames):
   im.seek(i);im.load();delay=im.info.get('duration',0)
   if delay<=0:continue
   rgba=im.convert('RGBA');rgba.thumbnail((480,480),Image.Resampling.LANCZOS)
   a=np.asarray(rgba.getchannel('A')).astype(np.float32)
   a=np.clip(np.rint(a/4)*4,0,255).astype('uint8');a[0,:]=0;a[-1,:]=0;a[:,0]=0;a[:,-1]=0
   rgba.putalpha(Image.fromarray(a));frames.append(rgba);raw_durations.append(delay)
 assert frames
 total=sum(raw_durations);elapsed=0;durations=[]
 for delay in raw_durations:
  before=round(elapsed*duration/total);elapsed+=delay;durations.append(round(elapsed*duration/total)-before)
 tmp=Path('/tmp/legend-ready');tmp.mkdir(exist_ok=True);target=tmp/path.name
 frames[0].save(target,save_all=True,append_images=frames[1:],duration=durations,loop=1,quality=76,method=4,lossless=False,allow_mixed=False)
 print(sku,path.stat().st_size,'->',target.stat().st_size,flush=True)
 return target
if __name__=='__main__':
 import sys
 names=sys.argv[1:] or [g['sku'] for g in json.loads((ROOT/'art/gift_sources/legendary.json').read_text())['gifts']]
 for sku in names:optimize(sku)
