// Icon/exercise pack signing.
//   dart run tool/pack_tool.dart keygen              -> ../keys/pack_key.json (private, git-ignored)
//                                                       and writes the public key into lib/packs/pack.dart
//   dart run tool/pack_tool.dart sign <dir> <version> <out.zip>
//        <dir> holds icons/*.svg and optionally exercises.json; upload out.zip to a GitHub release as "pack.zip".
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

const keyFile = '../keys/pack_key.json';

Future<void> main(List<String> a) async {
  if (a.isNotEmpty && a[0] == 'keygen') return keygen();
  if (a.length == 4 && a[0] == 'sign') return sign(a[1], int.parse(a[2]), a[3]);
  stderr.writeln('usage: keygen | sign <dir> <version> <out.zip>');
  exit(2);
}

Future<void> keygen() async {
  final f = File(keyFile);
  if (f.existsSync()) {
    stderr.writeln('$keyFile already exists - not overwriting.');
    exit(1);
  }
  final kp = await Ed25519().newKeyPair();
  final seed = await kp.extractPrivateKeyBytes();
  final pub = base64Encode((await kp.extractPublicKey()).bytes);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(jsonEncode({'seed': base64Encode(seed), 'public': pub}));
  final src = File('lib/packs/pack.dart');
  src.writeAsStringSync(src.readAsStringSync().replaceFirst(RegExp(r"const packPublicKeyB64 = '[^']*';"), "const packPublicKeyB64 = '$pub';"));
  stdout.writeln('public key: $pub');
}

Future<void> sign(String dir, int version, String out) async {
  final k = jsonDecode(File(keyFile).readAsStringSync()) as Map<String, dynamic>;
  final kp = await Ed25519().newKeyPairFromSeed(base64Decode(k['seed'] as String));
  final files = <String, List<int>>{};
  for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
    final rel = f.path.substring(dir.length + 1).replaceAll('\\', '/');
    if (rel.startsWith('icons/') && rel.endsWith('.svg') || rel == 'exercises.json') files[rel] = f.readAsBytesSync();
  }
  final manifest = utf8.encode(jsonEncode({
    'version': version,
    'files': {for (final e in files.entries) e.key: sha256.convert(e.value).toString()},
  }));
  final sig = await Ed25519().sign(manifest, keyPair: kp);
  final ar = Archive()
    ..addFile(ArchiveFile.bytes('manifest.json', manifest))
    ..addFile(ArchiveFile.bytes('manifest.sig', utf8.encode(base64Encode(sig.bytes))));
  files.forEach((k, v) => ar.addFile(ArchiveFile.bytes(k, v)));
  File(out).writeAsBytesSync(ZipEncoder().encodeBytes(ar));
  stdout.writeln('signed ${files.length} files, version $version -> $out');
}
