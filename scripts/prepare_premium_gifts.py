"""Preserve uploaded premium footage with a narrow 3% border feather only."""
import argparse, hashlib, json, pathlib, subprocess
import numpy as np
from PIL import Image
from pack_legendary_video import pack
ROOT = pathlib.Path(__file__).resolve().parents[1]
GIFTS = [
 ('premium_royal_stallion', 'Royal Stallion', 30000, '1000460743.mp4'),
 ('premium_white_tiger', 'White Tiger', 35000, '1000460744.mp4'),
 ('premium_fire_dragon', 'Fire Dragon', 40000, '1000460745.mp4'),
 ('premium_great_shark', 'Great Shark', 45000, '1000460746.mp4'),
]
def main():
 parser=argparse.ArgumentParser(); parser.add_argument('--input-dir',type=pathlib.Path,required=True); args=parser.parse_args()
 receipt={'gifts':[], 'files':[], 'notes':'Original uploaded premium footage and audio. Only the outer 3% is feathered; no foreground segmentation or internal holes.'}
 out=ROOT/'assets/gifts'
 for sku,title,coins,filename in GIFTS:
  src=args.input_dir/filename
  meta=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-show_streams','-of','json',str(src)]))
  v=next(s for s in meta['streams'] if s['codec_type']=='video')
  duration=round(float(meta['format']['duration'])*1000); w=480; h=round(v['height']/v['width']*w/2)*2
  raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(src),'-vf',f'scale={w}:{h},fps=24','-f','rawvideo','-pix_fmt','rgb24','-'])
  count=round(duration*24/1000); available=len(raw)//(w*h*3); assert available>0
  yy,xx=np.mgrid[:h,:w]
  alpha=np.clip(np.minimum.reduce([xx/(w*.03),(w-1-xx)/(w*.03),yy/(h*.03),(h-1-yy)/(h*.03)]),0,1)
  alpha=np.rint(alpha*alpha*(3-2*alpha)*255).astype('uint8'); frames=[]
  for i in range(count):
   j=min(i,available-1); frame=Image.frombytes('RGB',(w,h),raw[j*w*h*3:(j+1)*w*h*3]).convert('RGBA'); frame.putalpha(Image.fromarray(alpha)); frames.append(frame)
  durations=[round((i+1)*duration/count)-round(i*duration/count) for i in range(count)]
  video=out/f'{sku}.webp'; frames[0].save(video,save_all=True,append_images=frames[1:],duration=durations,loop=1,quality=78,method=4,allow_mixed=False)
  thumb=frames[count//3].copy();thumb.thumbnail((192,192),Image.Resampling.LANCZOS);canvas=Image.new('RGBA',(192,192));canvas.alpha_composite(thumb,((192-thumb.width)//2,(192-thumb.height)//2)); thumbnail=out/f'thumb_{sku}.png';canvas.save(thumbnail)
  audio=out/f'{sku}.m4a';subprocess.run(['ffmpeg','-v','error','-i',str(src),'-map','0:a:0','-vn','-c:a','aac','-b:a','96k','-t',str(duration/1000),'-y',str(audio)],check=True)
  gift={'sku':sku,'title':title,'coins':coins,'source':filename,'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'duration_ms':duration,'width':w,'height':h,'frames':count}
  packed=pack(gift);receipt['gifts'].append(gift)
  for p in [video,audio,thumbnail,packed]:receipt['files'].append({'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'sku':sku})
 (ROOT/'art/gift_sources/premium.json').write_text(json.dumps(receipt,indent=2)+'\n')
if __name__=='__main__':main()
