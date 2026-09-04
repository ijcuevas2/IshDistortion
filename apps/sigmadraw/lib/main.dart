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
/// [TransferFunctionPanel] / [PoleZeroPanel], sharing one [SelectionModel]
/// and one [UndoStack] (§2/§12 — every mutation those pieces make routes
/// through it, undoable via the ribbon's buttons or
/// Ctrl+Z/Ctrl+Shift+Z/Ctrl+Y). §5's [Ribbon] (Phase 5) is the real
/// dockable-panel ribbon shell: a Home tab (Clipboard/Undo/Tools/Zoom)
/// and an Insert tab ([InsertLatexDialog] — the UI entry point Phase 9's
/// `sd_latex` compile pipeline had been missing).
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
  late final SdDocument _document;
  late final DocumentListenable _documentListenable;

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

  Future<void> _insertEquation() => showDialog<void>(
    context: context,
    builder: (_) => InsertLatexDialog(
      document: _document,
      undoStack: _undoStack,
      selection: _selection,
    ),
  );

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
                    Ribbon(tabs: [_homeTab(), _insertTab()]),
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
                          length: 6,
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
