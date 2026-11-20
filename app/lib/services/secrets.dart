import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../ai/ai.dart';

/// API keys, in Android's Keystore-backed storage. Never logged, never in backups.
class Secrets {
  final _s = const FlutterSecureStorage();

  Future<String?> key(AiKind k) => _s.read(key: 'ai_key_${k.name}');

  Future<void> setKey(AiKind k, String v) => v.trim().isEmpty ? _s.delete(key: 'ai_key_${k.name}') : _s.write(key: 'ai_key_${k.name}', value: v.trim());

  Future<void> wipe() => _s.deleteAll();
}
