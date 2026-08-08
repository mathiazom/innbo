import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import 'device_credentials.dart';
import 'pairing/pairing_screen.dart';
import 'powersync/backend_connector.dart';
import 'powersync/schema.dart';
import 'rooms/room_list_screen.dart';
import 'sync/unsynced_changes_guard.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InnboApp());
}

class InnboApp extends StatefulWidget {
  const InnboApp({super.key});

  @override
  State<InnboApp> createState() => _InnboAppState();
}

class _InnboAppState extends State<InnboApp> {
  PowerSyncDatabase? _db;
  DeviceCredentials? _credentials;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
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
                : PairingScreen(onPaired: _onPaired)),
    );
  }
}
