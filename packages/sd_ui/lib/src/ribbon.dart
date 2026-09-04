import 'package:flutter/material.dart';

/// One clickable command inside a [RibbonGroup] — e.g. "Undo", "Copy",
/// "Zoom In". A `null` [onPressed] renders (and behaves) disabled, the
/// same convention `IconButton`/`SegmentedButton` already use everywhere
/// else in this app, so callers computing reactive enabled-state (e.g.
/// "Undo" only while `UndoStack.canUndo`) don't need any new pattern.
class RibbonAction {
  const RibbonAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Defaults to [label] when omitted.
  final String? tooltip;
}

/// A titled cluster of controls inside a [RibbonTab] — Office's "group":
/// a caption (e.g. "Clipboard", "Zoom") underneath a row of controls.
/// [actions] renders as icon-over-label buttons; [child], when given, is
/// appended after them for a control a plain [RibbonAction] can't express
/// (e.g. the Select/Ink tool [SegmentedButton]). A group needs at least
/// one of the two — an empty group is never meaningful.
class RibbonGroup {
  const RibbonGroup({required this.title, this.actions = const [], this.child});

  final String title;
  final List<RibbonAction> actions;
  final Widget? child;
}

/// One tab's worth of [RibbonGroup]s (e.g. "Home", "Insert").
class RibbonTab {
  const RibbonTab({required this.title, required this.groups});

  final String title;
  final List<RibbonGroup> groups;
}

/// A hand-rolled, minimal ribbon (§10): a row of tab titles above a row of
/// captioned [RibbonGroup]s for whichever tab is selected — the general
/// tabs-of-labeled-command-clusters shape common to Office/WPS/LibreOffice
/// ribbons, built from plain Material widgets rather than a pixel copy of
/// any one of them (deliberately out of scope — see the project brief's
/// own "do not pixel-copy Office ribbon chrome"). Purely data-driven off
/// [tabs], so callers needing reactive enabled-state (most of them) just
/// rebuild the `List<RibbonTab>` they pass in — typically from inside a
/// `ListenableBuilder`/`AnimatedBuilder` — rather than this widget needing
/// any awareness of *why* an action is or isn't enabled right now.
class Ribbon extends StatefulWidget {
  const Ribbon({super.key, required this.tabs});

  final List<RibbonTab> tabs;

  @override
  State<Ribbon> createState() => _RibbonState();
}

class _RibbonState extends State<Ribbon> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final selected = _selected.clamp(0, widget.tabs.length - 1);
    final tab = widget.tabs[selected];
    return Material(
      elevation: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (i, t) in widget.tabs.indexed)
                InkWell(
                  onTap: () => setState(() => _selected = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: i == selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Text(
                      t.title,
                      style: TextStyle(
                        fontWeight: i == selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 1),
          SizedBox(
            height: 92,
            // Scrolls horizontally rather than overflowing once a tab's
            // groups don't all fit — an ordinary ribbon (this ribbon's
            // own Home tab, once it grew a File group on top of
            // Undo/Clipboard/Tools/Zoom, included) can outgrow a narrow
            // window; a real one wraps to a second row or collapses
            // groups, but scrolling is the simplest correct behavior
            // that never clips content unreachably.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in tab.groups) ...[
                    _RibbonGroupView(group: group),
                    const VerticalDivider(width: 1),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RibbonGroupView extends StatelessWidget {
  const _RibbonGroupView({required this.group});

  final RibbonGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final action in group.actions)
                  _RibbonActionButton(action: action),
                if (group.child != null) group.child!,
              ],
            ),
          ),
          Text(group.title, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _RibbonActionButton extends StatelessWidget {
  const _RibbonActionButton({required this.action});

  final RibbonAction action;

  @override
  Widget build(BuildContext context) {
    // The whole control (icon + caption) is one tap target, wrapped in an
    // InkWell around the IconButton it contains — a real ribbon button's
    // label is clickable too, not just its icon. The inner IconButton
    // stays a real, independently-findable widget (existing finders like
    // `find.widgetWithIcon(IconButton, ...)` keep working unchanged); the
    // outer InkWell only ever catches a tap that lands *outside* it, on
    // the caption below — Flutter's gesture arena resolves the overlap
    // correctly rather than double-firing.
    return SizedBox(
      width: 64,
      child: InkWell(
        onTap: action.onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(action.icon),
              tooltip: action.tooltip ?? action.label,
              onPressed: action.onPressed,
            ),
            Text(
              action.label,
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
