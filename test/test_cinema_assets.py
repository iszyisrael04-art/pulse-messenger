"""Check the exact licensed production inputs and distributable media bytes."""
import hashlib,json,struct,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class CinemaAssetTests(unittest.TestCase):
 def test_bundled_media_is_complete_and_matches_reviewed_bytes(self):
  rows=json.loads((ROOT/'art/gift_sources/rendered.json').read_text(encoding='utf-8'))
  skus={'dream','phoenix','dragon','sports_car','lion','gorilla','royal_lions','pulse_stars','thunder_falcon','galaxy','voltage_dominion','void_rift','solar_overdrive','quantum_cathedral','prism_avalanche','aurora_ascension','gravity_collapse','pulse_supernova'}
  expected={f'assets/gifts/{prefix}{sku}{ext}' for sku in skus for prefix,ext in [('cinema_','.mp4'),('thumb_','.png')]}
  self.assertEqual({x['path'] for x in rows},expected)
  total=0
  for row in rows:
   b=(ROOT/row['path']).read_bytes();total+=len(b)
   self.assertEqual(len(b),row['bytes']);self.assertEqual(hashlib.sha256(b).hexdigest(),row['sha256'])
   if row['path'].endswith('.mp4'):
    self.assertEqual(b[4:8],b'ftyp');self.assertIn(b'moov',b);self.assertIn(b'vide',b);self.assertIn(b'soun',b)
   else:
    self.assertEqual(b[:8],b'\x89PNG\r\n\x1a\n');self.assertEqual(struct.unpack('>II',b[16:24]),(192,192))
  self.assertLess(total,10*1024*1024)
 def test_original_effects_have_complete_receipts(self):
  data=json.loads((ROOT/'art/gift_sources/effects.json').read_text(encoding='utf-8'))
  self.assertEqual(len(data['effects']),8)
  self.assertEqual(len(data['files']),16)
  self.assertEqual(data['author'],'Pulse')
  for effect in data['effects']:
   self.assertEqual((effect['width'],effect['height'],effect['fps'],effect['frames']),(480,854,24,144))
   self.assertGreaterEqual(effect['coins'],29999)
 def test_production_inputs_have_per_asset_provenance(self):
  rows=json.loads((ROOT/'art/gift_sources/manifest.json').read_text(encoding='utf-8'))['assets']
  self.assertEqual(len(rows),7)
  for row in rows:
   self.assertTrue(row['source'].startswith('https://'));self.assertTrue(row['download'].startswith('https://'))
   self.assertEqual(len(row['sha256']),64);self.assertTrue(row['author']);self.assertTrue(row['license'])
if __name__=='__main__':unittest.main()
