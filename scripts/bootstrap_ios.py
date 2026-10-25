"""Generate iOS runner for compile checks. Apple distribution needs signing."""
import json
import plistlib
import subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
subprocess.run(['flutter','create','--no-pub','--platforms=ios','--org','com.pulsemessenger','--project-name','pulse_messenger','.'],cwd=root,check=True)
p = root/'ios/Runner/Info.plist'
with p.open('rb') as f: info=plistlib.load(f)
info.update(CFBundleDisplayName='Pulse',NSCameraUsageDescription='Use the camera for calls, LIVE and posts.',NSMicrophoneUsageDescription='Use the microphone for calls, LIVE and voice messages.',NSPhotoLibraryUsageDescription='Choose media to share in Pulse.',NSPhotoLibraryAddUsageDescription='Save permitted Pulse media to your library.',FirebaseMessagingAutoInitEnabled=False)
with p.open('wb') as f: plistlib.dump(info,f)
project=root/'ios/Runner.xcodeproj/project.pbxproj'
s=project.read_text().replace('IPHONEOS_DEPLOYMENT_TARGET = 13.0;', 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;')
project.write_text(s)
pod=root/'ios/Podfile'
if pod.exists():
 s=pod.read_text();s=s.replace("# platform :ios, '13.0'", "platform :ios, '15.0'").replace("platform :ios, '13.0'", "platform :ios, '15.0'");pod.write_text(s)
assets=root/'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for icon in json.loads((assets/'Contents.json').read_text())['images']:
 if 'filename' not in icon: continue
 size=round(float(icon['size'].split('x')[0])*float(icon['scale'].rstrip('x')))
 subprocess.run(['sips','-z',str(size),str(size),str(root/'assets/branding/pulse.png'),'--out',str(assets/icon['filename'])],check=True,stdout=subprocess.DEVNULL)
