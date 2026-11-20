import 'package:flutter/services.dart';

/// Chat apps the request can be handed to. The person's own subscription is used there; this app
/// sends nothing itself.
const chatApps = {
  'com.anthropic.claude': 'Claude',
  'com.openai.chatgpt': 'ChatGPT',
  'com.google.android.apps.bard': 'Gemini',
  '': 'Share menu',
};

const _ch = MethodChannel('workout/handoff');

/// Copies [text] to the clipboard and opens [package] with it (or the share menu).
/// Returns 'app', 'chooser', 'missing' (that app isn't installed, share menu shown) or 'failed'.
Future<String> handOff(String text, String package) async {
  await Clipboard.setData(ClipboardData(text: text));
  try {
    return (await _ch.invokeMethod<String>('send', {'text': text, 'package': package})) ?? 'failed';
  } catch (_) {
    return 'failed';
  }
}

Future<String?> pasteText() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;
