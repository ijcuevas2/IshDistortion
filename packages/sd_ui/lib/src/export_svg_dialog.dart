import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';

/// §11's "Export Plain SVG" dialog: type (or accept the suggested) output
/// file path and Export to write the document's `sd:*`-stripped, portable
/// SVG serialization there via `writeSdDocument(..., mode:
/// SdSaveMode.plain)` — the same underlying function/mode
/// [SaveDocumentDialog] already ships, tested there in Phase 1
/// (`svg_round_trip_test.dart` et al.), just with `SdSaveMode.plain`
/// instead of the default `SdSaveMode.native`. Pure Dart string
/// serialization plus a plain synchronous file write, the same as
/// [SaveDocumentDialog] — no external process involved, so no
/// `Isolate.run`/injectable-seam concern here either.
///
/// Pops with the exported path on success, or `null` on Cancel.
class ExportSvgDialog extends StatefulWidget {
  const ExportSvgDialog({
    super.key,
    required this.document,
    this.suggestedPath,
  });

  final SdDocument document;

  /// Defaults to `<current working directory>/diagram-plain.svg` when
  /// omitted — desktop-only, so there's no permissions concern reading
  /// it, and a text field the user can freely edit either way. Named
  /// differently from [SaveDocumentDialog]'s own `diagram.svg` default so
  /// exporting plain SVG next to an already-saved native one doesn't
  /// silently overwrite it.
  final String? suggestedPath;

  @override
  State<ExportSvgDialog> createState() => _ExportSvgDialogState();
}

class _ExportSvgDialogState extends State<ExportSvgDialog> {
  late final _controller = TextEditingController(
    text: widget.suggestedPath ?? '${Directory.current.path}/diagram-plain.svg',
  )..addListener(() => setState(() {}));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _export() {
    final path = _controller.text.trim();
    if (path.isEmpty) return;
    try {
      File(path).writeAsStringSync(
        writeSdDocument(widget.document, mode: SdSaveMode.plain),
      );
      Navigator.of(context).pop(path);
    } on FileSystemException catch (e) {
      setState(
        () => _error =
            'Could not write to this path: ${e.osError?.message ?? e.message}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _controller.text.trim();
    return AlertDialog(
      title: const Text('Export Plain SVG'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Strips all SigmaDraw-specific data, so the file opens '
              'identically everywhere but no longer reopens with full '
              'semantics in SigmaDraw itself.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'File path',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: path.isEmpty ? null : _export,
          child: const Text('Export'),
        ),
      ],
    );
  }
}
