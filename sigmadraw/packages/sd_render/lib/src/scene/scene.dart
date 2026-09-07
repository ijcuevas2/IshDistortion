import 'package:flutter/foundation.dart';
import 'package:sd_document/sd_document.dart';

import 'scene_builder.dart';
import 'scene_node.dart';
import 'spatial_index.dart';

/// Owns the retained [SceneNode] tree and [SpatialIndex] for one
/// [SdDocument], rebuilding both whenever the document changes, and is
/// itself a [Listenable] a [CustomPainter] can key its repaint off of —
/// the bridge from [SdDocument.changes] (a dependency-free
/// `SdChangeNotifier`, since `sd_document` can't depend on Flutter) to a
/// real `ChangeNotifier`, exactly as forecast in that class's doc comment.
///
/// Rebuilding the whole tree on every change (rather than incrementally
/// patching it) is a deliberate Phase 2 simplification: `sd_document`
/// currently fires one coarse-grained, whole-document change notification,
/// so there's nothing finer to key an incremental update off yet. A full
/// rebuild at the sizes targeted here (§13: thousands of elements) is well
/// under a frame — revisit only if profiling says otherwise.
class Scene extends ChangeNotifier {
  Scene(this.document) {
    _rebuild();
    document.changes.addListener(_onDocumentChanged);
  }

  final SdDocument document;

  late SceneNode root;
  late SpatialIndex spatialIndex;

  void _onDocumentChanged() {
    _rebuild();
    notifyListeners();
  }

  void _rebuild() {
    root = buildScene(document);
    spatialIndex = SpatialIndex.build(root);
  }

  @override
  void dispose() {
    document.changes.removeListener(_onDocumentChanged);
    super.dispose();
  }
}
