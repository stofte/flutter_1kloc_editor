import 'package:flutter/material.dart';
import 'package:flutter_1kloc_editor/document.dart';
import 'package:flutter_1kloc_editor/editor_config.dart';
import 'package:flutter_1kloc_editor/editor_notifier.dart';

class EditorPainter extends CustomPainter {
  EditorConfig config;
  EditorNotifier notifier;
  late Document doc;
  late TextPainter tp;
  final stopwatch = Stopwatch();

  EditorPainter(this.config, this.notifier) : super(repaint: notifier) {
    tp = TextPainter(textDirection: TextDirection.ltr);
    doc = notifier.doc.doc;
    stopwatch.start();
  }

  @override
  void paint(Canvas canvas, Size size) {
    stopwatch.reset();

    var renderedGlyphHeight = doc.renderedGlyphHeight;
    var hOffset = notifier.hOffset();
    var vOffset = notifier.vOffset() / renderedGlyphHeight;
    var startLine = vOffset.floor();
    var startVOffset = -1 * renderedGlyphHeight * (vOffset - startLine);

    var offset = Offset(config.canvasMargin - hOffset, config.canvasMargin + startVOffset);
    var renderedHeight = 0.0;

    for (var i = startLine; i < doc.lines.length && renderedHeight < size.height; i++) {
      var txt = doc.lines[i];
      tp.text = TextSpan(text: txt, style: config.textStyle);
      tp.layout();
      assert(tp.height <= renderedGlyphHeight);
      if (tp.height < renderedGlyphHeight) {
        var diff = renderedGlyphHeight - tp.height;
        tp.paint(canvas, Offset(offset.dx, offset.dy + diff));
      } else {
        tp.paint(canvas, offset);
      }
      offset = Offset(offset.dx, offset.dy + renderedGlyphHeight);
      renderedHeight += renderedGlyphHeight;
    }
    print("paint: ${stopwatch.elapsedMicroseconds} us");
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
