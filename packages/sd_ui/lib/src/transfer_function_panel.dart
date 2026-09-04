import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';

import 'document_listenable.dart';

/// A live `H(z)` readout via Mason's gain formula (§4/§10's "Compute
/// transfer function (Mason)"), recomputed from the document's current
/// `source`/`sink` blocks whenever it changes. Pole-zero generation from
/// this H(z) (§4/§5.11) is not implemented yet.
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
              Text('H(z)', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              if (hasLoop)
                const Text(
                  'Cannot compute: the diagram has an algebraic (delay-free) loop.',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                )
              else if (result == null)
                const Text(
                  'Place a "source" and a "sink" block to compute a transfer function.',
                  style: TextStyle(fontSize: 12),
                )
              else
                SelectableText(
                  '${result.h}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
            ],
          ),
        );
      },
    );
  }
}
