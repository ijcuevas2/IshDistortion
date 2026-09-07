import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_latex/sd_latex.dart';

import 'document_listenable.dart';

/// A live `H(z)` readout via Mason's gain formula (§4/§10's "Compute
/// transfer function (Mason)"), recomputed from the document's current
/// `source`/`sink` blocks whenever it changes. Rendered as real typeset
/// math (`Expr.toTex()` through `sd_latex`'s [LatexLabel]), not a plain
/// monospace expression string. See `PoleZeroPanel` for pole-zero
/// analysis (§4/§5.11) of this same `H(z)`.
class TransferFunctionPanel extends StatefulWidget {
  const TransferFunctionPanel({super.key, required this.document});

  final SdDocument document;

  @override
  State<TransferFunctionPanel> createState() => _TransferFunctionPanelState();
}

class _TransferFunctionPanelState extends State<TransferFunctionPanel> {
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
        final result = hasLoop ? null : computeTransferFunction(graph);

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasLoop) ...[
                Text('H(z)', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                const Text(
                  'Cannot compute: the diagram has an algebraic (delay-free) loop.',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ] else if (result == null) ...[
                Text('H(z)', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                const Text(
                  'Place a "source" and a "sink" block to compute a transfer function.',
                  style: TextStyle(fontSize: 12),
                ),
              ] else
                LatexLabel(
                  'H(z) = ${result.h.toTex()}',
                  style: const TextStyle(fontSize: 16),
                ),
            ],
          ),
        );
      },
    );
  }
}
