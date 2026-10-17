import runpy
import tempfile
import unittest
from pathlib import Path
SCRIPT=Path(__file__).resolve().parents[1]/'scripts/configure_staff.py'
class StaffIdentityTest(unittest.TestCase):
 def test_distinct_native_identity_and_idempotency(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp); script=root/'scripts/configure_staff.py';script.parent.mkdir();script.write_text(SCRIPT.read_text())
   files={'android/app/src/main/AndroidManifest.xml':'<application android:label="PULSE"><activity android:name=".MainActivity"/></application>', 'android/app/build.gradle.kts':'namespace = "com.pulsemessenger.pulse_messenger"\napplicationId = "com.pulsemessenger.pulse_messenger"', 'windows/CMakeLists.txt':'set(BINARY_NAME "Pulse")', 'windows/runner/main.cpp':'window.Create(L"Pulse");','windows/runner/Runner.rc':'VALUE "ProductName", "Pulse"\nVALUE "OriginalFilename", "Pulse.exe"'}
   for path,text in files.items():p=root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
   runpy.run_path(str(script));runpy.run_path(str(script))
   self.assertIn('applicationId = "com.pulsemessenger.pulse_control"',(root/'android/app/build.gradle.kts').read_text())
   self.assertIn('namespace = "com.pulsemessenger.pulse_messenger"',(root/'android/app/build.gradle.kts').read_text())
   self.assertIn('com.pulsemessenger.pulse_messenger.MainActivity',(root/'android/app/src/main/AndroidManifest.xml').read_text())
   self.assertIn('PulseControl',(root/'windows/CMakeLists.txt').read_text())
