"""Download reviewed licensed footage into a temporary cache; trim and encode MP4s.
Original URLs, attribution, source hashes and output hashes are recorded in wildlife.json.
No social-media reposts, watermark removal, synthesis or 3D rendering is used.
"""
import hashlib,json,pathlib,subprocess,tempfile,urllib.request,shutil
ROOT=pathlib.Path(__file__).resolve().parents[1]
CACHE=pathlib.Path(tempfile.gettempdir())/'pulse-wildlife';CACHE.mkdir(exist_ok=True)
SOURCES={
 'lions':{'url':'https://upload.wikimedia.org/wikipedia/commons/3/32/Lions_in_the_wild.webm','page':'https://commons.wikimedia.org/wiki/File:Lions_in_the_wild.webm','author':'Coverr','license':'CC0-1.0','license_url':'https://creativecommons.org/publicdomain/zero/1.0/'},
 'gorilla':{'url':'https://upload.wikimedia.org/wikipedia/commons/c/c1/Wild_Western_Lowland_gorilla_and_his_family_foraging_for_figs.webm','page':'https://commons.wikimedia.org/wiki/File:Wild_Western_Lowland_gorilla_and_his_family_foraging_for_figs.webm','author':'TheLeftCoast','license':'CC-BY-4.0','license_url':'https://creativecommons.org/licenses/by/4.0/'},
 'falcon':{'url':'https://upload.wikimedia.org/wikipedia/commons/f/f6/Peregrine_falcon_(Falco_peregrinus)_in_West_Reno,_Nevada,_USA.webm','page':'https://commons.wikimedia.org/wiki/File:Peregrine_falcon_(Falco_peregrinus)_in_West_Reno,_Nevada,_USA.webm','author':'Paul Hurtado','license':'CC-BY-SA-2.0','license_url':'https://creativecommons.org/licenses/by-sa/2.0/'},
}
SHOTS={'lion':('lions',0),'royal_lions':('lions',7),'gorilla':('gorilla',6.5),'thunder_falcon':('falcon',2)}
def run(args):subprocess.run(args,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 receipt=ROOT/'art/gift_sources/wildlife.json'
 old=json.loads(receipt.read_text()) if receipt.exists() else {}
 for name,s in SOURCES.items():
  p=CACHE/(name+'.webm')
  if not p.exists():
   req=urllib.request.Request(s['url'],headers={'User-Agent':'Mozilla/5.0'})
   p.write_bytes(urllib.request.urlopen(req,timeout=40).read())
  previous=old.get('sources',{}).get(name,{}).get('sha256')
  if previous and previous!=digest(p):raise ValueError('Source changed: '+name)
  s['sha256']=digest(p)
 rows=[]
 for sku,(source,start) in SHOTS.items():
  src=CACHE/(source+'.webm');out=CACHE/('wildlife_'+sku+'.mp4');thumb=CACHE/('thumb_'+sku+'.png')
  run(['ffmpeg','-v','error','-ss',str(start),'-i',str(src),'-t','5','-vf','scale=640:-2,fps=24','-c:v','libx264','-profile:v','main','-pix_fmt','yuv420p','-crf','25','-preset','medium','-c:a','aac','-b:a','64k','-movflags','+faststart','-y',str(out)])
  run(['ffmpeg','-v','error','-ss','1','-i',str(out),'-vf','scale=192:192:force_original_aspect_ratio=increase,crop=192:192','-frames:v','1','-y',str(thumb)])
  probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-show_entries','stream=codec_type,codec_name,width,height','-of','json',str(out)]))
  assert 4.8<=float(probe['format']['duration'])<=5.2
  for f in [out,thumb]:
   target=ROOT/'assets/gifts'/f.name;shutil.copyfile(f,target)
   rows.append({'path':str(target.relative_to(ROOT)),'bytes':target.stat().st_size,'sha256':digest(target),'source':source,'start':start,'duration':5,'license':SOURCES[source]['license']})
 receipt.write_text(json.dumps({'sources':SOURCES,'files':rows,'changes':'Trimmed to 5 seconds, resized, re-encoded to H264/AAC where audio exists; square thumbnails extracted. No watermarks removed. CC BY-SA derivatives retain CC BY-SA 2.0.','reviewed':'2026-10-26'},indent=2)+'\n')
 print('Prepared',len(rows),'files;',sum(r['bytes'] for r in rows),'bytes')
if __name__=='__main__':main()
