import 'package:http/http.dart' as http;

/// The app's whole list of places it may talk to:
///  - the AI service the user set up (only once they've set it up),
///  - GitHub, for icon/exercise pack updates, and
///  - Hugging Face, only while downloading an on-phone model the person asked for.
/// Plain http is allowed only to a home-network address (the user's own AI server).
class NetGuard {
  final String? aiHost;
  final bool models; // a model download the person started: Hugging Face and its download network

  const NetGuard({this.aiHost, this.models = false});

  static bool _modelHost(String h) => h == 'huggingface.co' || h.endsWith('.hf.co');

  static const githubHosts = {
    'github.com',
    'api.github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
    'codeload.github.com',
  };

  bool allows(Uri u) {
    final h = u.host.toLowerCase();
    if (models && _modelHost(h)) return u.scheme == 'https';
    final known = githubHosts.contains(h) || (aiHost != null && aiHost!.toLowerCase() == h);
    if (!known) return false;
    if (u.scheme == 'https') return true;
    return u.scheme == 'http' && isPrivateHost(h) && h == aiHost?.toLowerCase();
  }
}

bool isPrivateHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h == '::1' || h.endsWith('.local')) return true;
  if (h.contains(':')) {
    // IPv6: unique-local fc00::/7 and link-local fe80::/10
    final f = h.replaceAll(RegExp(r'^\[|\]$'), '');
    return RegExp(r'^f[cd][0-9a-f]{0,2}:').hasMatch(f) || RegExp(r'^fe[89ab][0-9a-f]?:').hasMatch(f);
  }
  final p = h.split('.');
  if (p.length != 4) return false;
  final n = p.map(int.tryParse).toList();
  if (n.any((x) => x == null || x < 0 || x > 255)) return false;
  final a = n[0]!, b = n[1]!;
  return a == 127 || a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) ||
      (a == 100 && b >= 64 && b <= 127) || // Tailscale / carrier-grade NAT
      (a == 169 && b == 254); // link-local
}

class NetBlocked implements Exception {
  final Uri uri;
  NetBlocked(this.uri);
  @override
  String toString() => 'Blocked: the app does not talk to ${uri.host}';
}

/// Every network call in the app goes through this. Redirects are followed by hand so each hop
/// is checked against the allow list too.
class GuardedClient extends http.BaseClient {
  final NetGuard guard;
  final http.Client _inner;

  GuardedClient(this.guard, [http.Client? inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var req = request;
    for (var hop = 0; hop < 6; hop++) {
      if (!guard.allows(req.url)) throw NetBlocked(req.url);
      final copy = _copy(req)..headers['user-agent'] = 'FightMilk'; // not the Dart version string
      final res = await _inner.send(copy);
      final loc = res.headers['location'];
      if (res.statusCode >= 300 && res.statusCode < 400 && loc != null && (req.method == 'GET' || req.method == 'HEAD')) {
        await res.stream.drain<void>();
        final next = req.url.resolve(loc);
        req = http.Request(req.method, next)..headers.addAll(_hopHeaders(req, next));
        continue;
      }
      return res;
    }
    throw http.ClientException('Too many redirects', request.url);
  }

  /// Keys never follow a redirect to another host.
  Map<String, String> _hopHeaders(http.BaseRequest r, Uri next) {
    final h = Map<String, String>.from(r.headers);
    if (next.host != r.url.host) {
      h.removeWhere((k, _) => {'authorization', 'x-api-key', 'x-goog-api-key'}.contains(k.toLowerCase()));
    }
    return h;
  }

  http.BaseRequest _copy(http.BaseRequest r) {
    if (r is http.Request) {
      return http.Request(r.method, r.url)
        ..headers.addAll(r.headers)
        ..bodyBytes = r.bodyBytes
        ..followRedirects = false;
    }
    r.followRedirects = false;
    return r;
  }

  @override
  void close() => _inner.close();
}
