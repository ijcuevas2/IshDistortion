import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_render/sd_render.dart';
import 'package:sd_stencils/sd_stencils.dart';
import 'package:sd_ui/sd_ui.dart';

/// SigmaDraw application entry point.
///
/// This is still an early scaffold: [SigmaDrawHome] wires up real
/// Phase 2/3 pieces — a [StencilCanvasArea] (drop-to-place canvas), a
/// [StencilPalette], an [ElementTree], and an [InspectorPanel], sharing
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
            width: 280,
            child: Material(
              elevation: 1,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Elements'),
                    ),
                  ),
                  Expanded(
                    child: ElementTree(
                      document: _document,
                      selection: _selection,
                      registry: _registry,
                    ),
                  ),
                  const Divider(height: 1),
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Inspector'),
                    ),
                  ),
                  Expanded(
                    child: InspectorPanel(
                      selection: _selection,
                      registry: _registry,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
