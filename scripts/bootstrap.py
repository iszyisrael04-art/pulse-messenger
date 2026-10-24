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
for permission in ['INTERNET', 'POST_NOTIFICATIONS', 'CAMERA', 'RECORD_AUDIO', 'ACCESS_NETWORK_STATE', 'CHANGE_NETWORK_STATE', 'MODIFY_AUDIO_SETTINGS', 'USE_FULL_SCREEN_INTENT', 'VIBRATE']:
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
if 'com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver' not in s:
    s = s.replace('</application>', '<receiver android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" android:exported="false"/>\n</application>', 1)
# Disable FCM auto-init until the user opts into alerts.
if 'firebase_messaging_auto_init_enabled' not in s:
    s = s.replace('</application>', '<meta-data android:name="firebase_messaging_auto_init_enabled" android:value="false" />\n    </application>', 1)
# Call notifications may open the answer screen over the lock screen when Android permits.
for attribute in ['showWhenLocked', 'turnScreenOn']:
    if 'android:' + attribute not in s:
        s = s.replace('<activity', f'<activity android:{attribute}="true"', 1)
manifest.write_text(s, encoding='utf-8')
raw = root / 'android/app/src/main/res/raw'
raw.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'assets/audio/incoming.ogg', raw / 'pulse_ringtone.ogg')
icon = root / 'android/app/src/main/res/drawable/ic_pulse_notification.xml'
icon.parent.mkdir(parents=True, exist_ok=True)
icon.write_text('<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24"><path android:strokeColor="#FFFFFFFF" android:strokeWidth="2.4" android:fillColor="#00000000" android:pathData="M7,21V3h7c10,0 10,12 0,12H7"/></vector>', encoding='utf-8')
# Branded OS launch window. Account-selected Flutter splash begins after
# local settings load; Android's own launch frame uses a fixed Pulse mark.
import xml.etree.ElementTree as ET
res = root / 'android/app/src/main/res'
(res / 'drawable/pulse_launch.xml').write_text('<layer-list xmlns:android="http://schemas.android.com/apk/res/android"><item android:drawable="@color/pulse_launch_background"/><item android:width="96dp" android:height="96dp" android:gravity="center" android:drawable="@drawable/pulse_launch_logo"/></layer-list>', encoding='utf-8')
(res / 'drawable/pulse_launch_logo.xml').write_text('<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="96dp" android:height="96dp" android:viewportWidth="100" android:viewportHeight="100"><path android:strokeColor="#FF23E5BA" android:strokeWidth="7" android:strokeLineCap="round" android:strokeLineJoin="round" android:fillColor="#00000000" android:pathData="M30 79 V24 H53 C70 24 79 32 79 45 C79 58 69 64 53 64 H30"/></vector>', encoding='utf-8')
for variant in ['values', 'values-night', 'values-v31', 'values-night-v31']:
    target = res / variant
    target.mkdir(parents=True, exist_ok=True)
    styles = target / 'styles.xml'
    tree = ET.parse(styles) if styles.exists() else ET.ElementTree(ET.Element('resources'))
    resources = tree.getroot()
    launch = next((x for x in resources.findall('style') if x.get('name') == 'LaunchTheme'), None)
    if launch is None:
        launch = ET.SubElement(resources, 'style', {'name':'LaunchTheme', 'parent':'@android:style/Theme.Black.NoTitleBar'})
    def item(name, value):
        node = next((x for x in launch.findall('item') if x.get('name') == name), None)
        if node is None: node = ET.SubElement(launch, 'item', {'name':name})
        node.text = value
    item('android:windowBackground', '@drawable/pulse_launch')
    if 'v31' in variant:
        item('android:windowSplashScreenBackground', '@color/pulse_launch_background')
        item('android:windowSplashScreenAnimatedIcon', '@drawable/pulse_launch_logo')
    tree.write(styles, encoding='utf-8', xml_declaration=True)
    (target / 'pulse_launch_colors.xml').write_text('<resources><color name="pulse_launch_background">#080B0F</color></resources>', encoding='utf-8')
# Flutter stable generates Kotlin Gradle files. Preserve its Java/Kotlin versions.
gradle = root / 'android/app/build.gradle.kts'
if not gradle.exists():
    raise RuntimeError('Expected Flutter Kotlin Gradle runner; update bootstrap for this SDK.')
s = gradle.read_text(encoding='utf-8')
if 'isCoreLibraryDesugaringEnabled' not in s:
    s = s.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
if 'desugar_jdk_libs' not in s:
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
if 'media3-transformer' not in s:
    s += '\ndependencies {\n    implementation("androidx.media3:media3-transformer:1.8.0")\n    implementation("androidx.media3:media3-effect:1.8.0")\n}\n'
gradle.write_text(s, encoding='utf-8')
runner = root / 'windows/runner/main.cpp'
if runner.exists():
    runner.write_text(runner.read_text(encoding='utf-8').replace('L"pulse_messenger"', 'L"Pulse"').replace('L"Pulse Messenger"', 'L"Pulse"').replace('L"PULSE"', 'L"Pulse"'), encoding='utf-8')
# Keep the existing installer identity while branding Windows as Pulse.
windows_cmake = root / 'windows/CMakeLists.txt'
if windows_cmake.exists():
    text = windows_cmake.read_text(encoding='utf-8')
    text = text.replace('set(BINARY_NAME "pulse_messenger")', 'set(BINARY_NAME "Pulse")')
    windows_cmake.write_text(text, encoding='utf-8')
windows_resources = root / 'windows/runner/Runner.rc'
if windows_resources.exists():
    text = windows_resources.read_text(encoding='utf-8')
    text = text.replace('pulse_messenger', 'Pulse').replace('Pulse Messenger', 'Pulse').replace('PULSE', 'Pulse')
    windows_resources.write_text(text, encoding='utf-8')
# Use the same original favicon for native launcher and runtime splash branding.
branding = root / 'assets/branding'
if (branding / 'pulse.png').exists():
    (res / 'drawable/pulse_launch_logo.xml').unlink(missing_ok=True)
    shutil.copyfile(branding / 'pulse.png', res / 'drawable/pulse_launch_logo.png')
if (branding / 'android').exists():
    for source in (branding / 'android').glob('mipmap-*/ic_launcher.png'):
        destination = root / 'android/app/src/main/res' / source.parent.name / source.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
if (branding / 'pulse.ico').exists():
    destination = root / 'windows/runner/resources/app_icon.ico'
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(branding / 'pulse.ico', destination)
# Native media export: Android platform codecs and Windows MediaComposition.
native = root / 'native/editor'
if native.exists():
    kotlin = root / 'android/app/src/main/kotlin/com/pulsemessenger/pulse_messenger'
    kotlin.mkdir(parents=True, exist_ok=True)
    for source in native.glob('*.kt'):
        shutil.copyfile(source, kotlin / source.name)
    activity = kotlin / 'MainActivity.kt'
    if activity.exists():
        text = activity.read_text(encoding='utf-8')
        if 'PulseNativeEditor(this,' not in text:
            method = '\n    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {\n        super.configureFlutterEngine(flutterEngine)\n        PulseNativeEditor(this, flutterEngine.dartExecutor.binaryMessenger)\n    }\n'
            if 'class MainActivity: FlutterActivity()' in text:
                text = text.replace('class MainActivity: FlutterActivity()', 'class MainActivity: FlutterActivity() {' + method + '}')
            elif 'class MainActivity : FlutterActivity()' in text:
                text = text.replace('class MainActivity : FlutterActivity()', 'class MainActivity : FlutterActivity() {' + method + '}')
            else:
                raise RuntimeError('MainActivity is customized: register PulseNativeEditor in configureFlutterEngine.')
            # Flutter's empty class may already have braces.
            text = text.replace('} {\n}', '}').replace('} {}', '}')
            activity.write_text(text, encoding='utf-8')
    cmake = root / 'windows/CMakeLists.txt'
    if cmake.exists():
        text = cmake.read_text(encoding='utf-8')
        legacy_editor_copy = 'add_custom_command(TARGET pulse_editor POST_BUILD COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:${BINARY_NAME}>" COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:pulse_editor>" "$<TARGET_FILE_DIR:${BINARY_NAME}>")'
        if legacy_editor_copy in text:
            text = text.replace(legacy_editor_copy, 'set_target_properties(pulse_editor PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner/$<CONFIG>")')
            cmake.write_text(text, encoding='utf-8')
        # Flutter uses a generator expression as its bundle prefix. Expand it
        # in an explicit destination; a relative target install leaves it literal.
        legacy_editor_install = 'install(TARGETS pulse_editor RUNTIME DESTINATION "." COMPONENT Runtime)'
        if legacy_editor_install in text:
            text = text.replace(legacy_editor_install, 'install(FILES "$<TARGET_FILE:pulse_editor>" DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)')
            cmake.write_text(text, encoding='utf-8')
        if '# Pulse native editor' not in text:
            text += '\n# Pulse native editor\nadd_library(pulse_editor SHARED "${CMAKE_CURRENT_SOURCE_DIR}/../native/editor/pulse_editor.cpp")\ntarget_compile_features(pulse_editor PRIVATE cxx_std_17)\ntarget_link_libraries(pulse_editor PRIVATE windowsapp)\nadd_dependencies(${BINARY_NAME} pulse_editor)\nset_target_properties(pulse_editor PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner/$<CONFIG>")\ninstall(FILES "$<TARGET_FILE:pulse_editor>" DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)\n'
            cmake.write_text(text, encoding='utf-8')
default = root / 'test/widget_test.dart'
if default.exists():
    s = default.read_text(encoding='utf-8')
    if 'MyApp' in s and 'counter' in s.lower():
        default.unlink()
print('Pulse native runners generated successfully.')
