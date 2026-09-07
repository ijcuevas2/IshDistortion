import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_export/sd_export.dart';

/// §10's Export-ribbon "PDF" dialog — the UI entry point `sd_export`'s
/// own `exportToPdf` had been missing (mirrors [InsertLatexDialog]
/// closing the same kind of gap for `sd_latex`'s compile pipeline): type
/// (or accept the suggested) output file path and Export to run the real
/// `pdflatex` pipeline.
///
/// Pops with the exported path on success (so a caller can confirm it,
/// e.g. via a `SnackBar` — this dialog has no `Scaffold` of its own to
/// show one from) or `null` on Cancel.
class ExportPdfDialog extends StatefulWidget {
  const ExportPdfDialog({
    super.key,
    required this.document,
    this.suggestedPath,
    this.exportPdf = exportToPdf,
  });

  final SdDocument document;

  /// Defaults to `<current working directory>/diagram.pdf` when omitted
  /// — desktop-only, so there's no permissions concern reading it, and a
  /// text field the user can freely edit either way.
  final String? suggestedPath;

  /// Injectable (default: the real `exportToPdf`, which spawns `pdflatex`
  /// via `Isolate.run`). Needed for testability beyond this dialog's own
  /// non-exporting behavior (Cancel, the suggested path, the disabled-
  /// button state): `Isolate.run` does not reliably complete when
  /// exercised from inside a `testWidgets` test (`flutter_tester`'s
  /// isolate hosting differs from a normal Dart VM or running app) —
  /// the same reason `InsertLatexDialog` goes through an injectable
  /// `LatexRenderCache` rather than calling `compileLatexToSvg`
  /// directly. The real path is still fully covered, just in
  /// `pdf_export_test.dart`'s plain (non-widget) `test()`s instead.
  final Future<void> Function(SdDocument document, String outputPath) exportPdf;

  @override
  State<ExportPdfDialog> createState() => _ExportPdfDialogState();
}

class _ExportPdfDialogState extends State<ExportPdfDialog> {
  late final _controller = TextEditingController(
    text: widget.suggestedPath ?? '${Directory.current.path}/diagram.pdf',
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
      await widget.exportPdf(widget.document, path);
      if (mounted) Navigator.of(context).pop(path);
    } on PdfExportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FileSystemException catch (e) {
      // Unlike a real file-save dialog (not used here — see the class
      // doc comment), a hand-typed path can easily name a directory
      // that doesn't exist or isn't writable; exportToPdf's own compile
      // step can succeed before failing only on this final copy, so
      // this needs its own separate, friendlier catch rather than
      // surfacing a raw FileSystemException as an unhandled error.
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
      title: const Text('Export to PDF'),
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
