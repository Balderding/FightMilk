import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../net/guarded_client.dart';

enum AiKind { claude, openai, gemini, local, chatApp, onDevice }

const aiKindLabel = {
  AiKind.claude: 'Claude',
  AiKind.openai: 'OpenAI',
  AiKind.gemini: 'Gemini',
  AiKind.local: 'My own server',
  AiKind.chatApp: 'Claude app (no key)',
  AiKind.onDevice: 'On this phone (LFM)',
};

/// Starting model per service; the user can type any model their account has.
const defaultModel = {
  AiKind.claude: 'claude-opus-5-5',
  AiKind.openai: 'gpt-5-mini',
  AiKind.gemini: 'gemini-2.5-flash',
  AiKind.local: '',
  AiKind.chatApp: 'com.anthropic.claude', // for the chat app, "model" holds the app to open
  AiKind.onDevice: 'lfm2.5-1.2b-instruct', // for the phone, "model" holds the model id
};

class AiConfig {
  final AiKind kind;
  final String model;
  final String? baseUrl; // local server only, e.g. http://192.168.1.20:8081

  const AiConfig({required this.kind, required this.model, this.baseUrl});

  /// Where requests go. Null when a local server has no usable address yet.
  String? get host => switch (kind) {
        AiKind.claude => 'api.anthropic.com',
        AiKind.openai => 'api.openai.com',
        AiKind.gemini => 'generativelanguage.googleapis.com',
        AiKind.local => Uri.tryParse(baseUrl ?? '')?.host.isNotEmpty == true ? Uri.parse(baseUrl!).host : null,
        AiKind.chatApp => null, // this app sends nothing; the chat app does
        AiKind.onDevice => null, // runs on the phone itself
      };

  bool get needsKey => kind != AiKind.local && kind != AiKind.chatApp && kind != AiKind.onDevice;

  /// The model runs inside the app, on the phone.
  bool get isOnDevice => kind == AiKind.onDevice;

  /// Handing the request to a chat app on the phone instead of calling a service.
  bool get isHandoff => kind == AiKind.chatApp;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'model': model, 'baseUrl': baseUrl};

  factory AiConfig.fromJson(Map<String, dynamic> j) =>
      AiConfig(kind: AiKind.values.byName(j['kind'] as String), model: (j['model'] ?? '') as String, baseUrl: j['baseUrl'] as String?);

  AiConfig copyWith({AiKind? kind, String? model, String? baseUrl}) =>
      AiConfig(kind: kind ?? this.kind, model: model ?? this.model, baseUrl: baseUrl ?? this.baseUrl);
}

/// A problem with an AI request, in plain words for the user.
class AiError implements Exception {
  final String message;
  AiError(this.message);
  @override
  String toString() => message;
}

abstract class AiProvider {
  /// [schema]: the JSON shape the answer must have (used where the service supports it).
  Future<String> complete(String system, String user, {Map<String, dynamic>? schema});
}

AiProvider providerFor(AiConfig c, String key, http.Client client) => _Safe(_provider(c, key, client));

/// Any odd reply shape becomes a plain AiError instead of a crash.
class _Safe implements AiProvider {
  final AiProvider inner;
  _Safe(this.inner);
  @override
  Future<String> complete(String system, String user, {Map<String, dynamic>? schema}) async {
    try {
      return await inner.complete(system, user, schema: schema);
    } on AiError {
      rethrow;
    } catch (_) {
      throw AiError('The AI sent an answer in a shape the app does not understand.');
    }
  }
}

AiProvider _provider(AiConfig c, String key, http.Client client) => switch (c.kind) {
      AiKind.claude => _Claude(c, key, client),
      AiKind.openai => _OpenAiCompat(c, key, client, Uri.parse('https://api.openai.com/v1/chat/completions')),
      AiKind.gemini => _Gemini(c, key, client),
      AiKind.local => _OpenAiCompat(c, key, client, _localUrl(c.baseUrl ?? '')),
      AiKind.chatApp => throw AiError('The chat app is used by hand-off, not by a request from this app.'),
      AiKind.onDevice => throw AiError('The on-phone model is run by the app directly.'),
    };

Uri _localUrl(String base) {
  var b = base.trim();
  while (b.endsWith('/')) {
    b = b.substring(0, b.length - 1);
  }
  if (b.endsWith('/v1/chat/completions')) return Uri.parse(b);
  if (b.endsWith('/v1')) return Uri.parse('$b/chat/completions');
  return Uri.parse('$b/v1/chat/completions');
}

const _timeout = Duration(minutes: 3);

Future<Map<String, dynamic>> _post(http.Client client, Uri url, Map<String, String> headers, Map<String, dynamic> body) async {
  final http.Response r;
  try {
    r = await client
        .post(url, headers: {'content-type': 'application/json', ...headers}, body: jsonEncode(body))
        .timeout(_timeout);
  } on NetBlocked {
    throw AiError('That address is not allowed. A server without https must be on your home network.');
  } on TimeoutException {
    throw AiError('The AI took too long to answer. Try again.');
  } catch (e) {
    throw AiError('Could not reach ${url.host}. Check your connection or the server address.');
  }
  Map<String, dynamic>? j;
  try {
    final d = jsonDecode(r.body);
    if (d is Map<String, dynamic>) j = d;
  } catch (_) {}
  if (r.statusCode >= 200 && r.statusCode < 300 && j == null) throw AiError('The AI service sent something that is not an answer.');
  if (r.statusCode >= 200 && r.statusCode < 300 && j != null) return j;
  final msg = _errMsg(j) ?? r.reasonPhrase ?? '';
  throw AiError(switch (r.statusCode) {
    401 || 403 => 'The service did not accept the API key. Check it in Settings. ($msg)',
    404 => 'The service does not know that model name. Check it in Settings. ($msg)',
    429 => 'The service is busy or your account is out of credit. ($msg)',
    _ => 'The AI service returned an error ${r.statusCode}. $msg',
  });
}

String? _errMsg(Map<String, dynamic>? j) {
  final e = j?['error'];
  if (e is Map && e['message'] is String) return e['message'] as String;
  if (e is String) return e;
  return null;
}

class _Claude implements AiProvider {
  final AiConfig c;
  final String key;
  final http.Client client;
  _Claude(this.c, this.key, this.client);

  /// Models that take output_config.effort and the server-side refusal fallback.
  static const _current = {'claude-opus-5-5', 'claude-opus-5', 'claude-sonnet-5-5', 'claude-fable-5-1', 'claude-fable-5-2'};

  @override
  Future<String> complete(String system, String user, {Map<String, dynamic>? schema}) async {
    final cur = _current.contains(c.model);
    final j = await _post(
      client,
      Uri.parse('https://api.anthropic.com/v1/messages'),
      {
        'x-api-key': key,
        'anthropic-version': '2026-10-21',
        if (cur) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      },
      {
        'model': c.model,
        'max_tokens': 16000,
        'system': system,
        'messages': [
          {'role': 'user', 'content': user}
        ],
        if (cur || schema != null)
          'output_config': {
            if (cur) 'effort': 'medium',
            if (schema != null) 'format': {'type': 'json_schema', 'schema': schema},
          },
        if (cur) 'fallbacks': 'default',
      },
    );
    if (j['stop_reason'] == 'refusal') throw AiError('The AI declined this request. Try rewording it.');
    final text = [
      for (final b in (j['content'] as List? ?? const []))
        if (b is Map && b['type'] == 'text') b['text'] as String
    ].join();
    if (text.trim().isEmpty) throw AiError('The AI sent back an empty answer.');
    return text;
  }
}

class _OpenAiCompat implements AiProvider {
  final AiConfig c;
  final String key;
  final http.Client client;
  final Uri url;
  _OpenAiCompat(this.c, this.key, this.client, this.url);

  @override
  Future<String> complete(String system, String user, {Map<String, dynamic>? schema}) async {
    final j = await _post(client, url, {if (key.isNotEmpty) 'authorization': 'Bearer $key'}, {
      'model': c.model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      // OpenAI itself enforces the shape; local servers vary, so they get the prompt + checks only
      if (schema != null && c.kind == AiKind.openai)
        'response_format': {
          'type': 'json_schema',
          'json_schema': {'name': 'workout', 'strict': true, 'schema': schema},
        },
    });
    final ch = j['choices'];
    String? text;
    if (ch is List && ch.isNotEmpty) {
      final m = (ch.first as Map)['message'];
      if (m is Map && m['content'] is String) text = m['content'] as String;
    }
    if (text == null || text.trim().isEmpty) throw AiError('The AI sent back an empty answer.');
    return text;
  }
}

class _Gemini implements AiProvider {
  final AiConfig c;
  final String key;
  final http.Client client;
  _Gemini(this.c, this.key, this.client);

  @override
  Future<String> complete(String system, String user, {Map<String, dynamic>? schema}) async {
    final j = await _post(
      client,
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/${Uri.encodeComponent(c.model)}:generateContent'),
      {'x-goog-api-key': key},
      {
        'systemInstruction': {
          'parts': [
            {'text': system}
          ]
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': user}
            ]
          }
        ],
        if (schema != null) 'generationConfig': {'responseMimeType': 'application/json'},
      },
    );
    final cands = j['candidates'];
    if (cands is! List || cands.isEmpty) throw AiError('The AI sent back no answer (it may have been blocked).');
    final parts = ((cands.first as Map)['content'] as Map?)?['parts'] as List? ?? const [];
    final text = [for (final p in parts) if (p is Map && p['text'] is String) p['text'] as String].join();
    if (text.trim().isEmpty) throw AiError('The AI sent back an empty answer.');
    return text;
  }
}
