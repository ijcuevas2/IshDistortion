/// Scene/display-list rendering for SigmaDraw: an SVG-subset interpreter,
/// a retained paint tree with a quadtree spatial index, and the composed
/// interactive infinite canvas — pan/zoom/grid, hit-testing, click/marquee
/// selection, and move/scale handles.
///
/// See `sigmadraw-implementation-prompt.md` §8/§9. Scope cuts made at this
/// phase are documented on [buildScene], [SigmaCanvas], and
/// `SvgPaintState`.
library;

export 'src/geometry/svg_paint.dart';
export 'src/geometry/svg_path_data.dart';
export 'src/geometry/svg_shapes.dart';
export 'src/geometry/svg_transform.dart';
export 'src/grid_painter.dart';
export 'src/scene/hit_test.dart';
export 'src/scene/scene.dart';
export 'src/scene/scene_builder.dart';
export 'src/scene/scene_node.dart';
export 'src/scene/scene_painter.dart';
export 'src/scene/spatial_index.dart';
export 'src/selection/handles.dart';
export 'src/selection/selection_model.dart';
export 'src/selection/selection_overlay_painter.dart';
export 'src/sigma_canvas.dart';
export 'src/viewport.dart';
