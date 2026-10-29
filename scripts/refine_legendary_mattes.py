"""Refine the difficult moving car and gold/brown feather footage offline.
ISNet is used only for the car; gold/brown keying preserves dark feather cores.
Models are never bundled in Pulse or run on viewers' devices.
"""
import argparse,hashlib,json,pathlib,subprocess,numpy as np
from PIL import Image,ImageFilter
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--input-dir',type=pathlib.Path,required=True);ap.add_argument('--isnet',type=pathlib.Path,required=True);args=ap.parse_args()
 import onnxruntime as ort
 opts=ort.SessionOptions();opts.intra_op_num_threads=4;opts.inter_op_num_threads=1
 session=ort.InferenceSession(str(args.isnet),opts,providers=['CPUExecutionProvider'])
 data=json.loads((ROOT/'art/gift_sources/legendary.json').read_text());output=pathlib.Path('/tmp/legend-refined');output.mkdir(exist_ok=True)
 for sku in ['legend_phantom_supercar','legend_pulse_legend']:
  g=next(g for g in data['gifts'] if g['sku']==sku);src=args.input_dir/g['source'];assert hashlib.sha256(src.read_bytes()).hexdigest()==g['source_sha256']
  w=480;source=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height','-of','json',str(src)]))['streams'][0];h=round(source['height']/source['width']*w/2)*2
  raw=subprocess.check_output(['ffmpeg','-v','quiet','-err_detect','ignore_err','-i',str(src),'-vf',f'scale={w}:{h},fps=24','-pix_fmt','rgb24','-f','rawvideo','-']);available=len(raw)//(w*h*3);frames=[];count=round(g['duration_ms']*24/1000)
  yy,xx=np.mgrid[0:h,0:w];edge=np.clip(np.minimum.reduce([xx/(w*.11),(w-1-xx)/(w*.11),yy/(h*.12),(h-1-yy)/(h*.12)]),0,1);edge=edge*edge*(3-2*edge)
  for i in range(count):
   j=min(i,available-1);im=Image.frombytes('RGB',(w,h),raw[j*w*h*3:(j+1)*w*h*3]);a=np.asarray(im).astype('float32')/255
   if sku=='legend_pulse_legend':
    warm=np.clip((a[:,:,0]-.035)/.075,0,1)*np.clip((a[:,:,0]+a[:,:,1]-2*a[:,:,2]-.015)/.08,0,1)
    closed=np.asarray(Image.fromarray((warm*255).astype('uint8')).filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.MinFilter(11)).filter(ImageFilter.GaussianBlur(.6))).astype('float32')/255
    alpha=np.maximum(warm,closed)*edge
   else:
    x=np.asarray(im.resize((1024,1024))).astype('float32')/255-.5
    m=session.run(None,{session.get_inputs()[0].name:x.transpose(2,0,1)[None]})[0][0,0];m=(m-m.min())/max(float(m.max()-m.min()),1e-6)
    m=np.asarray(Image.fromarray((m*255).astype('uint8')).resize((w,h),Image.Resampling.BILINEAR)).astype('float32')/255
    core=np.clip((m-.06)/.55,0,1);core=core*core*(3-2*core)
    red=(a[:,:,0]>a[:,:,1]*1.35)&(a[:,:,0]>a[:,:,2]*1.25)&(a[:,:,0]>.18)&(yy>h*.15)
    ry,rx=np.where(red)
    if len(rx)>15:
     y1=np.quantile(ry,.97);support=np.clip((y1+h*.18-yy)/(h*.10),0,1);core*=support
    alpha=core*edge
   aa=np.clip(np.rint(alpha*255/4)*4,0,255).astype('uint8');aa[0,:]=0;aa[-1,:]=0;aa[:,0]=0;aa[:,-1]=0
   frame=im.convert('RGBA');frame.putalpha(Image.fromarray(aa));frames.append(frame)
   if i%30==0:print(sku,'frame',i,'/',count,flush=True)
  durations=[round((i+1)*g['duration_ms']/count)-round(i*g['duration_ms']/count) for i in range(count)]
  frames[0].save(output/f'{sku}.webp',save_all=True,append_images=frames[1:],duration=durations,loop=1,quality=76,method=4,lossless=False,allow_mixed=False)
  thumb=frames[round(len(frames)*.3)].copy();thumb.thumbnail((192,192),Image.Resampling.LANCZOS);canvas=Image.new('RGBA',(192,192));canvas.alpha_composite(thumb,((192-thumb.width)//2,(192-thumb.height)//2));canvas.save(output/f'thumb_{sku}.png')
  print('REFINED',sku,flush=True)
 (output/'model.json').write_text(json.dumps({'isnet_url':'https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx','sha256':hashlib.sha256(args.isnet.read_bytes()).hexdigest(),'scope':'offline car matting only'}))
if __name__=='__main__':main()
