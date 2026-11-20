import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Calls the app's own llama.cpp bridge (libwk_llm) on a background isolate, so the screen never
/// freezes while the model thinks. Everything happens on this phone; no network.
class LlmResult {
  final String text;
  final int status; // 0 ok, 1 prompt too long, 2 model error, 3 bad grammar, 4 hit max tokens, 9 could not load
  final String error;
  final int millis;
  const LlmResult(this.text, this.status, this.error, this.millis);
}

typedef _LoadC = Pointer<Void> Function(Pointer<Utf8>, Int32, Int32, Pointer<Utf8>, Int32);
typedef _LoadD = Pointer<Void> Function(Pointer<Utf8>, int, int, Pointer<Utf8>, int);
typedef _ChatC = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32, Float, Uint32, Pointer<Int32>);
typedef _ChatD = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, double, int, Pointer<Int32>);
typedef _FreeStrC = Void Function(Pointer<Utf8>);
typedef _FreeStrD = void Function(Pointer<Utf8>);
typedef _UnloadC = Void Function(Pointer<Void>);
typedef _UnloadD = void Function(Pointer<Void>);

String get defaultLibrary => Platform.isAndroid ? 'libwk_llm.so' : (Platform.isWindows ? 'libwk_llm.dll' : 'libwk_llm.so');

/// The phone's processor has what the engine was built for (64-bit ARM: dot-product + fp16).
bool cpuSupported() {
  if (!Platform.isAndroid) return true;
  try {
    final info = File('/proc/cpuinfo').readAsStringSync();
    if (!info.contains('Features')) return true;
    if (info.contains('asimd') || info.contains('aarch64') || info.contains('AArch64')) {
      // 64-bit ARM
      return info.contains('asimddp') && info.contains('asimdhp');
    }
    return true; // x86_64 emulator / 32-bit: those builds use generic code
  } catch (_) {
    return true;
  }
}

/// True when the engine is in this build and this phone's processor can run it.
/// Screenshot/test builds can say the engine is there.
bool? engineAvailableOverride;

bool engineAvailable([String? lib]) {
  if (engineAvailableOverride != null) return engineAvailableOverride!;
  if (!cpuSupported()) return false;
  try {
    DynamicLibrary.open(lib ?? defaultLibrary);
    return true;
  } catch (_) {
    return false;
  }
}

int defaultThreads() {
  final n = Platform.numberOfProcessors;
  return n >= 8 ? 4 : (n >= 4 ? n - 1 : 2);
}

Future<LlmResult> runLocal({
  required String modelPath,
  required String system,
  required String user,
  String? grammar,
  int maxTokens = 600,
  double temperature = 0.4,
  int seed = 42,
  int nCtx = 4096,
  int? threads,
  String? library,
}) {
  final lib = library ?? defaultLibrary;
  final th = threads ?? defaultThreads();
  return Isolate.run(() => _run(lib, modelPath, system, user, grammar, maxTokens, temperature, seed, nCtx, th));
}

LlmResult _run(String libPath, String model, String system, String user, String? grammar, int maxTokens, double temp, int seed, int nCtx, int threads) {
  final sw = Stopwatch()..start();
  final DynamicLibrary dl;
  try {
    dl = DynamicLibrary.open(libPath);
  } catch (e) {
    return LlmResult('', 9, 'The on-phone AI engine is not in this build for this phone.', 0);
  }
  final load = dl.lookupFunction<_LoadC, _LoadD>('wk_load');
  final chat = dl.lookupFunction<_ChatC, _ChatD>('wk_chat');
  final freeStr = dl.lookupFunction<_FreeStrC, _FreeStrD>('wk_free_str');
  final unload = dl.lookupFunction<_UnloadC, _UnloadD>('wk_unload');

  final pModel = model.toNativeUtf8();
  final err = calloc<Uint8>(256).cast<Utf8>();
  final pSys = system.toNativeUtf8();
  final pUser = user.toNativeUtf8();
  final pGram = grammar == null ? nullptr.cast<Utf8>() : grammar.toNativeUtf8();
  final status = calloc<Int32>();
  try {
    final h = load(pModel, nCtx, threads, err, 256);
    if (h == nullptr) return LlmResult('', 9, err.toDartString(), sw.elapsedMilliseconds);
    try {
      final out = chat(h, pSys, pUser, pGram, maxTokens, temp, seed, status);
      final text = out == nullptr ? '' : out.toDartString();
      if (out != nullptr) freeStr(out);
      return LlmResult(text, status.value, '', sw.elapsedMilliseconds);
    } finally {
      unload(h);
    }
  } finally {
    for (final p in [pModel, pSys, pUser]) {
      calloc.free(p);
    }
    if (grammar != null) calloc.free(pGram);
    calloc.free(err);
    calloc.free(status);
  }
}
