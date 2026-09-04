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
/// and (§6/§7) draw-ink canvas — the app bar's segmented button switches
/// [CanvasTool]), a [StencilPalette], and a tabbed [ElementTree] /
/// [InspectorPanel] / [ProblemsPanel] / [TransferFunctionPanel], sharing
/// one [SelectionModel] and one [UndoStack] (§2/§12 — every mutation those
/// pieces make routes through it, undoable via the app bar's buttons or
/// Ctrl+Z/Ctrl+Shift+Z/Ctrl+Y) — in a plain [Row] layout standing in for
/// the dockable-panel ribbon shell that Phase 5 will build.
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
  late final SdDocument _document;
  late final DocumentListenable _documentListenable;

  /// §10's Home-tab tool selector, stood in for by the app bar's
  /// segmented button below until the real ribbon (Phase 5) exists.
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
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('SigmaDraw'),
            actions: [
              SegmentedButton<CanvasTool>(
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
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: _documentListenable,
                builder: (context, _) => IconButton(
                  icon: const Icon(Icons.undo),
                  tooltip: _undoStack.canUndo
                      ? 'Undo ${_undoStack.undoDescription}'
                      : 'Undo',
                  onPressed: _undoStack.canUndo ? _undo : null,
                ),
              ),
              ListenableBuilder(
                listenable: _documentListenable,
                builder: (context, _) => IconButton(
                  icon: const Icon(Icons.redo),
                  tooltip: _undoStack.canRedo
                      ? 'Redo ${_undoStack.redoDescription}'
                      : 'Redo',
                  onPressed: _undoStack.canRedo ? _redo : null,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Row(
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
                ),
              ),
              SizedBox(
                width: 320,
                child: Material(
                  elevation: 1,
                  child: DefaultTabController(
                    length: 4,
                    child: Column(
                      children: [
                        const TabBar(
                          labelStyle: TextStyle(fontSize: 11),
                          tabs: [
                            Tab(text: 'Elements'),
                            Tab(text: 'Inspector'),
                            Tab(text: 'Problems'),
                            Tab(text: 'H(z)'),
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
      ),
    );
  }
}
