import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:sd_ui/sd_ui.dart';

/// SigmaDraw application entry point.
///
/// This is still an early scaffold: [SigmaDrawHome] wires up real Phase
/// 2-4 pieces — a [StencilCanvasArea] (drop-to-place, drag-to-connect
/// canvas), a [StencilPalette], and a tabbed [ElementTree] /
/// [InspectorPanel] / [ProblemsPanel] / [TransferFunctionPanel], sharing
/// one [SelectionModel] — in a plain [Row] layout standing in for the
/// dockable-panel ribbon shell that Phase 5 will build.
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
  late final SdDocument _document;

  @override
  void initState() {
    super.initState();
    _document = createBlankSdDocument(
      width: 1200,
      height: 800,
      sampleRate: '48000',
    );
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SigmaDraw')),
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
    );
  }
}
