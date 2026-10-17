"""Configure generated native runners for the separate Pulse Control app."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
manifest=root/'android/app/src/main/AndroidManifest.xml'
if manifest.exists():
 s=manifest.read_text();s=s.replace('android:label="PULSE"','android:label="Pulse Control"').replace('android:name=".MainActivity"','android:name="com.pulsemessenger.pulse_messenger.MainActivity"');manifest.write_text(s)
gradle=root/'android/app/build.gradle.kts'
if gradle.exists():
 s=gradle.read_text().replace('applicationId = "com.pulsemessenger.pulse_messenger"','applicationId = "com.pulsemessenger.pulse_control"');
 if 'com.pulsemessenger.pulse_control' not in s: raise RuntimeError('Staff application ID was not configured.')
 gradle.write_text(s)
cmake=root/'windows/CMakeLists.txt'
if cmake.exists():cmake.write_text(cmake.read_text().replace('set(BINARY_NAME "Pulse")','set(BINARY_NAME "PulseControl")'))
for file in [root/'windows/runner/main.cpp',root/'windows/runner/Runner.rc']:
 if file.exists():file.write_text(file.read_text().replace('Pulse.exe','PulseControl.exe').replace('L"Pulse"','L"Pulse Control"').replace('"Pulse"','"Pulse Control"'))
print('Pulse Control native identity configured. Build with --dart-define=PULSE_STAFF=true.')
