import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Shows an "about" dialog with the running client's version (from
/// pubspec.yaml in release builds, a "dev" placeholder otherwise — matching
/// the server's own fallback in backend/internal/httpapi/version.go) and the
/// paired server's version (fetched from GET /version, "utilgjengelig" if
/// unreachable).
Future<void> showAboutAppDialog(BuildContext context, String serverUrl) async {
  final clientVersion = kReleaseMode
      ? (await PackageInfo.fromPlatform()).version
      : 'dev';
  final serverVersion = _fetchServerVersion(serverUrl);

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Om Innbo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Klientversjon: $clientVersion'),
          FutureBuilder<String>(
            future: serverVersion,
            builder: (context, snapshot) {
              final text = switch (snapshot.connectionState) {
                ConnectionState.done => snapshot.data ?? 'utilgjengelig',
                _ => 'laster …',
              };
              return Text('Serverversjon: $text');
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Lukk'),
        ),
      ],
    ),
  );
}

Future<String> _fetchServerVersion(String serverUrl) async {
  try {
    final uri = Uri.parse(serverUrl).resolve('/version');
    final response = await http.get(uri).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) throw Exception('bad status');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['version'] as String;
  } catch (_) {
    return 'utilgjengelig';
  }
}
