import 'package:flutter/foundation.dart';
import 'package:sd_document/sd_document.dart';

/// Which elements are currently selected on the canvas.
///
/// Phase 2 scope: single-select and marquee-select only (§9's
/// group/ungroup/lasso/z-order land with the ribbon and semantic graph in
/// later phases).
class SelectionModel extends ChangeNotifier {
  final Set<SdElement> _selected = {};

  Set<SdElement> get selected => Set.unmodifiable(_selected);

  bool get isEmpty => _selected.isEmpty;

  bool isSelected(SdElement element) => _selected.contains(element);

  void selectOnly(SdElement? element) {
    _selected.clear();
    if (element != null) _selected.add(element);
    notifyListeners();
  }

  void selectAll(Iterable<SdElement> elements) {
    _selected
      ..clear()
      ..addAll(elements);
    notifyListeners();
  }

  void toggle(SdElement element) {
    if (!_selected.remove(element)) _selected.add(element);
    notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }
}
