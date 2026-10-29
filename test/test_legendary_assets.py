import hashlib,json,struct,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class LegendaryTests(unittest.TestCase):
 def test_prepared_assets_have_provenance_and_portable_headers(self):
  data=json.loads((ROOT/'art/gift_sources/legendary.json').read_text())
  self.assertEqual(len(data['gifts']),9);self.assertEqual(len(data['files']),36)
  self.assertEqual(sorted(g['coins'] for g in data['gifts']),[1000,5000,7500,10000,15000,20000,30000,50000,60000])
  for g in data['gifts']:
   self.assertEqual(len(g['source_sha256']),64);self.assertGreaterEqual(g['duration_ms'],5042)
   self.assertLessEqual(g['duration_ms'],5167);self.assertGreater(g['frames'],100)
  for row in data['files']:
   b=(ROOT/row['path']).read_bytes();self.assertEqual(len(b),row['bytes']);self.assertEqual(hashlib.sha256(b).hexdigest(),row['sha256'])
   if row['path'].endswith('.webp'):
    self.assertEqual(b[:4],b'RIFF');self.assertEqual(b[8:12],b'WEBP');self.assertIn(b'ANIM',b);self.assertIn(b'ANMF',b);self.assertIn(b'ALPH',b)
   elif row['path'].endswith(('.m4a','.mp4')):self.assertEqual(b[4:8],b'ftyp')
   else:self.assertEqual(struct.unpack('>II',b[16:24]),(192,192))
 def test_no_cloud_matting_or_untrusted_effect_urls_in_player(self):
  code=(ROOT/'lib/legendary_overlay.dart').read_text()
  self.assertNotIn('http://',code);self.assertNotIn('https://',code)
  self.assertIn('codec.dispose()',code);self.assertIn('old?.dispose()',code)
  self.assertIn('targetWidth:480',code.replace(' ',''))
if __name__=='__main__':unittest.main()
