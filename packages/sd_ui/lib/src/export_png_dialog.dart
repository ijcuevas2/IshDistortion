import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_export/sd_export.dart';

/// §10's Export-ribbon "PNG" dialog — the same kind of gap
/// [ExportPdfDialog]/`sd_export`'s `exportToPdf` had before that dialog
/// closed it, now for `exportToPng`.
///
/// `exportToPng` itself has no external process/`Isolate.run` to work
/// around — just `dart:ui` rendering calls tied to the calling isolate,
/// and `tester.runAsync` (Flutter's documented fix for that shape of
/// call — see the standalone `isolate-run-testwidgets-hang` memory)
/// verifies it directly in `sd_export`'s own `png_export_test.dart`. But
/// `runAsync` specifically does not mix with `tester.tap`/`pump` calls
/// inside its own callback, so a widget test *triggering* the real
/// export via a simulated button tap (as opposed to calling the
/// function directly) hits the same testability problem `ExportPdfDialog`
/// has for a different reason — `exportPng` is an injectable seam for
/// exactly that: the real pipeline is covered elsewhere, and this
/// dialog's own tests exercise its reaction to success/error via a fake.
///
/// Pops with the exported path on success, or `null` on Cancel.
class ExportPngDialog extends StatefulWidget {
  const ExportPngDialog({
    super.key,
    required this.document,
    this.suggestedPath,
    this.exportPng = exportToPng,
  });

  final SdDocument document;

  /// Defaults to `<current working directory>/diagram.png` when omitted.
  final String? suggestedPath;

  /// Injectable (default: the real `exportToPng`) — see the class doc
  /// comment on why a widget test needs this despite `exportToPng`
  /// itself having no `Isolate.run`/external process of its own.
  final Future<void> Function(SdDocument document, String outputPath) exportPng;

  @override
  State<ExportPngDialog> createState() => _ExportPngDialogState();
}

class _ExportPngDialogState extends State<ExportPngDialog> {
  late final _controller = TextEditingController(
    text: widget.suggestedPath ?? '${Directory.current.path}/diagram.png',
  )..addListener(() => setState(() {}));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final path = _controller.text.trim();
    if (path.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.exportPng(widget.document, path);
      if (mounted) Navigator.of(context).pop(path);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = e.message.toString());
    } on FileSystemException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Could not write to this path: ${e.osError?.message ?? e.message}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _controller.text.trim();
    return AlertDialog(
      title: const Text('Export to PNG'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Output file path',
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
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_busy || path.isEmpty) ? null : _export,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Export'),
        ),
      ],
    );
  }
}
