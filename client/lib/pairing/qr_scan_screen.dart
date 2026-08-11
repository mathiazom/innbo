import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'pairing_link.dart';

/// Full-screen camera view for scanning the QR code printed by
/// `bootstrap-pairing`. Pops with the parsed [PairingLinkData] on the
/// first recognized pairing link; ignores anything else.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final data = parsePairingLink(raw);
      if (data != null) {
        _handled = true;
        Navigator.of(context).pop(data);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Skann QR-kode')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
