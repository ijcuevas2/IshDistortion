import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

import 'document_listenable.dart';

/// A live impulse/step response plot (§5.11's "Analysis Plot —
/// impulse/step stem") from the same Mason-derived `H(z)`
/// `TransferFunctionPanel`/`PoleZeroPanel`/`BodePanel`/`NyquistPanel`/
/// `SpectrogramPanel`/`GroupDelayPanel` show, recomputed whenever the
/// document changes: `H`'s own simulated reaction to an impulse and to
/// a step, the same "needs an actual simulated signal" shape
/// `SpectrogramPanel`'s own doc comment explains for the spectrogram.
///
/// [computeImpulseResponse]/[computeStepResponse] need concrete numbers
/// (unlike Mason's formula itself, which stays meaningful fully
/// symbolic), so this panel shares [PoleZeroPanel]'s three message
/// states — no source/sink, an algebraic loop, or an unresolved
/// coefficient symbol.
class ImpulseStepPanel extends StatefulWidget {
  const ImpulseStepPanel({super.key, required this.document});

  final SdDocument document;

  @override
  State<ImpulseStepPanel> createState() => _ImpulseStepPanelState();
}

class _ImpulseStepPanelState extends State<ImpulseStepPanel> {
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
        final impulse = transferFunction == null
            ? null
            : computeImpulseResponse(transferFunction.h);
        final step = transferFunction == null
            ? null
            : computeStepResponse(transferFunction.h);

        String? message;
        if (hasLoop) {
          message =
              'Cannot compute: the diagram has an algebraic (delay-free) loop.';
        } else if (transferFunction == null) {
          message = 'Place a "source" and a "sink" block to compute a transfer function.';
        } else if (impulse == null || step == null) {
          message =
              'Cannot plot: one or more coefficients is still an unresolved '
              'parameter (e.g. a gain left as a symbol rather than a number).';
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Impulse / Step Response',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              if (message != null)
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasLoop ? Colors.red : null,
                  ),
                )
              else
                Expanded(
                  child: CustomPaint(
                    painter: ImpulseStepPainter(impulse: impulse, step: step),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
