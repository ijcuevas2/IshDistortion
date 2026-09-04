import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart'
    show currentLocalTransform, parentWorldTransformOf;

/// 1cm per this many SVG user units. Our stencils are authored at
/// `StencilMetrics.kBaseUnit == 10` SVG units per tikz-dsp unit, and a
/// typical tikz-dsp figure uses roughly 1cm per unit — so this puts a
/// `squareBlock` (80 units) at ~4cm, matching a normal tikz-dsp figure's
/// scale.
const double _svgUnitsPerCm = 20;

/// Options for [exportToTikz].
class TikzExportOptions {
  const TikzExportOptions({
    this.standalone = true,
    this.scale = 1 / _svgUnitsPerCm,
  });

  /// Wrap the `tikzpicture` in a compilable `standalone` document (so the
  /// output is directly `pdflatex`-able) rather than emitting just the
  /// `tikzpicture` environment for inclusion in a larger document.
  final bool standalone;

  /// SVG user units per TikZ unit (TikZ units default to cm).
  final double scale;
}

/// Exports [document] as tikz-dsp-style source (§11): each block becomes a
/// styled, labeled TikZ node (a circle for summing junctions/pickoff
/// nodes, a triangle for gains, a rectangle otherwise); each edge becomes
/// an arrow between two *named* nodes — TikZ's node-shape-aware path
/// clipping draws the arrow to each shape's boundary automatically, so
/// this doesn't need to duplicate `sd_render`'s port-position geometry.
///
/// Scope: only a `translate(x,y)` (or no) `transform` on a block is
/// resolved into a position — rotation/skew on a block itself isn't
/// reflected in the exported layout (TikZ nodes are still readable, just
/// not rotated to match). Standard TikZ only (no dependency on the
/// external, rarely-installed `tikz-dsp` package), styled to read the
/// same way.
String exportToTikz(
  SdDocument document, {
  TikzExportOptions options = const TikzExportOptions(),
}) {
  final graph = SignalGraph.fromDocument(document);
  final buffer = StringBuffer();

  if (options.standalone) {
    buffer
      ..writeln(r'\documentclass[tikz,border=4pt]{standalone}')
      ..writeln(r'\usetikzlibrary{arrows.meta,shapes.geometric}')
      ..writeln(r'\begin{document}');
  }
  buffer
    ..writeln(r'\begin{tikzpicture}[')
    ..writeln(
      r'  block/.style={draw, rectangle, minimum width=1.4cm, minimum height=1.2cm, font=\small},',
    )
    ..writeln(r'  sum/.style={draw, circle, minimum size=0.9cm, font=\small},')
    ..writeln(
      r'  tri/.style={draw, isosceles triangle, isosceles triangle apex angle=60, minimum height=1.2cm, font=\small},',
    )
    ..writeln(r'  >={Stealth[length=2mm]}')
    ..writeln(']');

  final nodeIdOf = <String, String>{};
  for (final element in document.root.descendantElements) {
    final type = element.blockType;
    final blockId = element.blockId;
    if (type == null || blockId == null) continue;

    final world =
        parentWorldTransformOf(element) * currentLocalTransform(element);
    final translation = world.getTranslation();
    final x = translation.x * options.scale;
    final y = -translation.y * options.scale; // SVG is y-down; TikZ is y-up.

    final style = switch (type) {
      'adder' || 'pickoff-node' => 'sum',
      'gain' => 'tri',
      _ => 'block',
    };
    final nodeId = 'n${nodeIdOf.length}';
    nodeIdOf[blockId] = nodeId;
    buffer.writeln(
      '  \\node[$style] ($nodeId) at (${_fmt(x)}, ${_fmt(y)}) {${_labelFor(element, type)}};',
    );
  }

  for (final edge in graph.edges) {
    final from = nodeIdOf[edge.fromBlockId];
    final to = nodeIdOf[edge.toBlockId];
    if (from == null || to == null) continue;
    final label = edge.signalLabel;
    final labelTex = label == null || label.isEmpty
        ? ''
        : ' node[midway, above] {\$${_tikzEscape(label)}\$}';
    buffer.writeln('  \\draw[->] ($from) -- ($to)$labelTex;');
  }

  buffer.writeln(r'\end{tikzpicture}');
  if (options.standalone) buffer.writeln(r'\end{document}');
  return buffer.toString();
}

String _labelFor(SdElement element, String type) {
  final explicit = element.blockLabel;
  if (explicit != null && explicit.isNotEmpty) return _tikzEscape(explicit);
  switch (type) {
    case 'gain':
      final g = element.blockParams['gain'];
      return g == null ? '' : _tikzEscape('$g');
    case 'delay':
      final k = (element.blockParams['k'] as num?)?.toInt() ?? 1;
      return k == 1 ? r'$z^{-1}$' : '\$z^{-$k}\$';
    case 'adder':
    case 'pickoff-node':
      return '';
    default:
      return _tikzEscape(type);
  }
}

String _tikzEscape(String s) => s
    .replaceAll(r'\', r'\textbackslash ')
    .replaceAll('_', r'\_')
    .replaceAll('&', r'\&')
    .replaceAll('%', r'\%')
    .replaceAll('#', r'\#');

String _fmt(double v) => v.toStringAsFixed(3);
