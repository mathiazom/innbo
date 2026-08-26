import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import 'device_credentials.dart';
import 'devices/device_status_sync.dart';
import 'items/upload_queue.dart';
import 'pairing/pairing_link.dart';
import 'pairing/pairing_screen.dart';
import 'powersync/backend_connector.dart';
import 'powersync/schema.dart';
import 'rooms/room_list_screen.dart';
import 'sync/unsynced_changes_guard.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // Caught framework errors (e.g. during build) still show today's
    // dev-mode red screen for that widget, but no longer propagate
    // past this handler — an uncaught one can otherwise force the
    // whole app to rebuild from MaterialApp.home, losing navigation.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError.onError: ${details.exception}');
    };
    runApp(const InnboApp());
  }, (error, stack) => debugPrint('runZonedGuarded: $error\n$stack'));
}

class InnboApp extends StatefulWidget {
  const InnboApp({super.key});

  @override
  State<InnboApp> createState() => _InnboAppState();
}

class _InnboAppState extends State<InnboApp> with WidgetsBindingObserver {
  PowerSyncDatabase? _db;
  DeviceCredentials? _credentials;
  bool _loading = true;
  PairingLinkData? _pendingPairingLink;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    _listenForPairingLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    super.dispose();
  }

  // Handles the "scan with the phone's stock camera app": the
  // app registers an innbo://pair intent-filter (see AndroidManifest.xml),
  // so the OS can hand us the link cold-start (getInitialLink) or while
  // already running (uriLinkStream). Ignored once already paired.
  void _listenForPairingLinks() {
    final appLinks = AppLinks();
    void handle(Uri uri) {
      if (_db != null) return;
      final data = parsePairingLink(uri.toString());
      if (data != null) setState(() => _pendingPairingLink = data);
    }

    appLinks.getInitialLink().then((uri) {
      if (uri != null) handle(uri);
    });
    _linkSubscription = appLinks.uriLinkStream.listen(handle);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final db = _db;
    final credentials = _credentials;
    if (state == AppLifecycleState.resumed &&
        db != null &&
        credentials != null &&
        db.currentStatus.hasSynced == true) {
      UploadQueue.retryDue(db, credentials);
      refreshDeviceStatus(db, credentials);
    }
  }

  Future<void> _bootstrap() async {
    final credentials = await DeviceCredentials.read();
    if (credentials != null) {
      await _connect(credentials);
    }
    setState(() => _loading = false);
  }

  Future<void> _connect(DeviceCredentials credentials) async {
    final dir = await getApplicationSupportDirectory();
    final db = PowerSyncDatabase(schema: schema, path: '${dir.path}/innbo.db');
    await db.initialize();
    await UploadQueue.ensureTable(db);
    await UploadQueue.backfill(db);

    final connector = InnboBackendConnector(
      credentials: credentials,
      database: db,
      onUpdateRequired: (database) async {
        final context = navigatorKey.currentContext;
        if (context != null) {
          await handleUpdateRequired(context, database);
        }
      },
    );
    await db.connect(connector: connector);
    UploadQueue.retryDue(db, credentials);

    setState(() {
      _db = db;
      _credentials = credentials;
    });
  }

  void _onPaired(DeviceCredentials credentials) {
    _connect(credentials);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Innbo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B4A2F)),
        useMaterial3: true,
      ),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_db != null
                ? RoomListScreen(db: _db!, credentials: _credentials!)
                : PairingScreen(
                    onPaired: _onPaired,
                    initialPairingLink: _pendingPairingLink,
                  )),
    );
  }
}
