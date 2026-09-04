import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';

/// §10's File-group "Save" dialog: type (or accept the suggested) output
/// file path and Save to write the document's native-SVG serialization
/// there via [writeSdDocument]. Pure Dart string serialization plus a
/// plain synchronous file write — no external process involved, so
/// (unlike [ExportPdfDialog]) there's no `Isolate.run` in the way and no
/// injectable seam needed for real widget-test coverage.
///
/// Pops with the saved path on success, or `null` on Cancel.
class SaveDocumentDialog extends StatefulWidget {
  const SaveDocumentDialog({
    super.key,
    required this.document,
    this.suggestedPath,
  });

  final SdDocument document;

  /// Defaults to `<current working directory>/diagram.svg` when omitted
  /// — desktop-only, so there's no permissions concern reading it, and a
  /// text field the user can freely edit either way.
  final String? suggestedPath;

  @override
  State<SaveDocumentDialog> createState() => _SaveDocumentDialogState();
}

class _SaveDocumentDialogState extends State<SaveDocumentDialog> {
  late final _controller = TextEditingController(
    text: widget.suggestedPath ?? '${Directory.current.path}/diagram.svg',
  )..addListener(() => setState(() {}));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final path = _controller.text.trim();
    if (path.isEmpty) return;
    try {
      File(path).writeAsStringSync(writeSdDocument(widget.document));
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
      title: const Text('Save Diagram'),
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
          onPressed: path.isEmpty ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
