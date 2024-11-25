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
    var lineCount = ((size.height - config.canvasMargin) / renderedGlyphHeight).ceil();
    var offset = Offset(config.canvasMargin - hOffset, config.canvasMargin + startVOffset);
    var textResult = doc.getText(startLine, lineCount, config.textStyle);
    var offsetY = 0.0;
    if (textResult.hasSelection) {
      for (var i = 0; i < textResult.text.length; i++) {
        var lineIdx = startLine + i;
        if (textResult.selectionStart.line <= lineIdx && lineIdx <= textResult.selectionEnd.line) {
          // We want to draw a box behind the selection, so we need to go
          // into the text elements and see which ones are selected or not.
          // We also do not care about the text after the selection ends, we do
          // not needs it's size information.

          List<InlineSpan> txtBeforeSel = [];
          List<InlineSpan> txtSel = [];
          var foundSelection = false;

          for (var j = 0; j < textResult.text[i].length; j++) {
            if (textResult.text[i][j] is TextSpanEx) {
              var span = textResult.text[i][j] as TextSpanEx;
              if (span.isNewline) {
                continue;
              }
              if (span.isSelected) {
                foundSelection = true;
                txtSel.add(span);
              } else if (!foundSelection) {
                txtBeforeSel.add(span);
              }
            }
          }

          tp.text = TextSpan(children: txtBeforeSel, style: config.textStyle);
          tp.layout();
          var preSelectionW = tp.width;
          tp.text = TextSpan(children: txtSel, style: config.textStyle);
          tp.layout();
          var selectionW = tp.width;
          var rect = Rect.fromLTRB(offset.dx + preSelectionW, offset.dy + offsetY,
              offset.dx + preSelectionW + selectionW, offset.dy + offsetY + renderedGlyphHeight);
          canvas.drawRect(rect, config.selectionPaint);
        }
        offsetY += doc.renderedGlyphHeight;
      }
    }

    tp.text = TextSpan(children: textResult.text.expand((x) => x).toList());
    tp.setPlaceholderDimensions(textResult.placeholderDimensions);
    tp.layout();
    tp.paint(canvas, offset);

    print("paint: ${stopwatch.elapsedMicroseconds} us");
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
