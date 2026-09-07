import 'package:sd_document/sd_document.dart';

/// Base metrics from tikz-dsp, scaled to a working pixel size (§5). All
/// stencil geometry is authored in these units then multiplied by
/// [kBaseUnit] once, so the *relative* proportions match tikz-dsp exactly
/// while the *absolute* size is convenient to work with on a real canvas.
abstract final class StencilMetrics {
  /// tikz-dsp units -> SVG user units.
  static const double kBaseUnit = 10.0;

  static const double operatorDiameter = 4 * kBaseUnit;
  static const double squareBlock = 8 * kBaseUnit;
  static const double filterBlockWidth = 14 * kBaseUnit;
  static const double nodeRadius = 1 * kBaseUnit;
  static const double wireWidth = 0.25 * kBaseUnit;
  static const double blockOutline = 0.3 * kBaseUnit;
  static const double labelSpacing = 2 * kBaseUnit;
}

const _stroke = SdQName('stroke');
const _strokeWidth = SdQName('stroke-width');
const _fill = SdQName('fill');

SdElement circleShape({
  required double cx,
  required double cy,
  required double r,
  String fill = '#ffffff',
  String stroke = '#1a1a1a',
  double strokeWidth = StencilMetrics.blockOutline,
}) => SdElement(
  const SdQName('circle'),
  attributes: {
    const SdQName('cx'): '$cx',
    const SdQName('cy'): '$cy',
    const SdQName('r'): '$r',
    _fill: fill,
    _stroke: stroke,
    _strokeWidth: '$strokeWidth',
  },
);

/// A small filled dot — the "pickoff node" (`dspnodefull`) and general
/// junction-point marker (§5.1).
SdElement filledDot({
  required double cx,
  required double cy,
  double r = StencilMetrics.nodeRadius,
}) => circleShape(cx: cx, cy: cy, r: r, fill: '#1a1a1a', strokeWidth: 0);

SdElement rectShape({
  required double x,
  required double y,
  required double width,
  required double height,
  String fill = '#ffffff',
  String stroke = '#1a1a1a',
  double strokeWidth = StencilMetrics.blockOutline,
}) => SdElement(
  const SdQName('rect'),
  attributes: {
    const SdQName('x'): '$x',
    const SdQName('y'): '$y',
    const SdQName('width'): '$width',
    const SdQName('height'): '$height',
    _fill: fill,
    _stroke: stroke,
    _strokeWidth: '$strokeWidth',
  },
);

SdElement lineShape({
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  String stroke = '#1a1a1a',
  double strokeWidth = StencilMetrics.wireWidth,
  String? markerEnd,
  String? dashArray,
}) => SdElement(
  const SdQName('line'),
  attributes: {
    const SdQName('x1'): '$x1',
    const SdQName('y1'): '$y1',
    const SdQName('x2'): '$x2',
    const SdQName('y2'): '$y2',
    _stroke: stroke,
    _strokeWidth: '$strokeWidth',
    const SdQName('vector-effect'): 'non-scaling-stroke',
    if (markerEnd != null) const SdQName('marker-end'): 'url(#$markerEnd)',
    const SdQName('stroke-dasharray'): ?dashArray,
  },
);

/// A closed polygon from local-space [points] (dx,dy pairs), e.g. the
/// multiplier/gain triangle (§5.1).
SdElement polygonShape(
  List<(double, double)> points, {
  String fill = '#ffffff',
  String stroke = '#1a1a1a',
  double strokeWidth = StencilMetrics.blockOutline,
}) => SdElement(
  const SdQName('polygon'),
  attributes: {
    const SdQName('points'): points.map((p) => '${p.$1},${p.$2}').join(' '),
    _fill: fill,
    _stroke: stroke,
    _strokeWidth: '$strokeWidth',
  },
);

SdElement textLabel({
  required double x,
  required double y,
  required String text,
  double fontSize = StencilMetrics.kBaseUnit * 1.6,
  String anchor = 'middle',
  String fill = '#1a1a1a',
}) => SdElement(
  const SdQName('text'),
  attributes: {
    const SdQName('x'): '$x',
    const SdQName('y'): '$y',
    const SdQName('font-size'): '$fontSize',
    const SdQName('text-anchor'): anchor,
    _fill: fill,
  },
  children: [SdText(text)],
);
