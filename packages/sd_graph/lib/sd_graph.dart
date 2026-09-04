/// The semantic signal-flow graph for SigmaDraw (§4): typed ports/blocks/
/// edges extracted from a document's `sd:*` attributes, validation
/// (§4/§10's Problems panel), and analysis (§4/§8) — rate propagation,
/// Tarjan strongly-connected-components-based algebraic-loop detection,
/// Mason's gain formula for a symbolic transfer function H(z), and
/// (§5.11) pole-zero computation from that H(z) via Durand-Kerner
/// polynomial root-finding.
///
/// Hierarchical/subsystem support is flagged (`Block.isSubsystem`) but not
/// implemented — see that field's doc comment. Netlist-driven simulation
/// and the rest of §5.11's analysis plots (Bode, Nyquist, spectrogram,
/// ...) are not implemented.
library;

export 'src/algebraic_loops.dart';
export 'src/block.dart';
export 'src/complex.dart';
export 'src/edge.dart';
export 'src/expression.dart';
export 'src/mason.dart';
export 'src/netlist.dart';
export 'src/pole_zero.dart';
export 'src/port.dart';
export 'src/rate_propagation.dart';
export 'src/signal_graph.dart';
export 'src/types.dart';
export 'src/validation.dart';
