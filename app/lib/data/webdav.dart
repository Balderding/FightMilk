import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../net/guarded_client.dart' show NetBlocked;
import 'backup.dart';
import 'repo.dart';

/// "Send a backup to my server" (batch 22, F343): the person's own WebDAV or Nextcloud folder.
/// Only when they tap it, never by itself. HTTPS only. The server password lives in Android's
/// secure storage, never in a backup, the settings or a log. The address and user are kept in
/// kv 'webdav' (on the phone only; not in a backup).

class ServerConfig {
  final String url; // the folder, e.g. https://cloud.example.org/remote.php/dav/files/me/Backups
  final String user;
  const ServerConfig(this.url, this.user);
  Map<String, dynamic> toJson() => {'url': url, 'user': user};
  factory ServerConfig.fromJson(Map<String, dynamic> j) => ServerConfig((j['url'] ?? '') as String, (j['user'] ?? '') as String);
}

/// Who a server password belongs to: scheme, host (any case), port and user (review 7, P1-3).
String serverKey(ServerConfig c) {
  final u = Uri.tryParse(c.url.trim());
  if (u == null || u.host.isEmpty) return '';
  return '${u.scheme.toLowerCase()}://${u.host.toLowerCase()}:${u.hasPort ? u.port : (u.scheme.toLowerCase() == 'https' ? 443 : 80)}|${c.user.trim()}';
}

/// Null when [url] can be used, else why not in plain words.
String? checkServerUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) return 'That is not a web address.';
  if (u.scheme == 'http') return 'Only https:// addresses: over http:// the backup and your password would travel unprotected.';
  if (u.scheme != 'https') return 'The address must start with https://';
  if (u.userInfo.isNotEmpty) return 'Put the user name in its own box, not in the address.';
  // a ? or # part would push the folder path out of the address (review 7, P3-4)
  if (u.hasQuery || u.hasFragment) return 'Leave out the part after ? or #: the address is the folder only.';
  return null;
}

/// The name a backup gets on the server, worked out once, so the confirm shows the real one
/// (review 7, P3-6).
String serverFileName(DateTime at, {required bool locked}) => 'fightmilk-backup-${at.toIso8601String().substring(0, 19).replaceAll(':', '')}${locked ? '.locked' : ''}.json';

/// Where a file named [name] goes: the folder address plus the name.
Uri serverTarget(ServerConfig c, String name) {
  final base = c.url.trim().endsWith('/') ? c.url.trim() : '${c.url.trim()}/';
  return Uri.parse(base).resolve(Uri.encodeComponent(name));
}

Future<ServerConfig?> loadServer(Repo r) async {
  try {
    final v = await r.kvGet('webdav');
    return v == null ? null : ServerConfig.fromJson(jsonDecode(v) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

Future<void> saveServer(Repo r, ServerConfig? c) => c == null ? r.db.delete('kv', where: 'k = ?', whereArgs: ['webdav']) : r.kvSet('webdav', jsonEncode(c.toJson()));

/// Puts [bytes] on the server as [name]. A plain BackupError on any problem.
Future<void> sendToServer(http.Client client, ServerConfig c, String password, String name, Uint8List bytes) async {
  final bad = checkServerUrl(c.url);
  if (bad != null) throw BackupError(bad);
  final target = serverTarget(c, name);
  http.Response res;
  try {
    res = await client
        .put(target, headers: {'Authorization': 'Basic ${base64.encode(utf8.encode('${c.user}:$password'))}', 'Content-Type': 'application/json'}, body: bytes)
        .timeout(const Duration(seconds: 90));
  } on NetBlocked {
    // the guard let nothing out: say that, not "could not be reached" (review 7, P3-5)
    throw BackupError('The app did not send it: only the server you set up may be sent to. Set the server up again in Settings → Backup.');
  } catch (e) {
    throw BackupError('The server could not be reached (${target.host}). Check the address and your connection.');
  }
  if (res.statusCode == 401 || res.statusCode == 403) throw BackupError('The server said the user name or password is wrong.');
  if (res.statusCode == 404 || res.statusCode == 409) throw BackupError('The server has no folder at that address. Make the folder first, or check the address.');
  if (res.statusCode == 507) throw BackupError('The server is full.');
  if (res.statusCode < 200 || res.statusCode >= 300) throw BackupError('The server did not take the backup (it answered ${res.statusCode}).');
}
