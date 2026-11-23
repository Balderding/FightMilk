import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// F430: the last few errors, kept on this phone only, so a crash leaves a record the person can
/// look at and copy. Only the error's TYPE and its stack frames are kept, never its message: a
/// database error carries the SQL and its values (a note, an exercise name), a FormatException
/// the text it could not read (a whole row). Photo file names are taken out of the frames. The
/// log is its own file in the app's private folder: never in the settings table, so never in a
/// backup, an export or an AI request. Nothing is sent anywhere; "Copy" is the person's tap.
class CrashLog {
  CrashLog(this.file);

  /// The log file (app support folder, `crash_log.json`).
  final File file;

  static const keep = 5, maxFrames = 12, maxFrameChars = 160;

  /// The one log of the running app, once [install] ran.
  static CrashLog? current;

  /// Catches what Flutter and the platform report, records it, and lets Flutter show it as usual.
  static void install(CrashLog log) {
    current = log;
    final before = FlutterError.onError;
    FlutterError.onError = (d) {
      log.record(d.exception, d.stack).ignore();
      (before ?? FlutterError.presentError)(d);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      log.record(e, st).ignore();
      return true; // recorded; the app keeps going
    };
  }

  /// One error as it is kept: its type and its cleaned frames (no message text).
  static Map<String, dynamic> entry(Object error, StackTrace? stack, {DateTime? at}) => {
        'at': (at ?? DateTime.now()).toIso8601String().substring(0, 19),
        'type': error.runtimeType.toString(),
        'frames': [for (final l in (stack?.toString() ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(maxFrames)) cleanFrame(l)],
      };

  /// A stack frame without photo file names or anything in quotes, cut to [maxFrameChars].
  static String cleanFrame(String l) {
    var t = l.replaceAll(RegExp(r'''(["'])[^"']*\1'''), '"…"');
    t = t.replaceAll(RegExp(r'[^\s/\\]*photos[/\\][^\s:)]*', caseSensitive: false), 'photos/…');
    t = t.replaceAll(RegExp(r'[^\s/\\]+\.(jpe?g|png|heic|webp)', caseSensitive: false), '….jpg');
    return t.length > maxFrameChars ? t.substring(0, maxFrameChars) : t;
  }

  Future<List<Map<String, dynamic>>> entries() async {
    try {
      if (!await file.exists()) return [];
      final v = jsonDecode(await file.readAsString());
      return v is List ? [for (final x in v) if (x is Map) x.cast<String, dynamic>()] : [];
    } catch (_) {
      return [];
    }
  }

  /// Keeps [error] (the newest [keep]); never throws.
  Future<void> record(Object error, StackTrace? stack) async {
    try {
      final all = [...await entries(), entry(error, stack)];
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(all.length > keep ? all.sublist(all.length - keep) : all));
    } catch (_) {}
  }

  /// What the person sees and may copy: plain lines.
  Future<String> text({String header = ''}) async {
    final e = await entries();
    final b = StringBuffer(header);
    if (e.isEmpty) b.writeln('No errors recorded.');
    for (final x in e.reversed) {
      b.writeln('${x['at']}  ${x['type']}');
      for (final f in (x['frames'] as List? ?? const [])) {
        b.writeln('  $f');
      }
    }
    return b.toString();
  }

  Future<void> clear() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
