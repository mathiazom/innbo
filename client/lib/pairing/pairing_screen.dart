import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../device_credentials.dart';

class PairingScreen extends StatefulWidget {
  final void Function(DeviceCredentials credentials) onPaired;

  const PairingScreen({super.key, required this.onPaired});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _powerSyncUrlController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _serverUrlController.dispose();
    _powerSyncUrlController.dispose();
    _codeController.dispose();
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
        body: jsonEncode({'code': _codeController.text.trim()}),
      );

      if (response.statusCode != 200) {
        setState(() => _error = 'Ugyldig eller utløpt paringskode.');
        return;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final credentials = DeviceCredentials(
        serverUrl: serverUrl,
        powerSyncUrl: _powerSyncUrlController.text.trim(),
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
                controller: _powerSyncUrlController,
                decoration: const InputDecoration(
                  labelText: 'PowerSync-adresse',
                  hintText: 'https://sync.innbo.eksempel.no',
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
