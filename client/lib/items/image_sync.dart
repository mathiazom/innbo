import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart' show FileImage, PaintingBinding;
import 'package:http/http.dart' as http;

import '../client_version.dart';
import '../device_credentials.dart';
import 'image_store.dart';

/// Applied to every request in this file. Without it, a request that
/// hangs (e.g. the backend/PowerSync mid-restart) never completes — and
/// since _ensureLocal caches Futures in a static map for the app's
/// lifetime, one stuck request permanently wedges every future tap on
/// that image until the app itself is restarted.
const _requestTimeout = Duration(seconds: 10);

/// Uploads/downloads the binary bytes for an `image` row (see
/// backend/internal/httpapi/images.go) — the row's metadata syncs
/// separately through the ordinary PowerSync path (schema.dart's `image`
/// Table), this only ever moves bytes for an id both sides already agree
/// on.
class ImageSync {
  /// ensureLocal* calls, keyed by "$imageId:$variant" — both a dedup
  /// (see below) and, for successful results, a permanent cache.
  ///
  /// The list and detail screens rebuild on every PowerSync checkpoint
  /// (which fires continuously, independent of whether these rows
  /// changed), and each rebuild calls ensureLocal* again inline in
  /// build(). FutureBuilder resets to "waiting" whenever it's given a
  /// *new* Future instance, even if the previous one already resolved —
  /// so without caching successful results here, a real network fetch
  /// (unlike a same-device local-file check, which resolves fast enough
  /// this was never observed) can lose its rendered result to the very
  /// next rebuild before anyone sees it. These images are immutable
  /// once written, so caching a success forever is correct, not just
  /// convenient. A null (failure) result is evicted so a later rebuild
  /// gets to retry rather than being stuck with a cached failure.
  static final Map<String, Future<File?>> _cache = {};

  /// Mirrors InnboBackendConnector.fetchCredentials()'s POST /token call
  /// (lib/powersync/backend_connector.dart), kept independent rather than
  /// reaching into the PowerSync connector's cached credentials (not
  /// exposed outside main.dart today) — one extra token round-trip per
  /// image action is cheap and keeps this decoupled.
  static Future<String?> _fetchToken(DeviceCredentials credentials) async {
    try {
      final uri = Uri.parse(credentials.serverUrl).resolve('/token');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'device_id': credentials.deviceId,
              'device_secret': credentials.deviceSecret,
              'client_version': kClientVersion,
            }),
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['token'] as String;
    } catch (_) {
      return null;
    }
  }

  /// Uploads the locally-saved full-res file for [imageId]. Returns
  /// whether it succeeded — callers show their own manual-retry affordance
  /// on failure rather than this queuing anything itself.
  static Future<bool> uploadFull(
    DeviceCredentials credentials,
    String imageId,
  ) async {
    final file = await ImageStore.localFullFile(imageId);
    if (!await file.exists()) {
      debugPrint('ImageSync.uploadFull($imageId): no local file, skipping');
      return false;
    }

    final token = await _fetchToken(credentials);
    if (token == null) {
      debugPrint('ImageSync.uploadFull($imageId): failed to fetch token');
      return false;
    }

    try {
      final uri = Uri.parse(credentials.serverUrl).resolve('/images/$imageId');
      final response = await http
          .put(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'X-Client-Version': '$kClientVersion',
            },
            body: await file.readAsBytes(),
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 204) {
        debugPrint(
          'ImageSync.uploadFull($imageId): server returned '
          '${response.statusCode}: ${response.body}',
        );
      }
      return response.statusCode == 204;
    } catch (e) {
      debugPrint('ImageSync.uploadFull($imageId): $e');
      return false;
    }
  }

  /// The device that captured a photo already has the full-res original
  /// locally — it should never need the network just to show its own
  /// photo's thumbnail. Only a device that never had this image at all
  /// (someone else's photo it hasn't downloaded) needs to fetch the
  /// small server-generated thumbnail.
  static Future<File?> ensureLocalThumbnail(
    DeviceCredentials credentials,
    String imageId,
  ) async {
    final full = await ImageStore.localFullFile(imageId);
    if (await full.exists() && await full.length() > 0) return full;
    return _ensureLocal(
      credentials,
      imageId,
      'thumbnail',
      ImageStore.localThumbFile,
    );
  }

  static Future<File?> ensureLocalFull(
    DeviceCredentials credentials,
    String imageId,
  ) => _ensureLocal(credentials, imageId, 'full', ImageStore.localFullFile);

  static Future<File?> _ensureLocal(
    DeviceCredentials credentials,
    String imageId,
    String variant,
    Future<File> Function(String id) localFile,
  ) {
    final key = '$imageId:$variant';
    return _cache[key] ??= _fetchLocal(credentials, imageId, variant, localFile)
      ..then((file) {
        if (file == null) _cache.remove(key);
      });
  }

  static Future<File?> _fetchLocal(
    DeviceCredentials credentials,
    String imageId,
    String variant,
    Future<File> Function(String id) localFile,
  ) async {
    final file = await localFile(imageId);
    // A zero-length file is a leftover from an interrupted/corrupted
    // write, never a genuine empty image — treat it as missing so it
    // self-heals by re-fetching, instead of getting stuck forever.
    if (await file.exists() && await file.length() > 0) return file;

    final token = await _fetchToken(credentials);
    if (token == null) return null;

    try {
      final uri = Uri.parse(
        credentials.serverUrl,
      ).resolve('/images/$imageId/$variant');

      // The row's metadata syncs via PowerSync almost instantly, but the
      // byte upload (a whole file, over the network) takes longer — so a
      // 404 right after a row first appears usually just means "not
      // uploaded yet", not "never will be". A few short retries covers
      // that gap without the caller needing its own rebuild-and-retry
      // machinery; a 404 that outlives this budget is treated as
      // missing, same as before.
      http.Response? response;
      for (var attempt = 0; attempt < 5; attempt++) {
        response = await http
            .get(
              uri,
              headers: {
                'Authorization': 'Bearer $token',
                'X-Client-Version': '$kClientVersion',
              },
            )
            .timeout(_requestTimeout);
        if (response.statusCode != 404) break;
        await Future.delayed(const Duration(milliseconds: 700));
      }
      if (response == null || response.statusCode != 200) return null;

      // Write-then-rename so a reader never sees a partially-written
      // file: rename is atomic on the same filesystem, unlike
      // writeAsBytes (which truncates in place).
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(response.bodyBytes);
      await tmp.rename(file.path);
      // Image.file/FileImage caches decoded images by file path, not
      // content. If an earlier attempt ever wrote bad/empty bytes to
      // this same path (e.g. before the atomic write above existed),
      // Flutter would otherwise keep serving that stale cached decode
      // forever, even though the file on disk is now correct.
      PaintingBinding.instance.imageCache.evict(FileImage(file));
      return file;
    } catch (_) {
      return null;
    }
  }
}
