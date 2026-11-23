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
  await copySensitive(text);
  try {
    return (await _ch.invokeMethod<String>('send', {'text': text, 'package': package})) ?? 'failed';
  } catch (_) {
    return 'failed';
  }
}

/// Copies [text] marked as sensitive, so keyboards' clipboard history leaves it out; Android
/// clears it after 3 minutes if it is still there. Falls back to a plain copy.
Future<void> copySensitive(String text) async {
  try {
    await _ch.invokeMethod('copy', {'text': text});
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
  }
}

/// Hands a file the person chose to export to the share menu (batch 20, F321). [path] must be
/// inside the cache's exports/ folder. Returns 'chooser' or 'failed'.
Future<String> shareFile(String path, String mime, {String title = 'Send to…'}) async {
  try {
    return (await _ch.invokeMethod<String>('shareFile', {'path': path, 'mime': mime, 'title': title})) ?? 'failed';
  } catch (_) {
    return 'failed';
  }
}

Future<String?> pasteText() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;
