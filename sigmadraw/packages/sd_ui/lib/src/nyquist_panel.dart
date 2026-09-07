import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

import 'document_listenable.dart';

/// A live Nyquist plot (§5.11's "Analysis Plot — Nyquist") from the same
/// Mason-derived `H(z)` [TransferFunctionPanel]/[PoleZeroPanel]/
/// [BodePanel] show, recomputed whenever the document changes:
/// `H(e^{j*omega})` traced directly in the complex plane over the full
/// closed contour.
///
/// [computeNyquistPlot] needs concrete numbers (unlike Mason's formula
/// itself, which stays meaningful fully symbolic), so this panel shares
/// [PoleZeroPanel]/[BodePanel]'s three message states — no source/sink,
/// an algebraic loop, or an unresolved coefficient symbol.
class NyquistPanel extends StatefulWidget {
  const NyquistPanel({super.key, required this.document});

  final SdDocument document;

  @override
  State<NyquistPanel> createState() => _NyquistPanelState();
}

class _NyquistPanelState extends State<NyquistPanel> {
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
            : computeNyquistPlot(transferFunction.h);

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
              Text('Nyquist', style: Theme.of(context).textTheme.labelMedium),
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
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: NyquistPlotPainter(points: points),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '"x" marks the classical -1 reference point.',
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
