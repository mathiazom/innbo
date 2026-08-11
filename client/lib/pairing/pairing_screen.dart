import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../device_credentials.dart';
import 'pairing_link.dart';
import 'qr_scan_screen.dart';

class PairingScreen extends StatefulWidget {
  final void Function(DeviceCredentials credentials) onPaired;
  final PairingLinkData? initialPairingLink;

  const PairingScreen({
    super.key,
    required this.onPaired,
    this.initialPairingLink,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = widget.initialPairingLink?.serverUrl ?? '';
    _codeController.text = widget.initialPairingLink?.code ?? '';
    _fillDefaultDeviceName();
  }

  Future<void> _fillDefaultDeviceName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final name = Platform.isAndroid
          ? (await deviceInfo.androidInfo).model
          : (await deviceInfo.macOsInfo).modelName;
      if (mounted && _nameController.text.isEmpty) {
        setState(() => _nameController.text = name);
      }
    } catch (e) {
      debugPrint('Could not read device name: $e');
    }
  }

  Future<void> _scanQrCode() async {
    final data = await Navigator.of(context).push<PairingLinkData>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (data == null) return;
    setState(() {
      if (data.serverUrl != null) _serverUrlController.text = data.serverUrl!;
      if (data.code != null) _codeController.text = data.code!;
    });
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final serverUrl = _serverUrlController.text.trim();
    try {
      final uri = Uri.parse(serverUrl).resolve('/pairing/exchange');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': _codeController.text.trim(),
          'name': _nameController.text.trim(),
          'platform': Platform.isAndroid ? 'android' : 'macos',
        }),
      );

      if (response.statusCode != 200) {
        setState(() => _error = 'Ugyldig eller utløpt paringskode.');
        return;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final credentials = DeviceCredentials(
        serverUrl: serverUrl,
        powerSyncUrl: body['powersync_url'] as String,
        deviceId: body['device_id'] as String,
        deviceSecret: body['device_secret'] as String,
      );
      await credentials.save();
      widget.onPaired(credentials);
    } catch (e, st) {
      debugPrint('Pairing failed: $e\n$st');
      setState(() => _error = 'Kunne ikke koble til serveren.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Koble til Innbo-server')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (Platform.isAndroid) ...[
                FilledButton.icon(
                  onPressed: _loading ? null : _scanQrCode,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Skann QR-kode'),
                ),
                const SizedBox(height: 24),
              ],
              TextFormField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'Server-adresse',
                  hintText: 'https://innbo.eksempel.no',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Påkrevd' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Paringskode'),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Påkrevd' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Enhetsnavn',
                  hintText: 'F.eks. Ola sin telefon',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Påkrevd' : null,
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Koble til'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
