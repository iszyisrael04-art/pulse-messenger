"""Compose original generated fantasy artwork with animated spell VFX.

Characters are 2D cinematic artwork, not skeletal 3D rigs. Wearable hats are
transparent textures for the app's existing on-device head tracking.
Usage: python scripts/render_magic_gifts.py --output /tmp/pulse-magic
"""
import argparse, hashlib, json, math, pathlib, subprocess
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops,ImageFont
from render_super_effects import audio
ROOT=pathlib.Path(__file__).resolve().parents[1]
W,H,FPS,DURATION=480,854,24,6
SPECS=[('archmage','The Archmage','wizard_scene',79999),('moon_witch','Moonlight Witch','witch_scene',84999),('wizard_filter','Wizard Head Filter','wizard_hat',15999),('witch_filter','Witch Head Filter','witch_hat',18999)]

def render(index,out):
 sku,title,source,coins=SPECS[index];hat=index>=2
 src=Image.open(ROOT/'art/magic'/f'{source}.webp').convert('RGBA')
 wav=out/(sku+'.wav');audio(wav,index+12)
 video=out/('cinema_'+sku+'.mp4')
 ff=subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','pipe:0','-i',str(wav),'-c:v','libx264','-threads','2','-crf','24','-maxrate','950k','-bufsize','1400k','-pix_fmt','yuv420p','-c:a','aac','-b:a','80k','-movflags','+faststart','-shortest',str(video)],stdin=subprocess.PIPE)
 rng=np.random.default_rng(942+index);particles=rng.random((110,4))
 tone=(70,172,255)if index%2==0 else(192,103,255)
 YY,XX=np.mgrid[:H,:W];font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',16)
 for frame in range(FPS*DURATION):
  t=frame/FPS;fade=min(1,t/.45,(DURATION-t)/.65)
  layer=Image.new('RGB',(W,H));draw=ImageDraw.Draw(layer)
  if hat:
   base=Image.new('RGBA',(W,H),(8,12,22,255))
   width=430;size=src.resize((width,width),Image.Resampling.LANCZOS)
   base.alpha_composite(size,((W-width)//2,int(H*.23+6*math.sin(t*1.3))))
   focus=(W*.5,H*.52)
  else:
   scale=1.02+.045*t/DURATION;wi,hi=round(W*scale),round(H*scale)
   view=src.resize((wi,hi),Image.Resampling.LANCZOS)
   x=(wi-W)//2+round(2*math.sin(t*.7));y=(hi-H)//2
   base=view.crop((x,y,x+W,y+H));focus=(W*.27,H*(.20 if index==0 else .27))
  fx,fy=focus
  # Multiple moving wisps and orbiting motes emanate from the spell's source.
  for k in range(7):
   points=[]
   for j in range(80):
    u=j/79;ang=u*math.tau*1.7+t*(.7+k*.08)+k*.8
    radius=(20+u*72)*(1+.1*math.sin(t))
    points.append((fx+math.cos(ang)*radius,fy+math.sin(ang)*radius*.55-u*30))
   draw.line(points,fill=tuple(int(c*(.4+k*.08))for c in tone),width=1+k%2)
  for px,py,speed,size in particles:
   x=px*W+math.sin(t*.6+py*15)*18
   y=(py*H-t*(14+speed*34))%H
   r=1+size*1.7;b=.35+.6*(math.sin(t*1.4+px*12)*.5+.5)
   draw.ellipse((x-r,y-r,x+r,y+r),fill=tuple(int(c*b)for c in tone))
  if not hat:
   # Animated floor sigil and free-moving atmospheric ribbons.
   cx,cy=W*.5,H*.78
   for ring in range(3):
    radius=80+ring*18
    draw.ellipse((cx-radius,cy-radius*.15,cx+radius,cy+radius*.15),outline=tone,width=1)
   for k in range(16):
    a=k*math.tau/16+t*.28
    x=cx+math.cos(a)*104;y=cy+math.sin(a)*17
    draw.line([(x,y-2),(x+4*math.cos(a),y+2)],fill=tone,width=2)
  glow=layer.filter(ImageFilter.GaussianBlur(7))
  final=ImageChops.add(base.convert('RGB'),glow,scale=1)
  final=ImageChops.add(final,layer,scale=1)
  arr=np.asarray(final,dtype=np.float32)
  # Low-frequency, drifting translucent mist retains the character's detail.
  mist=np.maximum(0,np.sin(XX*.013+YY*.009-t*.6)+np.sin(YY*.021+t*.35)-1.1)
  mist*=np.clip((YY/H-.55)*2,0,.65)
  arr+=mist[:,:,None]*np.array(tone)[None,None,:]*.14
  final=Image.fromarray(np.uint8(np.clip(arr*fade,0,255)))
  d=ImageDraw.Draw(final)
  d.text((W/2,H-42),title,font=font,anchor='mm',fill=(216,227,242))
  if hat:d.text((W/2,H-68),'LIVE HEAD FILTER · ARTWORK PREVIEW',font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',10),anchor='mm',fill=(150,172,200))
  if frame==72:
   if hat:
    thumb=src.resize((192,192),Image.Resampling.LANCZOS)
   else:
    thumb=final.crop((0,80,W,80+W)).resize((192,192),Image.Resampling.LANCZOS)
   thumb.save(out/('thumb_'+sku+'.png'))
  ff.stdin.write(final.tobytes())
 ff.stdin.close();assert ff.wait()==0;wav.unlink()
 probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-of','json',str(video)]))
 v=next(x for x in probe['streams']if x['codec_type']=='video');assert int(v['nb_frames'])==144
 assert any(x['codec_type']=='audio'for x in probe['streams'])
 print(sku,video.stat().st_size,flush=True)
 return {'sku':sku,'title':title,'coins':coins,'type':'head_filter'if hat else'cinematic_scene','frames':144,'fps':24,'width':W,'height':H,'duration':6}

def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
 effects=[render(i,a.output)for i in range(4)]
 files=[]
 for e in effects:
  for prefix,ext in [('cinema_','.mp4'),('thumb_','.png')]:
   f=a.output/(prefix+e['sku']+ext);b=f.read_bytes();files.append({'path':'assets/gifts/'+f.name,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
 (a.output/'magic.json').write_text(json.dumps({'generator':'scripts/render_magic_gifts.py','effects':effects,'files':files},indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
