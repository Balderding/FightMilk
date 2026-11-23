import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../ai/ai.dart';

/// API keys, in Android's Keystore-backed storage. Never logged, never in backups.
class Secrets {
  final _s = const FlutterSecureStorage();

  Future<String?> key(AiKind k) => _s.read(key: 'ai_key_${k.name}');

  Future<void> setKey(AiKind k, String v) => v.trim().isEmpty ? _s.delete(key: 'ai_key_${k.name}') : _s.write(key: 'ai_key_${k.name}', value: v.trim());

  /// The password for locked automatic backups (batch 22): only here, never in a backup or a log.
  Future<String?> backupPassword() => _s.read(key: 'backup_pw');
  Future<void> setBackupPassword(String? v) => v == null || v.isEmpty ? _s.delete(key: 'backup_pw') : _s.write(key: 'backup_pw', value: v);

  /// The person's own server for "Send a backup to my server" (batch 22, F343). The password is
  /// kept with the server it belongs to ([forServer], see serverKey in webdav.dart) and is only
  /// ever given back for that same server, so a changed or mistyped address never gets it
  /// (review 7, P1-3).
  Future<String?> serverPassword(String forServer) async {
    final pw = await _s.read(key: 'webdav_pw');
    return pw != null && await _s.read(key: 'webdav_pw_for') == forServer ? pw : null;
  }

  Future<void> setServerPassword(String? v, {String? forServer}) async {
    if (v == null || v.isEmpty || forServer == null) {
      await _s.delete(key: 'webdav_pw');
      await _s.delete(key: 'webdav_pw_for');
    } else {
      await _s.write(key: 'webdav_pw_for', value: forServer);
      await _s.write(key: 'webdav_pw', value: v);
    }
  }

  Future<void> wipe() => _s.deleteAll();
}
