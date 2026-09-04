import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

import 'document_listenable.dart';

/// A live pole-zero plot (§5.11's "Analysis Plot — pole-zero") from the
/// same Mason-derived `H(z)` [TransferFunctionPanel] shows, recomputed
/// whenever the document changes. Poles (`x`) and zeros (`o`) are plotted
/// against the unit circle — a pole strictly inside it means a stable
/// causal filter, which the plot calls out explicitly rather than leaving
/// the reader to eyeball it.
///
/// [computePoleZero] needs concrete numbers (unlike Mason's formula
/// itself, which stays meaningful fully symbolic), so this panel shows
/// its own distinct message when a coefficient is still an unresolved
/// symbol, separate from [TransferFunctionPanel]'s "no source/sink" and
/// "algebraic loop" cases (both of which this panel shares, since neither
/// produces a usable `H(z)` to begin with).
class PoleZeroPanel extends StatefulWidget {
  const PoleZeroPanel({super.key, required this.document});

  final SdDocument document;

  @override
  State<PoleZeroPanel> createState() => _PoleZeroPanelState();
}

class _PoleZeroPanelState extends State<PoleZeroPanel> {
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
        final poleZero = transferFunction == null
            ? null
            : computePoleZero(transferFunction.h);

        String? message;
        if (hasLoop) {
          message =
              'Cannot compute: the diagram has an algebraic (delay-free) loop.';
        } else if (transferFunction == null) {
          message = 'Place a "source" and a "sink" block to compute a transfer function.';
        } else if (poleZero == null) {
          message =
              'Cannot plot: one or more coefficients is still an unresolved '
              'parameter (e.g. a gain left as a symbol rather than a number).';
        }

        final unstable =
            poleZero != null && poleZero.poles.any((p) => p.abs() >= 1);

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pole-Zero', style: Theme.of(context).textTheme.labelMedium),
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
                      painter: PoleZeroPlotPainter(result: poleZero),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    _Legend(color: Color(0xFFC62828), label: 'x pole'),
                    SizedBox(width: 16),
                    _Legend(color: Color(0xFF1565C0), label: 'o zero'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  unstable
                      ? 'Unstable: at least one pole is on or outside the unit circle.'
                      : 'Stable: every pole is strictly inside the unit circle.',
                  style: TextStyle(
                    fontSize: 12,
                    color: unstable ? Colors.red : Colors.green.shade700,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
