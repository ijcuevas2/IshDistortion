/// The semantic signal-flow graph for SigmaDraw (§4): typed ports/blocks/
/// edges extracted from a document's `sd:*` attributes, validation
/// (§4/§10's Problems panel), and analysis (§4/§8) — rate propagation,
/// Tarjan strongly-connected-components-based algebraic-loop detection,
/// Mason's gain formula for a symbolic transfer function H(z), (§5.11)
/// pole-zero computation from that H(z) via Durand-Kerner polynomial
/// root-finding, (§5.11) Bode magnitude/phase and Nyquist complex-plane
/// plots from the same H(z) evaluated around the unit circle, and
/// (§5.11) a spectrogram of `H`'s own simulated response to a chirp —
/// the one §5.11 plot that needs an actual sampled signal rather than
/// only `H(z)` itself.
///
/// Hierarchical/subsystem support is flagged (`Block.isSubsystem`) but not
/// implemented — see that field's doc comment. Netlist-driven simulation
/// against an arbitrary, user-authored input signal is not implemented —
/// [simulateDifferenceEquation] exists but is only driven by
/// [generateChirp] so far.
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
