import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

import 'document_listenable.dart';

/// A live spectrogram (§5.11's "Analysis Plot — spectrogram") of the same
/// Mason-derived `H(z)` [TransferFunctionPanel]/[PoleZeroPanel]/
/// [BodePanel]/[NyquistPanel] show, recomputed whenever the document
/// changes: `H`'s own simulated response to a chirp, plotted as
/// magnitude vs. time and frequency (see [computeSpectrogram]'s own doc
/// comment for why a spectrogram needs an actual simulated signal, not
/// just `H(z)` evaluated at points, unlike the other three plots).
///
/// [computeSpectrogram] needs concrete numbers (unlike Mason's formula
/// itself, which stays meaningful fully symbolic), so this panel shares
/// [PoleZeroPanel]/[BodePanel]/[NyquistPanel]'s three message states — no
/// source/sink, an algebraic loop, or an unresolved coefficient symbol.
class SpectrogramPanel extends StatefulWidget {
  const SpectrogramPanel({super.key, required this.document});

  final SdDocument document;

  @override
  State<SpectrogramPanel> createState() => _SpectrogramPanelState();
}

class _SpectrogramPanelState extends State<SpectrogramPanel> {
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
        final frames = transferFunction == null
            ? null
            : computeSpectrogram(transferFunction.h);

        String? message;
        if (hasLoop) {
          message =
              'Cannot compute: the diagram has an algebraic (delay-free) loop.';
        } else if (transferFunction == null) {
          message = 'Place a "source" and a "sink" block to compute a transfer function.';
        } else if (frames == null) {
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
                'Spectrogram',
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
              else ...[
                Expanded(
                  child: CustomPaint(
                    painter: SpectrogramPainter(frames: frames),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Response to a DC-to-Nyquist chirp; time left to right, '
                  'DC to Nyquist bottom to top.',
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
