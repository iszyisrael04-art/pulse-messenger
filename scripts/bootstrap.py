"""Generate native runners and configure notifications and camera capture."""
from pathlib import Path
import shutil
import subprocess
root = Path(__file__).resolve().parents[1]
flutter = shutil.which('flutter')
if flutter is None:
    raise RuntimeError('Flutter was not found on PATH.')
subprocess.run([flutter, 'create', '--no-pub', '--platforms=android,windows', '--org', 'com.pulsemessenger', '--project-name', 'pulse_messenger', '.'], cwd=root, check=True)
manifest = root / 'android/app/src/main/AndroidManifest.xml'
s = manifest.read_text(encoding='utf-8')
for permission in ['INTERNET', 'POST_NOTIFICATIONS', 'CAMERA', 'RECORD_AUDIO', 'ACCESS_NETWORK_STATE', 'CHANGE_NETWORK_STATE', 'MODIFY_AUDIO_SETTINGS']:
    name = 'android.permission.' + permission
    if name not in s:
        s = s.replace('<application', f'<uses-permission android:name="{name}" />\n    <application', 1)
for feature in ['android.hardware.camera', 'android.hardware.microphone']:
    if feature not in s:
        s = s.replace('<application', f'<uses-feature android:name="{feature}" android:required="false" />\n    <application', 1)
s = s.replace('android:label="pulse_messenger"', 'android:label="PULSE"').replace('android:label="Pulse Messenger"', 'android:label="PULSE"')
for attribute in ['allowBackup', 'usesCleartextTraffic']:
    if 'android:' + attribute not in s:
        s = s.replace('<application', f'<application android:{attribute}="false"', 1)
if 'android:scheme="https"' not in s:
    query = '<intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>'
    s = s.replace('</queries>', query + '</queries>', 1) if '</queries>' in s else s.replace('</manifest>', '<queries>' + query + '</queries></manifest>', 1)
# Disable FCM auto-init until the user opts into alerts.
if 'firebase_messaging_auto_init_enabled' not in s:
    s = s.replace('</application>', '<meta-data android:name="firebase_messaging_auto_init_enabled" android:value="false" />\n    </application>', 1)
manifest.write_text(s, encoding='utf-8')
icon = root / 'android/app/src/main/res/drawable/ic_pulse_notification.xml'
icon.parent.mkdir(parents=True, exist_ok=True)
icon.write_text('<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24"><path android:fillColor="#FFFFFFFF" android:pathData="M13,2L4,14h6l-1,8L20,9h-7z"/></vector>', encoding='utf-8')
# Flutter stable generates Kotlin Gradle files. Preserve its Java/Kotlin versions.
gradle = root / 'android/app/build.gradle.kts'
if not gradle.exists():
    raise RuntimeError('Expected Flutter Kotlin Gradle runner; update bootstrap for this SDK.')
s = gradle.read_text(encoding='utf-8')
if 'isCoreLibraryDesugaringEnabled' not in s:
    s = s.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
if 'desugar_jdk_libs' not in s:
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
gradle.write_text(s, encoding='utf-8')
runner = root / 'windows/runner/main.cpp'
if runner.exists():
    runner.write_text(runner.read_text(encoding='utf-8').replace('L"pulse_messenger"', 'L"PULSE"').replace('L"Pulse Messenger"', 'L"PULSE"'), encoding='utf-8')
default = root / 'test/widget_test.dart'
if default.exists():
    s = default.read_text(encoding='utf-8')
    if 'MyApp' in s and 'counter' in s.lower():
        default.unlink()
print('Pulse native runners generated successfully.')
