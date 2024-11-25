import 'dart:io';

import 'package:flutter/material.dart';

class Document {
  List<String> lines = [''];
  List<double> widths = [];

  TextDirection textDirection = TextDirection.ltr;
  TextStyle style;

  // This is the height of the "█" char, which should be as tall as fx smileys and kanji.
  // Regular ASCII symbols are not as tall, so this should allow a consistent line height.
  late double renderedGlyphHeight;

  late TextPainter tp;
  late String path;

  Document(this.style) {
    tp = TextPainter(textDirection: textDirection);
    tp.text = TextSpan(text: '\u2288', style: style);
    tp.layout();
    renderedGlyphHeight = tp.height;
  }

  Future<bool> openFile(String path) async {
    this.path = path;
    lines = await File(this.path).readAsLines();
    widths = List.filled(lines.length, 0, growable: true);
    for (var i = 0; i < lines.length; i++) {
      tp.text = TextSpan(text: lines[i], style: style);
      tp.layout();
      widths[i] = tp.width;
    }
    return true;
  }

  Size getSize() {
    var h = lines.length * renderedGlyphHeight;
    var w = widths.fold(0.0, (max, val) => val > max ? val : max);
    return Size(w, h);
  }
}
