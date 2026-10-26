"""Download the pinned, licensed editable sources for Pulse gift production.
Sources are build-time art inputs, not additional downloads in the app.
Run once before render_cinema_gifts.py. Existing matching bytes are reused.
"""
from pathlib import Path
import hashlib,json,urllib.request,struct
root=Path(__file__).resolve().parents[1]/'art/gift_sources'
for item in json.loads((root/'manifest.json').read_text())['assets']:
 path=root/item['file']
 data=path.read_bytes() if path.exists() else b''
 if hashlib.sha256(data).hexdigest()!=item['sha256']:
  request=urllib.request.Request(item['download'],headers={'User-Agent':'Pulse-art-source-fetch/1.0'})
  with urllib.request.urlopen(request,timeout=60) as response:data=response.read(32*1024*1024)
  if len(data)!=item['bytes'] or hashlib.sha256(data).hexdigest()!=item['sha256']:
   raise RuntimeError(f"Source changed; review before accepting: {item['name']}")
  if path.suffix=='.glb' and (data[:4]!=b'glTF' or struct.unpack_from('<I',data,4)[0]!=2):
   raise RuntimeError('Not a glTF 2.0 binary')
  temporary=path.with_suffix('.partial');temporary.write_bytes(data);temporary.replace(path)
 print('Verified licensed source:',item['name'])
