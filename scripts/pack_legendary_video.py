"""Pack RGB + alpha into one H264/AAC stream for hardware decoding on Impeller.
Requires finalized alpha WebPs and audio tracks from prepare/optimize steps.
"""
import json,subprocess,pathlib,numpy as np
from PIL import Image
ROOT=pathlib.Path(__file__).resolve().parents[1]
def pack(g):
 p=ROOT/'assets/gifts'/f"{g['sku']}.webp";im=Image.open(p)
 frames=[];ends=[];t=0
 for i in range(im.n_frames):
  im.seek(i);im.load();t+=im.info.get('duration',0);frames.append(im.convert('RGBA'));ends.append(t)
 w,h=frames[0].size;dest=ROOT/'assets/gifts'/f"{g['sku']}_packed.mp4"
 cmd=['ffmpeg','-v','error','-f','rawvideo','-pix_fmt','rgb24','-s',f'{w*2}x{h}','-r','24','-i','-','-i',str(ROOT/'assets/gifts'/f"{g['sku']}.m4a"),'-vf','pad=ceil(iw/2)*2:ceil(ih/2)*2','-c:v','libx264','-profile:v','main','-pix_fmt','yuv420p','-crf','21','-preset','medium','-c:a','copy','-t',str(g['duration_ms']/1000),'-movflags','+faststart','-y',str(dest)]
 process=subprocess.Popen(cmd,stdin=subprocess.PIPE);index=0
 for j in range(round(g['duration_ms']*24/1000)):
  while index+1<len(frames) and ends[index]<=j*1000/24:index+=1
  a=np.asarray(frames[index]);matte=np.repeat(a[:,:,3:4],3,axis=2)
  process.stdin.write(np.concatenate([a[:,:,:3],matte],axis=1).tobytes())
 process.stdin.close();assert process.wait()==0
 print('Packed',g['sku'],dest.stat().st_size,flush=True)
 return dest
if __name__=='__main__':
 data=json.loads((ROOT/'art/gift_sources/legendary.json').read_text())
 for gift in data['gifts']:pack(gift)
