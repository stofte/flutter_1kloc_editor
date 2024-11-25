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

  void paintText(String text, Offset offset, Canvas canvas, double renderedGlyphHeight) {
    tp.text = TextSpan(text: text, style: config.textStyle);
    tp.layout();
    assert(tp.height <= renderedGlyphHeight);
    if (tp.height < renderedGlyphHeight) {
      var diff = renderedGlyphHeight - tp.height;
      tp.paint(canvas, Offset(offset.dx, offset.dy + diff));
    } else {
      tp.paint(canvas, offset);
    }
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
      if (i == doc.cursor.line && doc.imeBufferWidth > 0) {
        var dx = offset.dx;
        var cs = doc.lines[i].characters;
        var txt1 = cs.take(doc.cursor.column).toString();
        var txt2 = cs.skip(doc.cursor.column).take(cs.length - doc.cursor.column).toString();
        paintText(txt1, offset, canvas, renderedGlyphHeight);
        offset = Offset(offset.dx + tp.width + doc.imeBufferWidth, offset.dy);
        paintText(txt2, offset, canvas, renderedGlyphHeight);
        offset = Offset(dx, offset.dy);
      } else {
        var txt = doc.lines[i];
        paintText(txt, offset, canvas, renderedGlyphHeight);
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
