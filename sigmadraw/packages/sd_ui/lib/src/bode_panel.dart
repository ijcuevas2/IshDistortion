import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

import 'document_listenable.dart';

/// A live Bode plot (§5.11's "Analysis Plot — Bode") from the same
/// Mason-derived `H(z)` [TransferFunctionPanel]/[PoleZeroPanel] show,
/// recomputed whenever the document changes: magnitude (dB) and unwrapped
/// phase (degrees) of `H(e^{j*omega})` swept from DC to Nyquist.
///
/// [computeBodePlot] needs concrete numbers (unlike Mason's formula
/// itself, which stays meaningful fully symbolic), so this panel shares
/// [PoleZeroPanel]'s three message states — no source/sink, an algebraic
/// loop, or an unresolved coefficient symbol — none of which produce a
/// usable `H(z)` to plot.
class BodePanel extends StatefulWidget {
  const BodePanel({super.key, required this.document});

  final SdDocument document;

  @override
  State<BodePanel> createState() => _BodePanelState();
}

class _BodePanelState extends State<BodePanel> {
  late final DocumentListenable _documentListenable;

  @override
  void initState() {
    super.initState();
    _documentListenable = DocumentListenable(widget.document);
  }

  @override
  void dispose() {
    _documentListenable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _documentListenable,
      builder: (context, _) {
        final graph = SignalGraph.fromDocument(widget.document);
        final hasLoop = detectAlgebraicLoops(graph).isNotEmpty;
        final transferFunction = hasLoop
            ? null
            : computeTransferFunction(graph);
        final points = transferFunction == null
            ? null
            : computeBodePlot(transferFunction.h);

        String? message;
        if (hasLoop) {
          message =
              'Cannot compute: the diagram has an algebraic (delay-free) loop.';
        } else if (transferFunction == null) {
          message = 'Place a "source" and a "sink" block to compute a transfer function.';
        } else if (points == null) {
          message =
              'Cannot plot: one or more coefficients is still an unresolved '
              'parameter (e.g. a gain left as a symbol rather than a number).';
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bode', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              if (message != null)
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasLoop ? Colors.red : null,
                  ),
                )
              else ...[
                Expanded(
                  child: CustomPaint(painter: BodePlotPainter(points: points)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'DC (0 rad/sample) to Nyquist (pi rad/sample)',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
