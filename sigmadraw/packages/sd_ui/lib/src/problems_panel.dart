import 'package:flutter/material.dart';
import 'package:sd_document/sd_document.dart';
import 'package:sd_graph/sd_graph.dart';
import 'package:sd_render/sd_render.dart';

import 'document_listenable.dart';

/// The Problems panel (§4/§10): every [ValidationIssue] from re-running
/// `validate()` on the document's current [SignalGraph], refreshed live as
/// the document changes. Tapping a row jumps to (selects) its block, when
/// it names one.
class ProblemsPanel extends StatefulWidget {
  const ProblemsPanel({super.key, required this.document, this.selection});

  final SdDocument document;
  final SelectionModel? selection;

  @override
  State<ProblemsPanel> createState() => _ProblemsPanelState();
}

class _ProblemsPanelState extends State<ProblemsPanel> {
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
        final issues = validate(SignalGraph.fromDocument(widget.document));
        if (issues.isEmpty) {
          return const Center(
            child: Text('No problems found.', style: TextStyle(fontSize: 12)),
          );
        }
        return ListView.builder(
          itemCount: issues.length,
          itemBuilder: (context, index) => _IssueRow(
            issue: issues[index],
            onTap: () => _jumpTo(issues[index]),
          ),
        );
      },
    );
  }

  void _jumpTo(ValidationIssue issue) {
    final selection = widget.selection;
    final blockId = issue.blockId;
    if (selection == null || blockId == null) return;
    for (final element in widget.document.root.descendantElements) {
      if (element.blockId == blockId) {
        selection.selectOnly(element);
        return;
      }
    }
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, required this.onTap});

  final ValidationIssue issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (issue.severity) {
      Severity.error => (Icons.error, Colors.red),
      Severity.warning => (Icons.warning_amber, Colors.orange),
      Severity.info => (Icons.info_outline, Colors.blueGrey),
    };
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 18),
      title: Text(issue.message, style: const TextStyle(fontSize: 12)),
      onTap: onTap,
    );
  }
}
