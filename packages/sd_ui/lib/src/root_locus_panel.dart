import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

import 'document_listenable.dart';

/// A live root-locus plot (§5.11's "Analysis Plot — root locus") from
/// the same Mason-derived `H(z)` `TransferFunctionPanel`/`PoleZeroPanel`/
/// etc. show, recomputed whenever the document changes — but unlike
/// every other analysis panel here, root locus's *whole point* is
/// sweeping a still-*unresolved* coefficient (e.g. a `gain` block left
/// as a symbol rather than a number), not treating one as an error
/// state. This panel finds that coefficient automatically via
/// [Expr.freeSymbols] rather than asking the user to name it:
///
/// - **Zero** free symbols: `H(z)` is already fully concrete, so
///   there's nothing to sweep — a message, the same shape every other
///   panel's "unresolved parameter" message is, just for the opposite
///   condition.
/// - **Exactly one**: swept from [sweepStart] to [sweepEnd] (default
///   `0` to `2`, the conventional "gain `K` from `0` upward" root-locus
///   convention — a fixed default, not yet exposed as an adjustable UI
///   control; a real, disclosed simplification, not a silent one).
/// - **More than one**: root locus needs exactly one swept coefficient
///   to mean anything — a message naming which symbols were found,
///   since there's no principled way to auto-pick among several.
class RootLocusPanel extends StatefulWidget {
  const RootLocusPanel({
    super.key,
    required this.document,
    this.sweepStart = 0,
    this.sweepEnd = 2,
  });

  final SdDocument document;
  final double sweepStart;
  final double sweepEnd;

  @override
  State<RootLocusPanel> createState() => _RootLocusPanelState();
}

class _RootLocusPanelState extends State<RootLocusPanel> {
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
        final freeSymbols = transferFunction?.h.freeSymbols;

        List<RootLocusSample>? samples;
        String? message;
        if (hasLoop) {
          message =
              'Cannot compute: the diagram has an algebraic (delay-free) loop.';
        } else if (transferFunction == null) {
          message = 'Place a "source" and a "sink" block to compute a transfer function.';
        } else if (freeSymbols!.isEmpty) {
          message =
              'Nothing to sweep: every coefficient already has a concrete '
              'value. Root locus needs one left as a symbol (e.g. a gain '
              'parameter set to a letter like "k" instead of a number).';
        } else if (freeSymbols.length > 1) {
          message =
              'Root locus needs exactly one unresolved parameter to sweep; '
              'found ${freeSymbols.length}: ${freeSymbols.join(', ')}.';
        } else {
          samples = computeRootLocus(
            transferFunction.h,
            parameter: freeSymbols.single,
            start: widget.sweepStart,
            end: widget.sweepEnd,
          );
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Root Locus',
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
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: RootLocusPainter(samples: samples),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sweeping "${freeSymbols!.single}" from '
                  '${widget.sweepStart} to ${widget.sweepEnd}.',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
