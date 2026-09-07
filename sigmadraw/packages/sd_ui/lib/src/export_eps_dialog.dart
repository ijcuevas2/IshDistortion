import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_export/sd_export.dart';

/// §10's Export-ribbon "EPS" dialog — the UI entry point `sd_export`'s
/// own `exportToEps` had been missing (mirrors [ExportPdfDialog] closing
/// the same kind of gap for `exportToPdf`): type (or accept the
/// suggested) output file path and Export to run the real
/// `pdflatex` + `pdftops` pipeline.
///
/// Pops with the exported path on success, or `null` on Cancel.
class ExportEpsDialog extends StatefulWidget {
  const ExportEpsDialog({
    super.key,
    required this.document,
    this.suggestedPath,
    this.exportEps = exportToEps,
  });

  final SdDocument document;

  /// Defaults to `<current working directory>/diagram.eps` when omitted.
  final String? suggestedPath;

  /// Injectable (default: the real `exportToEps`, which spawns
  /// `pdflatex`/`pdftops` via `Isolate.run`) — same reason and shape as
  /// [ExportPdfDialog.exportPdf]: `Isolate.run` does not reliably
  /// complete when exercised from inside a `testWidgets` test. The real
  /// path is still fully covered, just in `eps_export_test.dart`'s plain
  /// (non-widget) `test()`s instead.
  final Future<void> Function(SdDocument document, String outputPath) exportEps;

  @override
  State<ExportEpsDialog> createState() => _ExportEpsDialogState();
}

class _ExportEpsDialogState extends State<ExportEpsDialog> {
  late final _controller = TextEditingController(
    text: widget.suggestedPath ?? '${Directory.current.path}/diagram.eps',
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
      await widget.exportEps(widget.document, path);
      if (mounted) Navigator.of(context).pop(path);
    } on PdfExportException catch (e) {
      // The pipeline's first (pdflatex) stage failed — see
      // exportToEps's own doc comment on the two-stage pipeline.
      if (mounted) setState(() => _error = e.message);
    } on EpsExportException catch (e) {
      // The second (pdftops) stage failed instead.
      if (mounted) setState(() => _error = e.message);
    } on FileSystemException catch (e) {
      // A hand-typed path (there's no native file-picker dependency
      // here) can easily name an unwritable location; the pipeline's
      // own compile/convert steps can succeed before failing only on
      // this final copy.
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
      title: const Text('Export to EPS'),
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
