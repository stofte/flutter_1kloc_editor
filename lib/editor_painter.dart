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
    var selectedRects = doc.getSelectionRects(startLine, lineCount, config.textStyle, offset);

    for (var i = 0; i < selectedRects.length; i++) {
      var r = selectedRects[i];
      canvas.drawRect(r, config.selectionPaint);
    }

    tp.text = TextSpan(children: textResult.text);
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
