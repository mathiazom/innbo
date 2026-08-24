import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';

import '../client_version.dart';
import '../device_credentials.dart';

/// Bridges PowerSync to the Go backend (see backend/internal/httpapi):
/// fetchCredentials() exchanges the device's long-lived pairing credential
/// for a short-lived PowerSync JWT via POST /token; uploadData() pushes the
/// local write queue to POST /upload.
class InnboBackendConnector extends PowerSyncBackendConnector {
  final DeviceCredentials credentials;
  final PowerSyncDatabase database;

  /// Called when the backend rejects this app version as mismatched (HTTP
  /// 426) — from fetchCredentials()'s /token call, or from uploadData()'s
  /// /upload call if a still-valid token outlives a version bump made
  /// after it was minted. See lib/sync/unsynced_changes_guard.dart and
  /// docs/adr/0004-schema-migration-strategy.md.
  final Future<void> Function(PowerSyncDatabase database) onUpdateRequired;

  InnboBackendConnector({
    required this.credentials,
    required this.database,
    required this.onUpdateRequired,
  });

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final uri = Uri.parse(credentials.serverUrl).resolve('/token');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'device_id': credentials.deviceId,
        'device_secret': credentials.deviceSecret,
        'client_version': kClientVersion,
      }),
    );

    if (response.statusCode == 426) {
      await onUpdateRequired(database);
      return null;
    }
    if (response.statusCode != 200) {
      throw http.ClientException(
        'token request failed (${response.statusCode})',
        uri,
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PowerSyncCredentials(
      endpoint: credentials.powerSyncUrl,
      token: body['token'] as String,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final batch = await database.getCrudBatch();
    if (batch == null) return;

    final creds = await getCredentialsCached();
    if (creds == null) {
      throw StateError('no PowerSync credentials available for upload');
    }

    final uri = Uri.parse(credentials.serverUrl).resolve('/upload');
    final ops = batch.crud
        .map(
          (entry) => {
            'op': entry.op.toJson(),
            'table': entry.table,
            'id': entry.id,
            if (entry.opData != null) 'data': entry.opData,
          },
        )
        .toList();

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${creds.token}',
        'X-Client-Version': '$kClientVersion',
      },
      body: jsonEncode(ops),
    );

    if (response.statusCode == 426) {
      await onUpdateRequired(database);
      return;
    }
    if (response.statusCode == 401) {
      invalidateCredentials();
    }
    if (response.statusCode != 204) {
      throw http.ClientException(
        'upload failed (${response.statusCode}): ${response.body}',
        uri,
      );
    }

    await batch.complete();
  }
}
