import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sd_commands/sd_commands.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:sd_ui/sd_ui.dart';

/// SigmaDraw application entry point.
///
/// This is still an early scaffold: [SigmaDrawHome] wires up real Phase
/// 2-4 pieces — a [StencilCanvasArea] (drop-to-place, drag-to-connect,
/// and (§6/§7) draw-ink canvas), a [StencilPalette], and a tabbed
/// [ElementTree] / [InspectorPanel] / [ProblemsPanel] /
/// [TransferFunctionPanel] / [PoleZeroPanel] / [BodePanel], sharing one
/// [SelectionModel] and one [UndoStack] (§2/§12 — every mutation those
/// pieces make routes through it, undoable via the ribbon's buttons or
/// Ctrl+Z/Ctrl+Shift+Z/Ctrl+Y). §5's [Ribbon] (Phase 5) is the real
/// dockable-panel ribbon shell: a Home tab (File/Clipboard/Undo/Tools/
/// Zoom — [SaveDocumentDialog]/[OpenDocumentDialog] give this app its
/// first persistence of any kind; before this, every diagram vanished on
/// close), an Insert tab ([InsertLatexDialog] — the UI entry point
/// Phase 9's `sd_latex` compile pipeline had been missing), and an
/// Export tab ([ExportPdfDialog] — the same kind of gap for
/// `sd_export`'s PDF pipeline).
void main() {
  runApp(const SigmaDrawApp());
}

class SigmaDrawApp extends StatelessWidget {
  const SigmaDrawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SigmaDraw',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const SigmaDrawHome(),
    );
  }
}

class SigmaDrawHome extends StatefulWidget {
  const SigmaDrawHome({super.key});

  @override
  State<SigmaDrawHome> createState() => _SigmaDrawHomeState();
}

class _SigmaDrawHomeState extends State<SigmaDrawHome> {
  final _registry = StencilRegistry.builtIn();
  final _selection = SelectionModel();
  final _undoStack = UndoStack();
  final _clipboard = SdClipboard();
  final _canvasKey = GlobalKey<SigmaCanvasState>();
  // Not `late final`: _openDocument replaces both with a fresh document
  // (and its own listenable) entirely, rather than mutating in place —
  // see _openDocument's own doc comment.
  late SdDocument _document;
  late DocumentListenable _documentListenable;

  /// §10's Home-tab tool selector, driven by the ribbon's Tools group
  /// below.
  CanvasTool _tool = CanvasTool.select;

  @override
  void initState() {
    super.initState();
    _document = createBlankSdDocument(
      width: 1200,
      height: 800,
      sampleRate: '48000',
    );
    // Every UndoStack mutation is also a document mutation (every concrete
    // SdCommand this app uses edits the document), so this already-tested
    // notifier is a correct, no-new-machinery-needed way to know when the
    // undo/redo buttons' enabled state needs to be re-evaluated.
    _documentListenable = DocumentListenable(_document);
  }

  @override
  void dispose() {
    _selection.dispose();
    _documentListenable.dispose();
    super.dispose();
  }

  void _undo() {
    if (_undoStack.canUndo) setState(_undoStack.undo);
  }

  void _redo() {
    if (_undoStack.canRedo) setState(_undoStack.redo);
  }

  void _delete() {
    setState(
      () => deleteSelection(_selection, _document, undoStack: _undoStack),
    );
  }

  void _copy() {
    copySelectionToClipboard(_clipboard, _selection);
  }

  void _paste() {
    setState(
      () => pasteFromClipboard(
        _clipboard,
        _document,
        _selection,
        undoStack: _undoStack,
      ),
    );
  }

  void _zoomIn() => _canvasKey.currentState?.zoomByFactor(1.25);

  void _zoomOut() => _canvasKey.currentState?.zoomByFactor(0.8);

  void _zoomToFit() => _canvasKey.currentState?.fitToContentAuto();

  Future<void> _saveDocument() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => SaveDocumentDialog(document: _document),
    );
    if (path != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved to $path')));
    }
  }

  /// Opens a document from disk, *replacing* the app's current one
  /// wholesale rather than mutating it in place — an
  /// [OpenDocumentDialog] only reads+parses a file (see its own doc
  /// comment on why), so this is the one place that actually adopts the
  /// result: swaps [_document] and [_documentListenable] (disposing the
  /// old listenable, since nothing should keep reacting to a document
  /// that's no longer current), and clears [_undoStack]/[_selection] —
  /// stale undo history or a stale selection referencing the *old*
  /// document's elements could never be meaningfully applied to the new
  /// one. [UndoStack.clear]'s own doc comment names this exact scenario.
  ///
  /// The canvas and the tabbed panels area are each keyed on
  /// `ValueKey(_document)` (see `build` below) so every one of them
  /// (several of which cache a `DocumentListenable` of their own,
  /// bound once in `initState`) gets a clean remount bound to the new
  /// document, rather than silently continuing to listen to the old one.
  Future<void> _openDocument() async {
    final opened = await showDialog<SdDocument>(
      context: context,
      builder: (_) => const OpenDocumentDialog(),
    );
    if (opened == null || !mounted) return;
    setState(() {
      _documentListenable.dispose();
      _document = opened;
      _documentListenable = DocumentListenable(_document);
      _undoStack.clear();
      _selection.clear();
    });
  }

  Future<void> _insertEquation() => showDialog<void>(
    context: context,
    builder: (_) => InsertLatexDialog(
      document: _document,
      undoStack: _undoStack,
      selection: _selection,
    ),
  );

  Future<void> _exportPdf() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => ExportPdfDialog(document: _document),
    );
    if (path != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exported to $path')));
    }
  }

  Future<void> _exportEps() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => ExportEpsDialog(document: _document),
    );
    if (path != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exported to $path')));
    }
  }

  Future<void> _exportPng() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => ExportPngDialog(document: _document),
    );
    if (path != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exported to $path')));
    }
  }

  /// The ribbon's Home tab: Clipboard/Undo/Tools/Zoom groups. Rebuilt from
  /// inside a [ListenableBuilder] merging every model an action's enabled
  /// state depends on, so e.g. "Undo" reads disabled the instant
  /// [UndoStack.canUndo] goes false — the same reactive pattern the old
  /// per-button [ListenableBuilder]s used, just centralized once here
  /// since [Ribbon] itself is plain data.
  RibbonTab _homeTab() => RibbonTab(
    title: 'Home',
    groups: [
      RibbonGroup(
        title: 'File',
        actions: [
          RibbonAction(
            icon: Icons.folder_open,
            label: 'Open',
            tooltip: 'Open a diagram from disk',
            onPressed: _openDocument,
          ),
          RibbonAction(
            icon: Icons.save,
            label: 'Save',
            tooltip: 'Save this diagram to disk',
            onPressed: _saveDocument,
          ),
        ],
      ),
      RibbonGroup(
        title: 'Undo',
        actions: [
          RibbonAction(
            icon: Icons.undo,
            label: 'Undo',
            tooltip: _undoStack.canUndo
                ? 'Undo ${_undoStack.undoDescription}'
                : 'Undo',
            onPressed: _undoStack.canUndo ? _undo : null,
          ),
          RibbonAction(
            icon: Icons.redo,
            label: 'Redo',
            tooltip: _undoStack.canRedo
                ? 'Redo ${_undoStack.redoDescription}'
                : 'Redo',
            onPressed: _undoStack.canRedo ? _redo : null,
          ),
        ],
      ),
      RibbonGroup(
        title: 'Clipboard',
        actions: [
          RibbonAction(
            icon: Icons.content_copy,
            label: 'Copy',
            onPressed: _selection.isEmpty ? null : _copy,
          ),
          RibbonAction(
            icon: Icons.content_paste,
            label: 'Paste',
            onPressed: _paste,
          ),
          RibbonAction(
            icon: Icons.delete_outline,
            label: 'Delete',
            onPressed: _selection.isEmpty ? null : _delete,
          ),
        ],
      ),
      RibbonGroup(
        title: 'Tools',
        child: SegmentedButton<CanvasTool>(
          segments: const [
            ButtonSegment(
              value: CanvasTool.select,
              icon: Icon(Icons.near_me),
              tooltip: 'Select',
            ),
            ButtonSegment(
              value: CanvasTool.ink,
              icon: Icon(Icons.draw),
              tooltip: 'Ink',
            ),
          ],
          selected: {_tool},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              setState(() => _tool = selection.single),
        ),
      ),
      RibbonGroup(
        title: 'Zoom',
        actions: [
          RibbonAction(
            icon: Icons.zoom_in,
            label: 'Zoom In',
            onPressed: _zoomIn,
          ),
          RibbonAction(
            icon: Icons.zoom_out,
            label: 'Zoom Out',
            onPressed: _zoomOut,
          ),
          RibbonAction(
            icon: Icons.fit_screen,
            label: 'Fit',
            tooltip: 'Zoom to fit',
            onPressed: _zoomToFit,
          ),
        ],
      ),
    ],
  );

  RibbonTab _insertTab() => RibbonTab(
    title: 'Insert',
    groups: [
      RibbonGroup(
        title: 'Equation',
        actions: [
          RibbonAction(
            icon: Icons.functions,
            label: 'New Equation',
            tooltip: 'Insert a LaTeX equation',
            onPressed: _insertEquation,
          ),
        ],
      ),
    ],
  );

  RibbonTab _exportTab() => RibbonTab(
    title: 'Export',
    groups: [
      RibbonGroup(
        title: 'Vector',
        actions: [
          RibbonAction(
            icon: Icons.picture_as_pdf,
            label: 'PDF',
            tooltip: 'Export this diagram to PDF',
            onPressed: _exportPdf,
          ),
          RibbonAction(
            icon: Icons.description_outlined,
            label: 'EPS',
            tooltip: 'Export this diagram to EPS',
            onPressed: _exportEps,
          ),
        ],
      ),
      RibbonGroup(
        title: 'Raster',
        actions: [
          RibbonAction(
            icon: Icons.image_outlined,
            label: 'PNG',
            tooltip: 'Export this diagram to PNG',
            onPressed: _exportPng,
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        const SingleActivator(LogicalKeyboardKey.delete): _delete,
        const SingleActivator(LogicalKeyboardKey.backspace): _delete,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copy,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _paste,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(title: const Text('SigmaDraw')),
          body: Column(
            children: [
              ListenableBuilder(
                listenable: Listenable.merge([_documentListenable, _selection]),
                builder: (context, _) =>
                    Ribbon(tabs: [_homeTab(), _insertTab(), _exportTab()]),
              ),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: Material(
                        elevation: 1,
                        child: StencilPalette(registry: _registry),
                      ),
                    ),
                    Expanded(
                      child: StencilCanvasArea(
                        // Forces a clean remount (fresh viewport/drag
                        // state) on _openDocument, rather than the canvas
                        // silently carrying over state that belonged to
                        // whatever document was open before.
                        key: ValueKey(_document),
                        document: _document,
                        selection: _selection,
                        undoStack: _undoStack,
                        tool: _tool,
                        canvasKey: _canvasKey,
                      ),
                    ),
                    SizedBox(
                      width: 320,
                      child: Material(
                        elevation: 1,
                        child: DefaultTabController(
                          // Same reasoning as StencilCanvasArea's key
                          // above: several of these panels cache their
                          // own DocumentListenable in initState and never
                          // rebind it if `document` merely changes on an
                          // existing State — a fresh key forces a clean
                          // remount bound to the new document instead.
                          key: ValueKey(_document),
                          length: 8,
                          child: Column(
                            children: [
                              const TabBar(
                                labelStyle: TextStyle(fontSize: 11),
                                tabs: [
                                  Tab(text: 'Elements'),
                                  Tab(text: 'Inspector'),
                                  Tab(text: 'Problems'),
                                  Tab(text: 'H(z)'),
                                  Tab(text: 'Pole-Zero'),
                                  Tab(text: 'Bode'),
                                  Tab(text: 'Nyquist'),
                                  Tab(text: 'Spectrogram'),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    ElementTree(
                                      document: _document,
                                      selection: _selection,
                                      registry: _registry,
                                    ),
                                    InspectorPanel(
                                      selection: _selection,
                                      registry: _registry,
                                      undoStack: _undoStack,
                                    ),
                                    ProblemsPanel(
                                      document: _document,
                                      selection: _selection,
                                    ),
                                    TransferFunctionPanel(document: _document),
                                    PoleZeroPanel(document: _document),
                                    BodePanel(document: _document),
                                    NyquistPanel(document: _document),
                                    SpectrogramPanel(document: _document),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
