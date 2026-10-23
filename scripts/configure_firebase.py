"""Merge optional public Firebase app settings; never accept service credentials."""
import json
import os
from pathlib import Path
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
    return True

if __name__ == '__main__':
    try:
        enabled = configure(Path('config.example.json'), os.environ.get('FIREBASE_CLIENT_JSON', ''))
    except (ValueError, OSError):
        raise SystemExit('Firebase client configuration rejected; check the four public fields.')
    print('Firebase public client configuration merged.' if enabled else 'No optional Firebase configuration supplied; background push stays unavailable.')
