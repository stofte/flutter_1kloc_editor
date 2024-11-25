import 'package:flutter/material.dart';
import 'package:flutter_1kloc_editor/document_provider.dart';

/// Wraps all notifiers which can affect the rendering of the UI
class EditorNotifier with ChangeNotifier {
  DocumentProvider doc;
  ScrollController vScroll;
  ScrollController hScroll;

  EditorNotifier(this.doc, this.vScroll, this.hScroll) {
    vScroll.addListener(() => notifyListeners());
    hScroll.addListener(() => notifyListeners());
    doc.addListener(() => notifyListeners());
  }

  double vOffset() => vScroll.offset;
  double hOffset() => hScroll.offset;
}
