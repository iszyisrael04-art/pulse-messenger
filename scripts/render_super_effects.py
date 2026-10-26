"""Original Pulse abstract cinematic effects. No third-party models or samples.

Usage: python scripts/render_super_effects.py --output /tmp/pulse-effects
Requires numpy, Pillow and ffmpeg. Reproducible seeds; outputs are first written
to staging, then installed only after ffprobe/hash validation by the caller.
"""
import argparse, concurrent.futures, hashlib, json, math, pathlib, subprocess, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

W,H,FPS,SECONDS=480,854,24,6
TAU=math.tau
SPECS=[
 ('voltage_dominion','VOLTAGE DOMINION',(38,168,255),(181,80,255),29999),
 ('void_rift','VOID RIFT',(157,63,255),(33,231,249),34999),
 ('solar_overdrive','SOLAR OVERDRIVE',(255,144,28),(255,48,99),39999),
 ('quantum_cathedral','QUANTUM CATHEDRAL',(107,107,255),(255,70,207),49999),
 ('prism_avalanche','PRISM AVALANCHE',(33,241,225),(249,107,204),59999),
 ('aurora_ascension','AURORA ASCENSION',(42,240,169),(62,132,255),69999),
 ('gravity_collapse','GRAVITY COLLAPSE',(255,158,54),(186,57,255),79999),
 ('pulse_supernova','PULSE SUPERNOVA',(83,246,231),(255,190,66),99999),
]
Y,X=np.mgrid[0:H,0:W].astype(np.float32)
NX=(X-W/2)/W; NY=(Y-H*.47)/W
R=np.sqrt(NX*NX+NY*NY); A=np.arctan2(NY,NX)
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BOLD='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

def project(points,t,tilt=.5,scale=1):
 p=np.asarray(points,dtype=float).copy()
 c,s=math.cos(t),math.sin(t)
 p[:,[0,2]]=p[:,[0,2]]@np.array([[c,-s],[s,c]])
 c,s=math.cos(tilt),math.sin(tilt)
 p[:,[1,2]]=p[:,[1,2]]@np.array([[c,-s],[s,c]])
 z=3.8+p[:,2]; f=W*.91*scale/z
 return np.c_[W/2+p[:,0]*f,H*.47+p[:,1]*f,z]

def ring(draw,t,radius,col,tilt=.6,axis=0,width=2,scale=1):
 a=np.linspace(0,TAU,180)
 p=np.c_[radius*np.cos(a),radius*np.sin(a),np.zeros_like(a)]
 if axis:p[:,[1,2]]=p[:,[2,1]]
 q=project(p,t,tilt,scale)
 for i in range(len(q)-1):
  z=q[i,2]; color=tuple(int(v*(.4+.6*min(1,3/z))) for v in col)
  draw.line([tuple(q[i,:2]),tuple(q[i+1,:2])],fill=color,width=width)
 return q

def lightning(draw,start,end,t,seed,color,width=2,branches=True):
 # Smooth electric filaments, rather than unrelated random flashes per frame.
 rng=np.random.default_rng(seed)
 s,e=np.array(start),np.array(end); vec=e-s; length=np.linalg.norm(vec)
 perp=np.array([-vec[1],vec[0]])/(length+1e-9)
 n=42;u=np.linspace(0,1,n);d=np.zeros(n)
 for frequency in [3,7,13,23]:
  d+=np.sin(u*frequency*TAU+rng.uniform(0,TAU)+t*(2+frequency*.1))*length/(frequency*2)
 d*=np.sin(u*math.pi)
 p=s[None,:]+u[:,None]*vec[None,:]+d[:,None]*perp[None,:]
 pts=[tuple(x) for x in p]
 draw.line(pts,fill=color,width=width+2,joint='curve')
 draw.line(pts,fill=(220,243,255),width=width,joint='curve')
 if branches:
  for i in [12,24,31]:
   side=1 if i%2 else -1
   tip=p[i]+vec*.12+perp*length*.18*side
   draw.line([tuple(p[i]),tuple(p[i]+perp*length*.07*side),tuple(tip)],fill=color,width=1)

def audio(path,index):
 sr=44100;t=np.arange(sr*SECONDS,dtype=np.float64)/sr
 rng=np.random.default_rng(510+index);noise=rng.standard_normal(len(t))
 low=np.sin(TAU*(42*t+6*np.sin(t*.8)))+.4*np.sin(TAU*81*t)
 sweep=np.sin(TAU*(100*t+340*np.power(t/SECONDS,2)*t))
 charge=np.sin(math.pi*np.minimum(t/2,1))**2*np.exp(-np.maximum(t-2,0)*1.4)
 air=np.convolve(noise,np.ones(5)/5,mode='same')
 envelope=np.sin(np.minimum(t/.6,1)*math.pi/2)*np.minimum((SECONDS-t)/.8,1)
 impact=np.exp(-np.maximum(t-2.1,0)*2.3)*(t>2.1)
 signal=(.09*low+.045*sweep*charge+.13*air*impact+.025*air)*envelope
 if index==0:signal+=.035*noise*(np.sin(t*TAU*2)*.5+.5)**10*envelope
 # Original synthesized stereo movement, conservatively below full scale.
 stereo=np.c_[signal*(.8+.2*np.sin(t)),signal*(.8-.2*np.sin(t))]
 with wave.open(str(path),'wb') as f:
  f.setnchannels(2);f.setsampwidth(2);f.setframerate(sr)
  f.writeframes((np.clip(stereo,-.75,.75)*32767).astype('<i2').tobytes())

def frame(index,t,poster=False):
 sku,title,c1,c2,_=SPECS[index]
 progress=min(t/2.2,1); energy=.3+.7*math.sin(progress*math.pi/2)
 outro=min(1,max(0,(SECONDS-t)/.75)); fade=min(1,t/.5)*outro
 # Wide luminous ribbons and fog with nonlinear HDR-style colour grading.
 field=(.035+.065*np.exp(-R*2))
 fog=np.exp(-((NX-.13*np.sin(NY*4+t*.4))**2*9+NY**2*1.2))*.15
 texture=(np.sin(NX*8+NY*12+t*.4)+np.sin(NX*19-NY*7-t*.3))*.015
 rgb=np.zeros((H,W,3),dtype=np.float32)
 for ch in range(3):rgb[:,:,ch]=(field+fog+texture)*c1[ch]*.55
 drawLayer=Image.new('RGB',(W,H));d=ImageDraw.Draw(drawLayer)
 rng=np.random.default_rng(700+index);stars=rng.uniform(-1,1,(180,3))
 # Perspective dust: depth and speed change at the energy release.
 for x,y,z in stars:
  depth=(z+t*.07+1)%2+.5
  px=W/2+x*W/depth;py=H*.47+y*H/depth
  radius=max(1,2.5/depth);brightness=int(90/depth)
  d.ellipse((px-radius,py-radius,px+radius,py+radius),fill=tuple(min(255,int(v*.25)+brightness) for v in c1))
 if index==0:
  core=np.exp(-((R-.16-.008*np.sin(A*9+t*3))/.022)**2)*energy
  for k in range(8):
   angle=k*TAU/8+t*.05;end=(W/2+math.cos(angle)*75,H*.47+math.sin(angle)*75)
   start=(W/2+math.cos(angle)*480,H*.47+math.sin(angle)*650)
   lightning(d,start,end,t,10+k,c1,2)
  for j in range(3):ring(d,t*.6+j,1.15+j*.28,c2,.5+j*.45,axis=j%2,width=2)
  for j in range(4):
   rr=((t*.25+j*.23)%1)*310
   d.arc((W/2-rr,H*.47-rr,W/2+rr,H*.47+rr),t*40+j*80,t*40+j*80+65,fill=c1,width=2)
 elif index==1:
  slit=.025+.04*progress+.018*np.sin(NY*10+t*2)
  core=np.exp(-((np.abs(NX)-slit)/.012)**2)*np.exp(-NY**4*3)
  for side in [-1,1]:
   pts=[(W/2+side*(30+12*math.sin(y*.016+t*2)),y) for y in range(50,H-90,5)]
   d.line(pts,fill=c1,width=4)
   lightning(d,(W/2+side*30,100),(W/2+side*40,H-130),t,80+side,c2,2)
  # Floating solid shards tumbling into the opening.
  for j in range(35):
   a=j*2.399+t*.24;r=170*(1-((t*.15+j*.071)%1))
   x=W/2+math.cos(a)*r;y=H*.47+math.sin(a)*r*2;s=3+8*((j*.37)%1)
   d.polygon([(x-s,y-s*2),(x+s,y),(x-s*.5,y+s*2)],fill=c2 if j%3 else c1)
 elif index==2:
  rad=.11+.025*math.sin(t*.7)
  core=np.exp(-((R-rad)/.018)**2)*1.1+np.exp(-R*R/.007)*.7
  rays=np.maximum(0,np.sin(A*17+t*.3)+.5*np.sin(A*31-t))**6
  core+=rays*np.exp(-np.abs(R-rad)*13)*.17*energy
  for j in range(12):
   a=j*TAU/12+t*.1;r=90+20*math.sin(t+j)
   pts=[]
   for u in np.linspace(0,math.pi,40):pts.append((W/2+math.cos(a+u*.35)*r*(1+.6*math.sin(u)),H*.47+math.sin(a+u*.35)*r*(1+.6*math.sin(u))))
   d.line(pts,fill=c1,width=2)
  for j in range(4):ring(d,t*.17+j,.9+j*.38,c2,1.2,width=1)
 elif index==3:
  core=np.exp(-((np.abs(NX)+np.abs(NY)-.25)/.013)**2)*.3
  vertices=np.array([[1,0,0],[-1,0,0],[0,1.6,0],[0,-1.6,0],[0,0,1],[0,0,-1]])
  for layer in range(3):
   q=project(vertices*(.9+layer*.5),t*.5+layer*.4,t*.16+.3)
   for a in range(6):
    for b in range(a+1,6):
     if (a//2)!=(b//2):d.line([tuple(q[a,:2]),tuple(q[b,:2])],fill=c1 if layer%2 else c2,width=2)
   for x,y,z in q:d.ellipse((x-4,y-4,x+4,y+4),fill=(232,220,255))
  ring(d,t*.5,2,c1,1.3,width=2)
  for side in [-1,1]:
   d.line([(W/2+side*190,90),(W/2+side*110,H*.47),(W/2+side*190,H-90)],fill=c1,width=2)
 elif index==4:
  core=np.exp(-((R-.14)/.022)**2)*.5
  for j in range(70):
   a=j*2.399+t*.3;z=((j*.174-t*.18)%1)*3+.7
   x=math.cos(a)*1.35;y=math.sin(a)*1.8
   q=project([[x,y,z-1],[x+.18,y+.04,z-1],[x+.07,y+.5,z-.8]],t*.13,.2,1.6)
   color=tuple(int(v) for v in (np.array(c1)*(math.sin(j*.7)*.5+.5)+np.array(c2)*(1-(math.sin(j*.7)*.5+.5))))
   d.polygon([tuple(p[:2]) for p in q],fill=tuple(int(v*.35) for v in color),outline=color,width=2)
  for j in range(5):ring(d,t*.3+j*.6,.7+j*.25,c1 if j%2 else c2,1.05,width=1)
 elif index==5:
  curtains=np.exp(-((NX-.2*np.sin(NY*5+t*.7))/.035)**2)
  core=curtains*np.exp(-NY*NY*.4)*.3
  for j in range(14):
   pts=[]
   for y in range(40,H-70,4):
    x=W/2+math.sin(y*.008+t*.8+j*.09)*(80+j*4)+math.sin(y*.017-t*.3)*25
    pts.append((x,y))
   col=tuple(int(c1[k]*(1-j/18)+c2[k]*(j/18)) for k in range(3))
   d.line(pts,fill=col,width=2 if j%3 else 4)
  for j in range(5):ring(d,t*.2+j*.4,.8+j*.18,c2,1.35,width=1)
 elif index==6:
  rr=np.sqrt(NX**2+(NY*3.1)**2)
  core=np.exp(-((rr-.22)/.015)**2)*.9+np.exp(-((R-.14)/.012)**2)*.4
  for j in range(9):
   pts=[]
   for u in np.linspace(0,TAU*2,160):
    radius=(.6+u*.22+j*.045);ang=u+t*(.4+j*.015)
    q=project([[math.cos(ang)*radius,math.sin(ang)*radius,0]],0,1.23)[0]
    pts.append(tuple(q[:2]))
   d.line(pts,fill=tuple(int(v*(.3+j*.07)) for v in c1),width=1)
  # Opaque central shadow occludes rear dust, keeping a convincing horizon.
  d.ellipse((W/2-61,H*.47-61,W/2+61,H*.47+61),fill=(1,2,8),outline=c2,width=2)
 else:
  r=.05+min(t/2.3,1)*.1
  core=np.exp(-R*R/(r*r))*.8
  for j in range(8):
   age=max(0,t-1.6-j*.18);rr=age*120
   if rr>0:d.ellipse((W/2-rr,H*.47-rr,W/2+rr,H*.47+rr),outline=c1 if j%2 else c2,width=max(1,5-j//2))
  for j in range(36):
   a=j*TAU/36+t*.06;inner=35+15*math.sin(t*2+j);outer=100+90*progress+20*math.sin(j)
   d.line([(W/2+math.cos(a)*inner,H*.47+math.sin(a)*inner),(W/2+math.cos(a)*outer,H*.47+math.sin(a)*outer)],fill=c1 if j%3 else c2,width=2)
  for j in range(3):ring(d,t*.3+j,1.1+j*.35,c2,.6+j*.4,width=2)
 # Multi-pass bloom, soft atmosphere, filmic shoulder, vignette and fine grain.
 for ch in range(3):rgb[:,:,ch]+=np.clip(core,0,2)*c1[ch]*.7
 base=Image.fromarray(np.uint8(np.clip(rgb,0,255)))
 if index==6:
  bd=ImageDraw.Draw(base);bd.ellipse((W/2-57,H*.47-57,W/2+57,H*.47+57),fill=(0,1,5))
 glow=ImageChops.add(drawLayer.filter(ImageFilter.GaussianBlur(13)),drawLayer.filter(ImageFilter.GaussianBlur(4)),scale=1)
 result=ImageChops.add(base,glow,scale=1)
 result=ImageChops.add(result,drawLayer,scale=1)
 # Deliberate edge colour separation; no full-frame strobing.
 red,green,blue=result.split();result=Image.merge('RGB',(ImageChops.offset(red,1,0),green,ImageChops.offset(blue,-1,0)))
 arr=np.array(result,dtype=np.float32)/255
 arr=np.power(arr,.9);vignette=np.clip(1-R*.38,.25,1)
 arr*=vignette[:,:,None]*fade
 result=Image.fromarray(np.uint8(np.clip(arr*255,0,255)))
 if not poster:
  d=ImageDraw.Draw(result)
  small=ImageFont.truetype(FONT,11);big=ImageFont.truetype(BOLD,18)
  d.text((W/2,H-104),'P U L S E   /   S U P E R   E F F E C T',font=small,anchor='mm',fill=tuple(int(v*fade) for v in (150,191,182)))
  d.text((W/2,H-76),title,font=big,anchor='mm',fill=tuple(int(v*fade) for v in (225,245,239)))
 return result

def render(index,out):
 sku,title,c1,c2,coins=SPECS[index];wav=out/(sku+'.wav');audio(wav,index)
 path=out/('cinema_'+sku+'.mp4')
 p=subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','pipe:0','-i',str(wav),'-c:v','libx264','-threads','2','-preset','medium','-crf','24','-maxrate','1100k','-bufsize','1600k','-pix_fmt','yuv420p','-c:a','aac','-b:a','80k','-movflags','+faststart','-shortest',str(path)],stdin=subprocess.PIPE)
 try:
  for f in range(FPS*SECONDS):p.stdin.write(frame(index,f/FPS).tobytes())
 finally:p.stdin.close()
 if p.wait()!=0:raise RuntimeError(sku+' encoder failed')
 still=frame(index,3.25,poster=True)
 # Square thumbnail includes the effect centre, rather than the small caption.
 still.crop((0,int(H*.47-W/2),W,int(H*.47+W/2))).resize((192,192),Image.Resampling.LANCZOS).save(out/('thumb_'+sku+'.png'))
 wav.unlink()
 probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
 video=next(s for s in probe['streams'] if s['codec_type']=='video');assert (video['width'],video['height'])==(W,H)
 assert int(video['nb_frames'])==FPS*SECONDS and any(s['codec_type']=='audio' for s in probe['streams'])
 print(sku,path.stat().st_size,flush=True)
 return {'sku':sku,'title':title.title(),'coins':coins,'duration':SECONDS,'fps':FPS,'frames':FPS*SECONDS,'width':W,'height':H}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',type=pathlib.Path,required=True);args=ap.parse_args();args.output.mkdir(parents=True,exist_ok=True)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:rows=list(ex.map(lambda i:render(i,args.output),range(len(SPECS))))
 files=[]
 for row in rows:
  for prefix,ext in [('cinema_','.mp4'),('thumb_','.png')]:
   p=args.output/(prefix+row['sku']+ext);b=p.read_bytes();files.append({'path':'assets/gifts/'+p.name,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
 receipt={'author':'Pulse','license':'Original Pulse procedural artwork and synthesized audio','generator':'scripts/render_super_effects.py','seed_base':700,'effects':rows,'files':files}
 (args.output/'effects.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
