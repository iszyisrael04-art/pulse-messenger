"""Merge optional public Firebase app settings; never accept service credentials."""
import json
import os
from pathlib import Path
import xml.etree.ElementTree as ET
from check_config import validate_config, FIREBASE

def configure(path, raw):
    if not raw:
        return False
    values = json.loads(raw)
    if not isinstance(values, dict) or set(values) != FIREBASE:
        raise ValueError('Supply only the four public Firebase client fields.')
    config = json.loads(path.read_text())
    config.update(values)
    validate_config(config)
    path.write_text(json.dumps(config, indent=2) + '\n')
    # FirebaseInitProvider needs native resources when Android starts the process
    # for a push before the Flutter UI has initialized Firebase.
    values_dir = path.parent / 'android/app/src/main/res/values'
    values_dir.mkdir(parents=True, exist_ok=True)
    resources = ET.Element('resources')
    for resource, field in {
        'google_app_id': 'FIREBASE_APP_ID',
        'gcm_defaultSenderId': 'FIREBASE_MESSAGING_SENDER_ID',
        'google_api_key': 'FIREBASE_API_KEY',
        'project_id': 'FIREBASE_PROJECT_ID',
    }.items():
        ET.SubElement(resources, 'string', {'name': resource, 'translatable': 'false'}).text = values[field]
    ET.ElementTree(resources).write(values_dir / 'pulse_firebase.xml', encoding='utf-8', xml_declaration=True)
    return True

if __name__ == '__main__':
    try:
        enabled = configure(Path('config.example.json'), os.environ.get('FIREBASE_CLIENT_JSON', ''))
    except (ValueError, OSError):
        raise SystemExit('Firebase client configuration rejected; check the four public fields.')
    print('Firebase public client configuration merged.' if enabled else 'No optional Firebase configuration supplied; background push stays unavailable.')
