import 'package:flutter/material.dart';
import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_latex/sd_latex.dart';
import 'package:sd_render/sd_render.dart';

/// §10's Insert-ribbon "Equation" dialog — the UI entry point `sd_latex`'s
/// own doc comment names as the one missing piece of the Phase 9 LaTeX
/// pipeline ("Not implemented: an equation-editor dialog/launcher"). Type
/// math-mode TeX, see it rendered live via the fast on-screen [LatexLabel]
/// path, and Insert to run the real `pdflatex`+`dvisvgm` toolchain (via
/// [renderCache]) and splice the result into [document] — as one undoable
/// step through [undoStack] when given, else this project's usual direct-
/// mutation fallback.
///
/// Typically opened with
/// `showDialog<void>(context: context, builder: (_) => InsertLatexDialog(...))`.
class InsertLatexDialog extends StatefulWidget {
  InsertLatexDialog({
    super.key,
    required this.document,
    this.undoStack,
    this.selection,
    this.insertAt = const Offset(100, 100),
    LatexRenderCache? renderCache,
  }) : renderCache = renderCache ?? LatexRenderCache();

  final SdDocument document;
  final UndoStack? undoStack;
  final SelectionModel? selection;

  /// Where, in document space, the compiled equation's top-left corner
  /// lands. A fixed default rather than e.g. "the current viewport's
  /// center" — this dialog has no viewport of its own to read; a caller
  /// wanting placement relative to one can compute this before opening
  /// the dialog.
  final Offset insertAt;

  /// Injectable (default: a fresh cache wrapping the real
  /// `compileLatexToSvg`) so tests — and repeated inserts within one
  /// session — don't each have to spawn a real `pdflatex` process.
  final LatexRenderCache renderCache;

  @override
  State<InsertLatexDialog> createState() => _InsertLatexDialogState();
}

class _InsertLatexDialogState extends State<InsertLatexDialog> {
  static const _defaultSource = r'H(z) = \frac{1}{1 - z^{-1}}';

  late final _controller = TextEditingController(text: _defaultSource)
    ..addListener(() => setState(() {}));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _insert() async {
    final source = _controller.text.trim();
    if (source.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final embed = await widget.renderCache.render(source);
      final content = positionLatexEmbed(
        widget.document,
        embed,
        x: widget.insertAt.dx,
        y: widget.insertAt.dy,
      );
      final undoStack = widget.undoStack;
      if (undoStack == null) {
        widget.document.root.appendChild(content);
      } else {
        undoStack.execute(
          InsertChildCommand(
            widget.document.root,
            content,
            description: 'Insert equation',
          ),
        );
      }
      widget.selection?.selectOnly(content);
      if (mounted) Navigator.of(context).pop();
    } on LatexCompileException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _controller.text.trim();
    return AlertDialog(
      title: const Text('Insert Equation'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'LaTeX (math mode, no \$ delimiters)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('Preview', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: source.isEmpty
                  ? const Text('—')
                  : LatexLabel(source, style: const TextStyle(fontSize: 18)),
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
          onPressed: (_busy || source.isEmpty) ? null : _insert,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Insert'),
        ),
      ],
    );
  }
}
