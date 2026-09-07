import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';

/// §10's File-group "Open" dialog: type an existing file's path and Open
/// to read and parse it via [parseSdDocument]. Pure Dart file read plus
/// XML parsing — no external process, so no `Isolate.run`/injectable-seam
/// concerns here.
///
/// Deliberately only reads and parses — it does not itself replace the
/// app's current document. A full document *replacement* has app-shell-
/// level implications (undo history, selection, viewport) this dialog
/// has no way to know about; it pops with the freshly parsed
/// [SdDocument] on success (or `null` on Cancel) and leaves swapping it
/// in to the caller.
class OpenDocumentDialog extends StatefulWidget {
  const OpenDocumentDialog({super.key, this.suggestedPath});

  final String? suggestedPath;

  @override
  State<OpenDocumentDialog> createState() => _OpenDocumentDialogState();
}

class _OpenDocumentDialogState extends State<OpenDocumentDialog> {
  late final _controller = TextEditingController(
    text: widget.suggestedPath ?? '',
  )..addListener(() => setState(() {}));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    final path = _controller.text.trim();
    if (path.isEmpty) return;
    setState(() => _error = null);
    final String source;
    try {
      source = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      setState(
        () => _error =
            'Could not read this path: ${e.osError?.message ?? e.message}',
      );
      return;
    }
    try {
      final document = parseSdDocument(source);
      Navigator.of(context).pop(document);
    } catch (e) {
      // parseSdDocument can throw for malformed/non-XML content in more
      // than one exception shape (an invalid-XML parse error vs. e.g. a
      // well-formed-XML-but-not-a-valid-SdDocument structural problem) —
      // catching broadly here is deliberate: any of them should surface
      // as this dialog's own friendly message, not crash it or bubble up
      // as an unhandled error.
      setState(() => _error = 'Could not parse this file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _controller.text.trim();
    return AlertDialog(
      title: const Text('Open Diagram'),
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
          onPressed: path.isEmpty ? null : _open,
          child: const Text('Open'),
        ),
      ],
    );
  }
}
