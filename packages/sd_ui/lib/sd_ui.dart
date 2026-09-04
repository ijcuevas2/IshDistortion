/// Ribbon, panels, element tree, inspector, palette, and status bar for
/// SigmaDraw (§10). Scope so far: the stencil palette (search + drag), a
/// drop-to-place-and-connect canvas wrapper, the element tree, the
/// property inspector, a live Problems panel, and a live H(z) readout
/// (§4's semantic-graph analysis, surfaced in the UI). The ribbon itself,
/// docking, and the status bar land in Phase 5.
library;

export 'src/document_listenable.dart';
export 'src/element_tree.dart';
export 'src/inspector_panel.dart';
export 'src/problems_panel.dart';
export 'src/stencil_canvas_area.dart';
export 'src/stencil_palette.dart';
export 'src/transfer_function_panel.dart';
