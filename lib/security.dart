import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();
  static const _store = FlutterSecureStorage();
  static const _key = 'pulse.auth.session.v1';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => await _store.containsKey(key: _key);
  @override
  Future<String?> accessToken() => _store.read(key: _key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(key: _key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => _store.delete(key: _key);
}
