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

  double paintText(String text, Offset offset, Canvas canvas, double renderedGlyphHeight, bool isSelection) {
    tp.text = TextSpan(text: text, style: config.textStyle);
    tp.layout();
    assert(tp.height <= renderedGlyphHeight);

    if (isSelection) {
      var rect = Rect.fromLTRB(offset.dx, offset.dy + 1, offset.dx + tp.width, offset.dy + renderedGlyphHeight + 1);
      rect.inflate(1);
      canvas.drawRect(rect, config.selectionPaint);
    }
    if (tp.height < renderedGlyphHeight) {
      var diff = renderedGlyphHeight - tp.height;
      tp.paint(canvas, Offset(offset.dx, offset.dy + diff));
    } else {
      tp.paint(canvas, offset);
    }
    return tp.width;
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

    var hasSelection = doc.hasSelection();
    var selStart = doc.getSelectionStart();
    var selEnd = doc.getSelectionEnd();

    for (var i = startLine; i < doc.lines.length && renderedHeight < size.height; i++) {
      var line = doc.lines[i];
      var dx = offset.dx;
      if (i == doc.cursor.line && doc.imeBufferWidth > 0) {
        var cs = doc.lines[i].characters;
        var txt1 = cs.take(doc.cursor.column).toString();
        var txt2 = cs.skip(doc.cursor.column).take(cs.length - doc.cursor.column).toString();
        var width = paintText(txt1, offset, canvas, renderedGlyphHeight, false);
        offset = Offset(offset.dx + width + doc.imeBufferWidth, offset.dy);
        paintText(txt2, offset, canvas, renderedGlyphHeight, false);
        offset = Offset(dx, offset.dy);
      } else if (hasSelection && selStart.line <= i && i <= selEnd.line) {
        var lineSelStart = i == selStart.line ? selStart.column : 0;
        var lineSelEnd = i == selEnd.line ? selEnd.column : line.characters.length;
        assert(lineSelStart <= lineSelEnd);
        var lineSegments = splitLineInto(line, lineSelStart, lineSelEnd);
        var width = paintText(lineSegments[0], offset, canvas, renderedGlyphHeight, false);
        offset = Offset(offset.dx + width, offset.dy);
        width = paintText(lineSegments[1], offset, canvas, renderedGlyphHeight, true);
        offset = Offset(offset.dx + width, offset.dy);
        width = paintText(lineSegments[2], offset, canvas, renderedGlyphHeight, false);
        offset = Offset(dx, offset.dy);
      } else {
        var txt = doc.lines[i];
        paintText(txt, offset, canvas, renderedGlyphHeight, false);
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

  List<String> splitLineInto(String line, int startIndex, int endIndex) {
    return [
      line.characters.take(startIndex).toString(),
      line.characters.skip(startIndex).take(endIndex - startIndex).toString(),
      line.characters.skip(endIndex).take(line.characters.length - endIndex).toString()
    ];
  }
}
