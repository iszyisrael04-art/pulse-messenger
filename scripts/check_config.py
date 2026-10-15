"""Reject server secrets or incomplete public build config without printing values."""
import argparse
import base64
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

FIREBASE = {'FIREBASE_API_KEY', 'FIREBASE_APP_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_PROJECT_ID'}
ALLOWED = {'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY'} | FIREBASE


def validate_config(config):
    if not isinstance(config, dict) or set(config) - ALLOWED:
        raise ValueError('Unsupported build configuration fields. Only public client options are permitted.')
    if any(not isinstance(value, str) for value in config.values()):
        raise ValueError('Build configuration values must be strings.')
    url = urlsplit(config.get('SUPABASE_URL', ''))
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
        raise ValueError('SUPABASE_URL must be an HTTPS project origin without credentials.')
    key = config.get('SUPABASE_PUBLISHABLE_KEY', '')
    if key.startswith('sb_publishable_'):
        if not re.fullmatch(r'sb_publishable_[A-Za-z0-9_-]{10,}', key):
            raise ValueError('Invalid publishable key format.')
    else:
        try:
            payload = key.split('.')[1]
            claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
            if claims.get('role') != 'anon':
                raise ValueError()
        except (ValueError, IndexError, TypeError, AttributeError):
            raise ValueError('Use a publishable key or legacy anon key, never a user token or server key.') from None
    present = [bool(config.get(key, '').strip()) for key in FIREBASE]
    if any(present) and not all(present):
        raise ValueError('Firebase client configuration is incomplete. Supply all four public fields or omit all four.')
    return all(present)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', nargs='?', default='config.example.json')
    args = parser.parse_args()
    try:
        enabled = validate_config(json.loads(Path(args.config).read_text(encoding='utf-8')))
    except (OSError, ValueError) as error:
        parser.exit(1, f'Build configuration rejected: {error}\n')
    print('Public build configuration passed. Firebase client: ' + ('configured; delivery still requires server setup/testing.' if enabled else 'not configured.'))
