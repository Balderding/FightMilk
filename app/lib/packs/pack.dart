import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/exercise.dart';
import '../version.dart';

/// Where packs are published: the latest GitHub release of the app's repo, asset "pack.zip".
const packRepo = appRepo;

/// Public half of the pack signing key (Ed25519). Packs signed with anything else are refused.
const packPublicKeyB64 = 'FpD+EZsuL45MBzceuplIrUOUdR5c6aD9dbunuRN+U1Y=';

class PackError implements Exception {
  final String message;
  PackError(this.message);
  @override
  String toString() => message;
}

class Pack {
  final int version;
  final Map<String, List<int>> files; // path inside the pack -> bytes (icons/*.svg, exercises.json)
  final List<Exercise> exercises;
  const Pack(this.version, this.files, this.exercises);
}

bool _safePath(String s) =>
    !s.startsWith('/') && !s.contains('\\') && !s.split('/').contains('..') && (s == 'exercises.json' || RegExp(r'^icons/[a-z0-9_]+\.svg$').hasMatch(s));

/// Opens a pack zip and checks it: the manifest must carry a valid signature from our key, and
/// every file must match its SHA-256 in the manifest. Anything else is refused.
Future<Pack> verifyPack(List<int> zip, List<int> publicKey) async {
  final Archive ar;
  try {
    ar = ZipDecoder().decodeBytes(zip);
  } catch (_) {
    throw PackError('The download is not a pack.');
  }
  List<int>? get(String n) => ar.findFile(n)?.content as List<int>?;
  final manifest = get('manifest.json'), sigText = get('manifest.sig');
  if (manifest == null || sigText == null) throw PackError('The pack has no signed manifest.');
  final List<int> sig;
  try {
    sig = base64Decode(utf8.decode(sigText).trim());
  } catch (_) {
    throw PackError('The pack signature is unreadable.');
  }
  final ok = await Ed25519().verify(manifest, signature: Signature(sig, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)));
  if (!ok) throw PackError('The pack is not signed by this app\'s key. Not installed.');
  final m = jsonDecode(utf8.decode(manifest)) as Map<String, dynamic>;
  final version = m['version'];
  final files = m['files'];
  if (version is! int || files is! Map) throw PackError('The pack manifest is broken.');
  final out = <String, List<int>>{};
  for (final e in files.entries) {
    final path = e.key as String;
    if (!_safePath(path)) throw PackError('The pack has a file the app does not accept: $path');
    final bytes = get(path);
    if (bytes == null) throw PackError('The pack is missing $path.');
    if (sha256.convert(bytes).toString() != e.value) throw PackError('$path does not match the signed manifest. Not installed.');
    out[path] = bytes;
  }
  var exercises = <Exercise>[];
  if (out.containsKey('exercises.json')) {
    try {
      final j = jsonDecode(utf8.decode(out['exercises.json']!)) as Map<String, dynamic>;
      exercises = [for (final x in j['exercises'] as List) Exercise.fromJson(x as Map<String, dynamic>)];
    } catch (_) {
      throw PackError('The pack exercise list is broken.');
    }
  }
  return Pack(version, out, exercises);
}

/// Installed pack files, in the app's own storage.
class PackStore {
  final String dir;
  PackStore(this.dir);

  String get _cur => p.join(dir, 'packs', 'current');

  int installedVersion() {
    final f = File(p.join(_cur, 'version'));
    return f.existsSync() ? int.tryParse(f.readAsStringSync().trim()) ?? 0 : 0;
  }

  /// Installs if newer than what's there. Writes to a temp folder first, then swaps it in.
  Future<bool> install(Pack pack) async {
    if (pack.version <= installedVersion()) return false;
    final tmp = Directory(p.join(dir, 'packs', 'incoming'));
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    for (final e in pack.files.entries) {
      final f = File(p.join(tmp.path, e.key));
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(e.value);
    }
    File(p.join(tmp.path, 'version')).writeAsStringSync('${pack.version}');
    final cur = Directory(_cur);
    if (cur.existsSync()) cur.deleteSync(recursive: true);
    tmp.renameSync(cur.path);
    return true;
  }

  String? iconPath(String icon) {
    final f = File(p.join(_cur, 'icons', '$icon.svg'));
    return f.existsSync() ? f.path : null;
  }

  List<Exercise> exercises() {
    final f = File(p.join(_cur, 'exercises.json'));
    if (!f.existsSync()) return const [];
    try {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return [for (final x in j['exercises'] as List) Exercise.fromJson(x as Map<String, dynamic>)];
    } catch (_) {
      return const [];
    }
  }

  void remove() {
    final cur = Directory(_cur);
    if (cur.existsSync()) cur.deleteSync(recursive: true);
  }
}

/// Asks GitHub for the latest release; downloads, verifies and installs pack.zip if newer.
/// Returns a plain sentence for the user.
Future<String> checkForPack(http.Client client, PackStore store) async {
  try {
    return await _check(client, store);
  } catch (e) {
    return 'Could not check for icons right now.';
  }
}

Future<String> _check(http.Client client, PackStore store) async {
  if (packPublicKeyB64.startsWith('REPLACED')) return 'Icon updates are not set up in this build.';
  final http.Response rel;
  try {
    rel = await client.get(Uri.parse('https://api.github.com/repos/$packRepo/releases/latest'), headers: {'accept': 'application/vnd.github+json'});
  } catch (e) {
    return 'Could not reach GitHub.';
  }
  if (rel.statusCode == 404) return 'No icon packs published yet.';
  if (rel.statusCode != 200) return 'GitHub answered ${rel.statusCode}. Try later.';
  final j = jsonDecode(rel.body) as Map<String, dynamic>;
  final asset = (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>().where((a) => a['name'] == 'pack.zip').firstOrNull;
  if (asset == null) return 'The latest release has no icon pack.';
  final http.Response dl;
  try {
    dl = await client.get(Uri.parse(asset['browser_download_url'] as String));
  } catch (_) {
    return 'Download failed. Check your connection.';
  }
  if (dl.statusCode != 200) return 'Download failed (${dl.statusCode}).';
  try {
    final pack = await verifyPack(dl.bodyBytes, base64Decode(packPublicKeyB64));
    if (!await store.install(pack)) return 'You already have the newest icons (version ${store.installedVersion()}).';
    return 'Installed icon pack version ${pack.version}.';
  } on PackError catch (e) {
    return e.message;
  }
}
