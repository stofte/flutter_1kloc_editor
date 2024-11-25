import 'package:flutter/material.dart';
import 'package:flutter_1kloc_editor/document.dart';
import 'package:flutter_1kloc_editor/tree_sitter.dart';

class DocumentProvider extends ChangeNotifier {
  TextStyle textStyle;
  late Document doc;

  DocumentProvider(this.textStyle, TreeSitter treeSitter, Map<String, Color> syntaxColoring) {
    doc = Document(textStyle, treeSitter, syntaxColoring);
  }

  Future<bool> openFile(String path) async {
    var stopwatch = Stopwatch();
    stopwatch.start();
    bool res = await doc.openFile(path);
    print("openFile: ${stopwatch.elapsedMilliseconds} ms");
    touch();
    return res;
  }

  void touch() {
    notifyListeners();
  }
}
