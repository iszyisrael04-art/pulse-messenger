"""Verify licensed wildlife payloads and removal of former effect assets."""
import hashlib,json,struct,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class WildlifeAssetTests(unittest.TestCase):
 def test_media_matches_reviewed_provenance(self):
  data=json.loads((ROOT/'art/gift_sources/wildlife.json').read_text())
  skus={'lion','royal_lions','gorilla','thunder_falcon'}
  expected={f'assets/gifts/{prefix}{sku}{ext}' for sku in skus for prefix,ext in [('wildlife_','.mp4'),('thumb_','.png')]}
  self.assertEqual({x['path'] for x in data['files']},expected)
  self.assertEqual({p.relative_to(ROOT).as_posix() for p in (ROOT/'assets/gifts').iterdir() if not p.name.startswith(('legend_', 'thumb_legend_', 'premium_', 'thumb_premium_', 'gift_', 'live_cover_'))},expected)
  for row in data['files']:
   b=(ROOT/row['path']).read_bytes()
   self.assertEqual(len(b),row['bytes']);self.assertEqual(hashlib.sha256(b).hexdigest(),row['sha256'])
   source=data['sources'][row['source']]
   self.assertTrue(source['page'].startswith('https://commons.wikimedia.org/wiki/'))
   self.assertIn(source['license'],['CC0-1.0','CC-BY-4.0','CC-BY-SA-2.0'])
   self.assertEqual(row['license'],source['license']);self.assertEqual(len(source['sha256']),64)
   if row['path'].endswith('.mp4'):
    self.assertEqual(b[4:8],b'ftyp');self.assertIn(b'moov',b);self.assertIn(b'vide',b)
   else:
    self.assertEqual(b[:8],b'\x89PNG\r\n\x1a\n');self.assertEqual(struct.unpack('>II',b[16:24]),(192,192))
  self.assertLess(sum(r['bytes'] for r in data['files']),4*1024*1024)
 def test_no_active_synthetic_renderers(self):
  for f in ['lib/gift_stories.dart','lib/gift_story_player.dart','lib/magic_hat.dart','lib/gift_face_anchor.dart']:
   self.assertFalse((ROOT/f).exists())
  self.assertFalse(list((ROOT/'art/gift_sources').glob('*.glb')))
if __name__=='__main__':unittest.main()
