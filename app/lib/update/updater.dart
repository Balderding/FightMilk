import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../version.dart';

/// App updates from the project's GitHub releases. Only when the person asks (or switched on the
/// start-up check). Each release publishes SHA256SUMS.txt; the APK must match it, and Android
/// itself refuses any update not signed with the same key as the installed app.

class UpdateError implements Exception {
  final String message;
  UpdateError(this.message);
  @override
  String toString() => message;
}

class Update {
  final String version, notes, apkName, apkUrl, sha256;
  final int bytes;
  const Update({required this.version, required this.notes, required this.apkName, required this.apkUrl, required this.sha256, required this.bytes});
}

List<int>? _parse(String v) {
  final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(v.trim());
  return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

/// Is release [tag] newer than [current]?
bool isNewer(String tag, String current) {
  final a = _parse(tag), b = _parse(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// The APK for this phone's processor, else the universal one.
String? pickApk(List<String> names, String abi) {
  final want = switch (abi) { 'arm64-v8a' => '-arm64.apk', 'armeabi-v7a' => '-armv7.apk', 'x86_64' => '-x86_64.apk', _ => '' };
  final apks = names.where((n) => n.endsWith('.apk')).toList();
  if (want.isNotEmpty) {
    final hit = apks.where((n) => n.endsWith(want)).firstOrNull;
    if (hit != null) return hit;
  }
  return apks.where((n) => n.endsWith('-universal.apk')).firstOrNull;
}

/// Returns the newer release for this phone, or null when the app is up to date.
Future<Update?> checkUpdate(http.Client c, String abi) async {
  final http.Response r;
  try {
    r = await c.get(Uri.parse('https://api.github.com/repos/$appRepo/releases/latest'), headers: {'accept': 'application/vnd.github+json'});
  } catch (_) {
    throw UpdateError('Could not reach GitHub. Check your connection.');
  }
  if (r.statusCode == 404) return null; // nothing published yet
  if (r.statusCode != 200) throw UpdateError('GitHub answered ${r.statusCode}. Try again later.');
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(r.body) as Map<String, dynamic>;
  } catch (_) {
    throw UpdateError('GitHub sent something unexpected.');
  }
  final tag = (j['tag_name'] ?? '') as String;
  if (!isNewer(tag, appVersion)) return null;
  final assets = (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
  final name = pickApk([for (final a in assets) a['name'] as String], abi);
  final sums = assets.where((a) => a['name'] == 'SHA256SUMS.txt').firstOrNull;
  if (name == null) throw UpdateError('Version ${tag.replaceFirst('v', '')} has no app file for this phone.');
  if (sums == null) throw UpdateError('Version ${tag.replaceFirst('v', '')} has no fingerprint list, so it is not installed.');
  final http.Response s;
  try {
    s = await c.get(Uri.parse(sums['browser_download_url'] as String));
  } catch (_) {
    throw UpdateError('Could not download the fingerprint list.');
  }
  final line = s.body.split('\n').map((l) => l.trim()).where((l) => l.endsWith(' $name') || l.endsWith('*$name')).firstOrNull;
  final sum = line == null ? null : RegExp(r'^[0-9a-f]{64}').firstMatch(line)?.group(0);
  if (sum == null) throw UpdateError('The fingerprint list does not cover $name, so it is not installed.');
  final a = assets.firstWhere((x) => x['name'] == name);
  return Update(
    version: tag.replaceFirst(RegExp('^v'), ''),
    notes: (j['body'] ?? '') as String,
    apkName: name,
    apkUrl: a['browser_download_url'] as String,
    sha256: sum,
    bytes: (a['size'] ?? 0) as int,
  );
}

/// Downloads the APK into [dir] and checks it. Returns the file path, ready for the installer.
Future<String> downloadUpdate(Update u, http.Client c, String dir, {void Function(double)? onProgress}) async {
  Directory(dir).createSync(recursive: true);
  final out = File(p.join(dir, u.apkName));
  final part = File('${out.path}.part');
  final http.StreamedResponse res;
  try {
    res = await c.send(http.Request('GET', Uri.parse(u.apkUrl)));
  } catch (_) {
    throw UpdateError('Could not download the update. Check your connection.');
  }
  if (res.statusCode != 200) throw UpdateError('The download failed (error ${res.statusCode}).');
  final sink = part.openWrite();
  var got = 0;
  try {
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (u.bytes > 0) onProgress?.call(got / u.bytes);
    }
  } catch (_) {
    await sink.close();
    part.deleteSync();
    throw UpdateError('The connection dropped. Try again.');
  }
  await sink.close();
  final digest = await sha256.bind(part.openRead()).first;
  if (digest.toString() != u.sha256) {
    part.deleteSync();
    throw UpdateError('The downloaded update did not match its fingerprint, so it was thrown away.');
  }
  if (out.existsSync()) out.deleteSync();
  part.renameSync(out.path);
  return out.path;
}
