import base64
import importlib.util
import json
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'scripts/check_config.py'
spec = importlib.util.spec_from_file_location('pulse_config', path)
config_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config_module)


class ConfigurationTest(unittest.TestCase):
    def setUp(self):
        self.config = {'SUPABASE_URL': 'https://fixture.supabase.co', 'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_fixture_public_key'}

    def test_public_and_complete_optional_configuration(self):
        self.assertFalse(config_module.validate_config(self.config))
        self.config.update({key: 'fixture' for key in config_module.FIREBASE})
        self.assertTrue(config_module.validate_config(self.config))

    def test_rejects_private_role_and_user_tokens(self):
        for role in ['service_role', 'authenticated']:
            encoded = base64.urlsafe_b64encode(json.dumps({'role': role}).encode()).decode().rstrip('=')
            self.config['SUPABASE_PUBLISHABLE_KEY'] = f'fixture.{encoded}.fixture'
            with self.assertRaises(ValueError): config_module.validate_config(self.config)

    def test_rejects_server_fields_and_partial_firebase(self):
        self.config['SUPABASE_SERVICE_ROLE_KEY'] = 'fixture'
        with self.assertRaises(ValueError): config_module.validate_config(self.config)
        del self.config['SUPABASE_SERVICE_ROLE_KEY']
        self.config['FIREBASE_API_KEY'] = 'fixture'
        with self.assertRaises(ValueError): config_module.validate_config(self.config)

    def test_rejects_unsafe_origins(self):
        for url in ['http://fixture.supabase.co', 'https://user:pass@fixture.supabase.co', 'https://fixture.supabase.co?token=fixture']:
            self.config['SUPABASE_URL'] = url
            with self.assertRaises(ValueError): config_module.validate_config(self.config)


if __name__ == '__main__': unittest.main()
