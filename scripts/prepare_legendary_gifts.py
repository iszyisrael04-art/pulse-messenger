"""Prepare user-supplied MP4s as portable straight-alpha WebP animations + audio.
Offline only: foreground inference runs here, never on viewers' devices.
Usage: PYTHONPATH=/tmp/pulse-matting-deps python scripts/prepare_legendary_gifts.py --input-dir /tmp/pulse-legendary --model /tmp/pulse-legendary/u2netp.onnx
"""
import argparse,hashlib,io,json,math,pathlib,subprocess,sys
import numpy as np
from PIL import Image,ImageFilter
ROOT=pathlib.Path(__file__).resolve().parents[1]
MODEL_SHA='309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8'
GIFTS=[
 ('legend_lion_king','Lion King',1000,'ffd1aaaa-2219-4062-9511-b4559f92ac79.mp4','subject'),
 ('legend_phoenix','Phoenix',5000,'ca47c3ab-9646-4fba-b558-779d09c4db7e.mp4','subject'),
 ('legend_thunder_god','Thunder God',7500,'6e9adf0d-2201-4cb1-a781-3f56015ed321.mp4','subject'),
 ('legend_phantom_supercar','Phantom Supercar',10000,'9e19526c-3c29-4dbb-b335-a6c8c1ce42de.mp4','car'),
 ('legend_cosmic_rocket','Cosmic Rocket',15000,'6dc23c0f-1fa5-422a-85f8-fd0b828d3405.mp4','luma'),
 ('legend_royal_palace','Royal Palace',20000,'1471b828-18ad-40c4-80c0-2577f3d6627b.mp4','palace'),
 ('legend_galaxy_dragon','Galaxy Dragon',30000,'e64ea1cc-aef8-4569-b411-0b381411119e.mp4','subject'),
 ('legend_pulse_legend','Pulse Legend',50000,'f68f190e-2153-4422-a892-1f6fe8b5c77c.mp4','gold'),
 ('legend_pulse_universe','Pulse Universe',60000,'949c1282-f0e9-4345-8b5b-a13b25a715ea.mp4','space'),
]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def smooth(x):x=np.clip(x,0,1);return x*x*(3-2*x)
def foreground(im,session,mode):
 a=np.asarray(im).astype(np.float32)/255;h,w=a.shape[:2]
 yy,xx=np.mgrid[0:h,0:w]
 edge=smooth(np.minimum.reduce([xx/(w*.11),(w-1-xx)/(w*.11),yy/(h*.12),(h-1-yy)/(h*.12)]))
 mx=a.max(2)
 if mode=='luma':return np.clip((mx-.045)/.52,0,1)**.65*edge
 x=np.asarray(im.resize((320,320))).astype(np.float32);x/=max(float(x.max()),1)
 x=((x-[.485,.456,.406])/[.229,.224,.225]).transpose(2,0,1)[None].astype(np.float32)
 m=session.run(None,{session.get_inputs()[0].name:x})[0][0,0];m=(m-m.min())/max(float(m.max()-m.min()),1e-6)
 m=np.asarray(Image.fromarray((m*255).astype('uint8')).resize((w,h),Image.Resampling.BILINEAR).filter(ImageFilter.GaussianBlur(.8))).astype(np.float32)/255
 fg=smooth((m-.12)/.58)
 broad=np.asarray(Image.fromarray((fg*255).astype('uint8')).filter(ImageFilter.GaussianBlur(22*w/480))).astype(np.float32)/255
 glow=np.clip((mx-.16)/.6,0,1)**1.3
 alpha=np.maximum(fg,glow*np.clip(broad*2.2,0,1)*.8)*edge
 if mode=='space':alpha=np.maximum(fg,glow*.92)*edge
 if mode=='car':
  red=(a[:,:,0]>a[:,:,1]*1.35)&(a[:,:,0]>a[:,:,2]*1.25)&(a[:,:,0]>.18)&(yy>h*.22)
  ry,rx=np.where(red)
  if len(rx)>15:
   x0,x1=np.quantile(rx,[.03,.97]);y0,y1=np.quantile(ry,[.03,.97])
   rad=((xx-(x0+x1)/2)/max((x1-x0)*.7,w*.12))**2+((yy-(y0+y1)/2-h*.055)/max((y1-y0)*.9,h*.13))**2
   alpha=np.maximum(alpha,np.clip((1.3-rad)/.5,0,1)*edge)
 if mode in ('gold','palace'):
  gold=np.clip((a[:,:,0]-.25)/.4,0,1)*np.clip((a[:,:,0]+a[:,:,1]-2*a[:,:,2]-.1)/.45,0,1)
  alpha=np.maximum(alpha,gold*edge)
 if mode=='palace':
  rad=((xx-w*.5)/(w*.24))**2+((yy-h*.55)/(h*.43))**2
  alpha=np.maximum(alpha,np.clip((1.2-rad)/.5,0,1)*edge)
 return alpha

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--input-dir',type=pathlib.Path,required=True);ap.add_argument('--model',type=pathlib.Path,required=True);ap.add_argument('--only');args=ap.parse_args()
 assert sha(args.model)==MODEL_SHA,'Unreviewed matting model'
 import onnxruntime as ort
 opts=ort.SessionOptions();opts.intra_op_num_threads=2;opts.inter_op_num_threads=1
 session=ort.InferenceSession(str(args.model),opts,providers=['CPUExecutionProvider'])
 out=ROOT/'assets/gifts';out.mkdir(exist_ok=True)
 receipt=ROOT/'art/gift_sources/legendary.json'
 old=json.loads(receipt.read_text()) if receipt.exists() else {'gifts':[],'files':[]}
 gifts={r['sku']:r for r in old['gifts']};files={r['path']:r for r in old['files']}
 for sku,title,coins,filename,mode in GIFTS:
  if args.only and args.only!=sku:continue
  src=args.input_dir/filename
  meta=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-show_streams','-of','json',str(src)]))
  duration_ms=round(float(meta['format']['duration'])*1000)
  v=next(s for s in meta['streams'] if s['codec_type']=='video');w=640;h=round(v['height']/v['width']*w/2)*2
  # Corrupt generated packets are reported. Retain the source timeline, holding recoverable frames if needed.
  decoded=subprocess.run(['ffmpeg','-v','warning','-err_detect','ignore_err','-i',str(src),'-vf',f'scale={w}:{h},fps=24','-f','rawvideo','-pix_fmt','rgb24','-'],capture_output=True,check=True)
  raw=decoded.stdout;count=len(raw)//(w*h*3);target=max(1,round(duration_ms*24/1000));frames=[];durations=[]
  assert count>0,'No decodable frames'
  for index in range(target):
   j=min(index,count-1);rgb=Image.frombytes('RGB',(w,h),raw[j*w*h*3:(j+1)*w*h*3]);a=foreground(rgb,session,mode)
   if frames:
    prev=np.asarray(frames[-1].getchannel('A')).astype(np.float32)/255
    a=np.where(np.abs(a-prev)<.12,a*.85+prev*.15,a)
   rgba=rgb.convert('RGBA');rgba.putalpha(Image.fromarray((a*255).astype('uint8')))
   frames.append(rgba)
   durations.append(round((index+1)*duration_ms/target)-round(index*duration_ms/target))
  temp=args.input_dir/(sku+'.webp')
  frames[0].save(temp,save_all=True,append_images=frames[1:],duration=durations,loop=1,quality=88,method=4,minimize_size=False,allow_mixed=True)
  target_file=out/(sku+'.webp');target_file.write_bytes(temp.read_bytes())
  thumb=out/('thumb_'+sku+'.png');key=frames[min(len(frames)-1,round(len(frames)*.4))];key.thumbnail((192,192),Image.Resampling.LANCZOS);canvas=Image.new('RGBA',(192,192));canvas.alpha_composite(key,((192-key.width)//2,(192-key.height)//2));canvas.save(thumb)
  audio=out/(sku+'.m4a')
  subprocess.run(['ffmpeg','-v','error','-i',str(src),'-map','0:a:0','-vn','-c:a','aac','-b:a','96k','-af',f'apad=whole_dur={duration_ms/1000}','-t',str(duration_ms/1000),'-y',str(args.input_dir/(sku+'.m4a'))],check=True)
  audio.write_bytes((args.input_dir/(sku+'.m4a')).read_bytes())
  gifts[sku]={'sku':sku,'title':title,'coins':coins,'source':filename,'source_sha256':sha(src),'source_bytes':src.stat().st_size,'duration_ms':duration_ms,'width':w,'height':h,'frames':target,'mask':mode,'decode_warnings':decoded.stderr.decode(errors='replace')[:3000]}
  for p in [target_file,thumb,audio]:files[p.name]={'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':sha(p),'sku':sku}
  receipt.write_text(json.dumps({'gifts':list(gifts.values()),'files':list(files.values()),'model':{'url':'https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx','sha256':MODEL_SHA,'license':'Apache-2.0','runtime':'offline processing only'},'notes':'User-supplied generated MP4s; inferred foreground plus mode-specific luminance/chroma protection and spatial edge feather. Strong subject cores stay opaque. Not depth/face tracked AR. No original frames trimmed; frame timing preserves source duration.'},indent=2)+'\n')
  print('Prepared',sku,duration_ms,'ms',target,'frames',target_file.stat().st_size,'bytes',flush=True)
if __name__=='__main__':main()
