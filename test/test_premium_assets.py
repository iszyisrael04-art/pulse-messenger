import hashlib,json,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class PremiumAssets(unittest.TestCase):
 def test_uploaded_assets_and_prices(self):
  data=json.loads((ROOT/'art/gift_sources/premium.json').read_text())
  self.assertEqual([g['coins'] for g in data['gifts']],[30000,35000,40000,45000])
  self.assertEqual([g['source'] for g in data['gifts']],['1000460743.mp4','1000460744.mp4','1000460745.mp4','1000460746.mp4'])
  self.assertEqual(len(data['files']),16)
  for row in data['files']:
   b=(ROOT/row['path']).read_bytes()
   self.assertEqual(len(b),row['bytes'])
   self.assertEqual(hashlib.sha256(b).hexdigest(),row['sha256'])
  for gift in data['gifts']:
   self.assertEqual(gift['duration_ms'],5042)
   self.assertEqual(gift['frames'],121)
if __name__=='__main__':unittest.main()
