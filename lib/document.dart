import 'dart:io';

import 'package:flutter/material.dart';

class Document {
  List<String> lines = [''];
  List<double> heights = [];
  List<double> widths = [];

  TextDirection textDirection = TextDirection.ltr;
  TextStyle style;

  late TextPainter tp;
  late String path;

  Document(this.style) {
    tp = TextPainter(textDirection: textDirection);
  }

  Future<bool> openFile(String path) async {
    this.path = path;
    lines = await File(this.path).readAsLines();
    heights = List.filled(lines.length, 0, growable: true);
    widths = List.filled(lines.length, 0, growable: true);
    for (var i = 0; i < lines.length; i++) {
      tp.text = TextSpan(text: lines[i], style: style);
      tp.layout();
      heights[i] = tp.height;
      widths[i] = tp.width;
    }
    return true;
  }

  Size getSize() {
    var h = heights.fold(0.0, (acc, val) => acc + val);
    var w = widths.fold(0.0, (max, val) => val > max ? val : max);
    return Size(w, h);
  }

  (int, double) getLineAndOffset(double vOffset) {
    var i = 0;
    var a = 0.0;
    for (; i < heights.length; i++) {
      if (a + heights[i] > vOffset) {
        break;
      } else {
        a += heights[i];
      }
    }
    return (i, -1 * (vOffset - a));
  }
}
