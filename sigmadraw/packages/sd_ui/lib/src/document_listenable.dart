import 'package:flutter/foundation.dart';
import 'package:sd_document/sd_document.dart';

/// Bridges [SdDocument.changes] (a dependency-free `SdChangeNotifier`,
/// since `sd_document` can't depend on Flutter) to a real Flutter
/// [ChangeNotifier], for any widget that wants to rebuild on document
/// edits without owning a full `Scene` (`sd_render`, which does this same
/// bridging for the canvas itself — see its doc comment).
class DocumentListenable extends ChangeNotifier {
  DocumentListenable(this.document) {
    document.changes.addListener(notifyListeners);
  }

  final SdDocument document;

  @override
  void dispose() {
    document.changes.removeListener(notifyListeners);
    super.dispose();
  }
}
