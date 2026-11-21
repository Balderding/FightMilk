import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// A model the app can run on the phone. Pinned to an exact Hugging Face commit and fingerprinted,
/// so the file can't change under us.
class ModelInfo {
  final String id, label, file, url, sha256, note;
  final int bytes;

  /// A file the person copies onto the phone themselves (no download, any size).
  final bool importOnly;
  const ModelInfo({required this.id, required this.label, required this.file, required this.url, required this.sha256, required this.bytes, required this.note, this.importOnly = false});
  String get size => sizeText(bytes);
}

String sizeText(int bytes) => bytes >= 1e9 ? '${(bytes / 1e9).toStringAsFixed(1)} GB' : '${(bytes / 1e6).round()} MB';

const modelCatalog = [
  ModelInfo(
    id: 'lfm2.5-1.2b-instruct',
    label: 'LFM2.5 1.2B (recommended)',
    file: 'LFM2.5-1.2B-Instruct-Q4_0.gguf',
    url: 'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/8ed288026e23958ad9dfa92d53ed773a8eee7125/LFM2.5-1.2B-Instruct-Q4_0.gguf',
    sha256: '2ea801949d760cdf1a2cc04a54262c22c3c0c54f0769d57760c9adeb0e59233f',
    bytes: 695751488,
    note: 'Fast, runs on most phones with 4 GB of memory or more.',
  ),
  ModelInfo(
    id: 'lfm2.5-2.6b',
    label: 'LFM2.5 2.6B (smarter, slower)',
    file: 'LFM2.5-2.6B-Q4_0.gguf',
    url: 'https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/resolve/e7caca5d835a3901a8e0d63e94009429bafafdfc/LFM2.5-2.6B-Q4_0.gguf',
    sha256: 'e1a61bf937bc60726e18626e97f7ee9bfd2574d95744c2ed909de98b78006fbe',
    bytes: 1593894912,
    note: 'Better answers; needs a newer phone with 8 GB of memory or more.',
  ),
  ModelInfo(
    id: 'own-model',
    label: 'My own model file',
    file: 'own-model.gguf',
    url: '',
    sha256: '',
    bytes: 0,
    note: 'A .gguf model you copy onto this phone yourself, for example a coach you trained. It gets the same prompts as LFM2.5 1.2B.',
    importOnly: true,
  ),
];

ModelInfo modelById(String id) => modelCatalog.firstWhere((m) => m.id == id, orElse: () => modelCatalog.first);

class ModelError implements Exception {
  final String message;
  ModelError(this.message);
  @override
  String toString() => message;
}

/// Models live in the app's own storage. Downloads resume after a break and are checked against
/// the fingerprint before use; a wrong file is thrown away.
class ModelStore {
  final String dir;
  ModelStore(String base) : dir = p.join(base, 'models');

  String pathOf(ModelInfo m) => p.join(dir, m.file);

  bool isReady(ModelInfo m) {
    final f = File(pathOf(m));
    return f.existsSync() && (m.importOnly ? f.lengthSync() > 1000000 : f.lengthSync() == m.bytes);
  }

  /// Size on the phone (imported files have no fixed size).
  int sizeOf(ModelInfo m) => m.importOnly ? (isReady(m) ? File(pathOf(m)).lengthSync() : 0) : m.bytes;

  /// Bytes already downloaded (finished or partial).
  int have(ModelInfo m) {
    if (m.importOnly) return 0;
    if (isReady(m)) return m.bytes;
    final part = File('${pathOf(m)}.part');
    return part.existsSync() ? part.lengthSync() : 0;
  }

  /// Checks a copied-in file (at the model path plus ".part") and puts it in place. Only GGUF model files pass.
  void finishImport(ModelInfo m) {
    final part = File('${pathOf(m)}.part');
    if (!part.existsSync()) throw ModelError('Nothing was copied.');
    final raf = part.openSync();
    final head = raf.readSync(4);
    raf.closeSync();
    if (String.fromCharCodes(head) != 'GGUF' || part.lengthSync() < 1000000) {
      part.deleteSync();
      throw ModelError('That file is not a .gguf model, so it was not used.');
    }
    final f = File(pathOf(m));
    if (f.existsSync()) f.deleteSync();
    part.renameSync(pathOf(m));
  }

  Future<void> download(ModelInfo m, http.Client client, {void Function(double)? onProgress, bool Function()? stop}) async {
    if (m.importOnly) throw ModelError('This one is not downloaded: use Import to pick the file.');
    final part = File('${pathOf(m)}.part');
    part.parent.createSync(recursive: true);
    var got = part.existsSync() ? part.lengthSync() : 0;
    if (got > m.bytes) {
      part.deleteSync();
      got = 0;
    }
    if (got < m.bytes) {
      final req = http.Request('GET', Uri.parse(m.url));
      if (got > 0) req.headers['range'] = 'bytes=$got-';
      final http.StreamedResponse res;
      try {
        res = await client.send(req);
      } catch (_) {
        throw ModelError('Could not reach Hugging Face. Check your connection; the download continues from where it stopped.');
      }
      if (res.statusCode == 200) {
        got = 0; // server sent the whole file
      } else if (res.statusCode != 206) {
        throw ModelError('The download failed (error ${res.statusCode}). Try again later.');
      }
      final sink = part.openWrite(mode: got > 0 ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          got += chunk.length;
          onProgress?.call(got / m.bytes);
          if (stop?.call() ?? false) throw ModelError('Paused. Tap Download again to continue from here.');
        }
      } on ModelError {
        await sink.close();
        rethrow;
      } catch (_) {
        await sink.close();
        throw ModelError('The connection dropped. Tap Download again to continue from where it stopped.');
      }
      await sink.close();
    }
    final digest = await sha256.bind(part.openRead()).first;
    if (digest.toString() != m.sha256) {
      part.deleteSync();
      throw ModelError('The downloaded file did not match its fingerprint, so it was thrown away. Try again.');
    }
    part.renameSync(pathOf(m));
    onProgress?.call(1.0);
  }

  /// Every downloaded or imported model (Delete all data).
  void deleteAll() {
    final d = Directory(dir);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }

  void delete(ModelInfo m) {
    for (final f in [File(pathOf(m)), File('${pathOf(m)}.part')]) {
      if (f.existsSync()) f.deleteSync();
    }
  }
}
