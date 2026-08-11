/// Parsed contents of an `innbo://pair` link, as printed by
/// `bootstrap-pairing` (see backend/cmd/server/cli.go) and produced by
/// scanning that QR code, whether via the in-app scanner or the OS
/// handing the app an incoming deep link.
class PairingLinkData {
  final String? serverUrl;
  final String? code;

  const PairingLinkData({this.serverUrl, this.code});
}

/// Parses `innbo://pair?url=<url>&code=<code>` (url is optional — omitted
/// when the server has no PUBLIC_URL configured). Returns null if [raw]
/// isn't a recognized pairing link.
PairingLinkData? parsePairingLink(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'innbo' || uri.host != 'pair') {
    return null;
  }
  final url = uri.queryParameters['url'];
  final code = uri.queryParameters['code'];
  if (url == null && code == null) return null;
  return PairingLinkData(serverUrl: url, code: code);
}
