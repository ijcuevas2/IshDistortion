/// The semantic signal-flow graph for SigmaDraw (§4): typed ports/blocks/
/// edges extracted from a document's `sd:*` attributes, validation
/// (§4/§10's Problems panel), and analysis (§4/§8) — rate propagation,
/// Tarjan strongly-connected-components-based algebraic-loop detection,
/// Mason's gain formula for a symbolic transfer function H(z), and 7 of
/// §5.11's 11 named analysis plots computed from that same `H(z)`:
/// pole-zero (Durand-Kerner polynomial root-finding), Bode (magnitude/
/// phase) and Nyquist (complex-plane) from `H` evaluated around the
/// unit circle, group delay (an exact symbolic derivative of `H`'s own
/// phase, not a finite-difference approximation), root locus (poles
/// re-found as one still-symbolic coefficient sweeps), and impulse/step
/// response and a spectrogram — the three plots needing an actual
/// simulated signal rather than only `H(z)` evaluated at points, via
/// [simulateDifferenceEquation]. Not implemented: a constellation plot
/// and an eye diagram, which need a symbol-level modulation/timing
/// simulation harness this project doesn't have (see README.md).
///
/// Hierarchical/subsystem support is flagged (`Block.isSubsystem`) but not
/// implemented — see that field's doc comment.
library;

export 'src/algebraic_loops.dart';
export 'src/block.dart';
export 'src/complex.dart';
export 'src/edge.dart';
export 'src/expression.dart';
export 'src/frequency_response.dart';
export 'src/mason.dart';
export 'src/netlist.dart';
export 'src/pole_zero.dart';
export 'src/port.dart';
export 'src/rate_propagation.dart';
export 'src/signal_graph.dart';
export 'src/spectrogram.dart';
export 'src/types.dart';
export 'src/validation.dart';
