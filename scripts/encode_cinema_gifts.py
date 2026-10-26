"""Encode original Blender frames and synchronized original synthesis to H.264.
python scripts/encode_cinema_gifts.py /path/containing/render-SKU/
The lion keeps the credited public-domain roar from the original Pulse movie.
"""
import array,hashlib,json,math,random,subprocess,sys,wave
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[1];base=Path(sys.argv[1]);assets=Path(sys.argv[2]) if len(sys.argv)>2 else root/'assets/gifts';assets.mkdir(parents=True,exist_ok=True)
skus=['dream','phoenix','dragon','sports_car','lion','gorilla','royal_lions','pulse_stars','thunder_falcon','galaxy']
rate=24000;duration=6
for sku in skus:
 folder=base/('render-'+sku)
 if len(list(folder.glob('frame_*.png')))!=108:raise RuntimeError('Incomplete render '+sku)
 rng=random.Random(450+skus.index(sku));samples=array.array('h')
 for i in range(rate*duration):
  t=i/rate;env=min(t/.35,1)*min((duration-t)/.6,1)
  # Original wind, bass swell and rising harmonic shimmer, per-scene tuning.
  bass={'dragon':42,'gorilla':39,'lion':38,'royal_lions':45,'sports_car':60}.get(sku,72)
  n=rng.uniform(-1,1);whoosh=max(0,1-abs(t-1.5)/1.2)
  value=.13*math.sin(math.tau*(bass*t+4*t*t))+.055*math.sin(math.tau*(220*t+27*t*t))+.06*n*whoosh
  if sku in ['dragon','lion','gorilla','royal_lions']:
   roar=max(0,math.sin(min(max((t-3)/2.5,0),1)*math.pi))
   value+=roar*(.17*math.sin(math.tau*52*t)*(1+.5*math.sin(math.tau*19*t))+.06*n)
  if sku=='thunder_falcon':value+=n*.22*max(0,1-abs(t-3.3)/.18)
  if sku=='sports_car':value+=.08*math.sin(math.tau*(38*t+18*t*t))
  samples.append(int(max(-.85,min(.85,value*env))*32767))
 audio=base/(sku+'.wav')
 with wave.open(str(audio),'w') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes(samples.tobytes())
 dest=assets/('cinema_'+sku+'.mp4')
 cmd=['ffmpeg','-y','-hide_banner','-loglevel','error','-framerate','18','-i',str(folder/'frame_%04d.png'),'-i',str(audio)]
 if sku in ['lion','royal_lions']:
  cmd+=['-i',str(root/'art/gift_sources/lion-roar.ogg'),'-filter_complex','[2:a]atrim=start=0:duration=2.5,asetpts=PTS-STARTPTS,volume=0.65,adelay=3200|3200[roar];[1:a][roar]amix=inputs=2:normalize=0,alimiter=limit=0.89[audio]','-map','0:v:0','-map','[audio]']
 cmd+=['-c:v','libx264','-preset','medium','-crf','24','-pix_fmt','yuv420p','-c:a','aac','-b:a','64k','-movflags','+faststart','-t','6',str(dest)]
 subprocess.run(cmd,check=True)

 # Square, offline thumbnails make the gallery recognizable without a decoder.
 im=Image.open(folder/'frame_0076.png');w,h=im.size;im.crop((0,(h-w)//2,w,(h+w)//2)).resize((192,192),Image.Resampling.LANCZOS).save(assets/('thumb_'+sku+'.png'),optimize=True)
 print(sku,dest.stat().st_size,flush=True)
manifest=[]
for sku in skus:
 for prefix,ext in [('cinema_','.mp4'),('thumb_','.png')]:
  p=assets/(prefix+sku+ext);manifest.append({'path':'assets/gifts/'+p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
metadata=(assets/'rendered.json') if len(sys.argv)>2 else root/'art/gift_sources/rendered.json'
metadata.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
