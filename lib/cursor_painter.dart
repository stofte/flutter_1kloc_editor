import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_1kloc_editor/document_provider.dart';
import 'package:flutter_1kloc_editor/editor_config.dart';

class CursorPainter extends CustomPainter {
  ScrollController vScroll;
  ScrollController hScroll;
  DocumentProvider doc;
  EditorConfig config;
  CursorBlinkTimer timer;
  TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
  Paint cursorPaint = Paint();

  CursorPainter(
      {required this.config, required this.timer, required this.doc, required this.vScroll, required this.hScroll})
      : super(repaint: timer) {
    cursorPaint.color = Colors.white;
    cursorPaint.style = PaintingStyle.fill;
    cursorPaint.blendMode = BlendMode.difference;
    cursorPaint.isAntiAlias = false;
  }

  @override
  bool shouldRepaint(CursorPainter oldDelegate) => true;

  @override
  void paint(Canvas canvas, Size size) {
    if (timer.visible) {
      var glyphHeight = doc.doc.renderedGlyphHeight;
      var cursorHOffset = hScroll.offset - config.canvasMargin - doc.doc.imeCursorOffset;
      // TODO: Figure out why this 1 needs to be here!
      var cursorVOffset = vScroll.offset - config.canvasMargin - 1;
      var cursorOffset = doc.doc.getCursorOffset();
      var scrollOffset = Offset(cursorHOffset, cursorVOffset);
      var pos = cursorOffset - scrollOffset;
      // We always show the full cursor, if any of it is visible
      var cursorR = Rect.fromLTRB(pos.dx, pos.dy - 1, pos.dx + 2, pos.dy + glyphHeight + 1);
      canvas.drawRect(cursorR, cursorPaint);
    }
  }
}

class CursorBlinkTimer with ChangeNotifier {
  late Timer timer;
  bool visible = false;
  // Indicates if we should keep the cursor on screen. This can be the case when:
  // - Moving the cursor by arrow keys (or other keyboard inputs, such as enter)
  // - Moving the cursor by selecting text (and dragging the cursor off canvas)
  bool keepOnScreen = false;

  CursorBlinkTimer() {
    timer = Timer.periodic(const Duration(milliseconds: 500), timerTicks);
  }

  void timerTicks(Timer timer) {
    visible = !visible;
    notifyListeners();
  }

  void showNow() {
    visible = true;
    timer.cancel();
    timer = Timer.periodic(const Duration(milliseconds: 500), timerTicks);
    notifyListeners();
  }
}
