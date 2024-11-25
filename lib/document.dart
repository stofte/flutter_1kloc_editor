import 'dart:io';

import 'package:flutter/material.dart';

class DocumentLocation {
  int line;
  int column;
  DocumentLocation(this.line, this.column);
}

class Document {
  List<String> lines = [''];
  List<double> widths = [];

  DocumentLocation cursor = DocumentLocation(0, 0);
  DocumentLocation? anchor;
  // When composing using IME, we have buffered input in the IME editor. It's not part of the document,
  // but we need to account for it, such as giving it space when displaying the line being edited.
  double imeBufferWidth = 0;
  // This value indicates the placement of the cursor, inside the IME editing buffer, as a columnar
  // offset only. This assumes that the IME inpue does no wrap to multiple lines.
  double imeCursorOffset = 0;

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

  // Inserts the text at the cursor position
  (Offset, DocumentLocation) insertText(String text) {
    var l = lines[cursor.line];
    var l1st = l.characters.take(cursor.column);
    var l2nd = l.characters.skip(cursor.column).take(l.characters.length - cursor.column);
    lines[cursor.line] = "$l1st$text$l2nd";
    tp.text = TextSpan(text: lines[cursor.line], style: style);
    tp.layout();
    widths[cursor.line] = tp.width;
    cursor.column += text.characters.length;
    return (Offset(tp.width, 0), cursor);
  }

  Size getSize() {
    var h = lines.length * renderedGlyphHeight;
    var w = widths.fold(0.0, (max, val) => val > max ? val : max);
    return Size(w, h);
  }

  Offset getCursorOffset() {
    var l = lines[cursor.line];
    var before = l.characters.take(cursor.column).toString();
    tp.text = TextSpan(text: before, style: style);
    tp.layout();
    return Offset(tp.width, cursor.line * renderedGlyphHeight);
  }

  bool setCursorFromOffset(Offset offset, bool initial) {
    if (initial) {
      // Clears anchor on initial
      anchor = null;
    } else {
      anchor ??= DocumentLocation(cursor.line, cursor.column);
    }
    // Assumes that the offset has been adjusted for canvas margins, etc
    var lineNum = (offset.dy / renderedGlyphHeight).floor();
    if (lineNum < 0) {
      lineNum = 0;
    } else if (lineNum >= lines.length) {
      lineNum = lines.length - 1;
    }
    var colNum = _findCharIndexInStringFromOffset(lines[lineNum], offset.dx, 0);
    var newCursor = DocumentLocation(lineNum, colNum);
    var changed = cursor != newCursor;
    cursor = newCursor;
    return changed;
  }

  bool moveCursorLeft() {
    var anchorWasNotNull = anchor != null;
    anchor = null;
    if (cursor.column == 0 && cursor.line > 0) {
      cursor.line--;
      cursor.column = lines[cursor.line].characters.length;
      return true;
    } else if (cursor.column > 0) {
      cursor.column--;
      return true;
    }
    // If the anchor was cleared, we return true as well
    return anchorWasNotNull;
  }

  bool moveCursorRight() {
    var anchorWasNotNull = anchor != null;
    anchor = null;
    var thisLineLength = lines[cursor.line].characters.length;
    if (cursor.column == thisLineLength && cursor.line < lines.length - 1) {
      cursor.line++;
      cursor.column = 0;
      return true;
    } else if (cursor.column < thisLineLength) {
      cursor.column++;
      return true;
    }
    return anchorWasNotNull;
  }

  bool moveCursorUp() {
    var anchorWasNotNull = anchor != null;
    anchor = null;
    if (cursor.line > 0) {
      // We try to find the closest match to the current visual column offset in the line up.
      var colOffset = _currentColOffset();
      cursor.line--;
      cursor.column = _findCharIndexInStringFromOffset(lines[cursor.line], colOffset, 0);
      return true;
    }
    return anchorWasNotNull;
  }

  bool moveCursorDown() {
    var anchorWasNotNull = anchor != null;
    anchor = null;
    if (cursor.line < lines.length - 1) {
      var colOffset = _currentColOffset();
      cursor.line++;
      cursor.column = _findCharIndexInStringFromOffset(lines[cursor.line], colOffset, 0);
      return true;
    }
    return anchorWasNotNull;
  }

  bool hasSelection() {
    return anchor != null && (cursor.line != anchor?.line || cursor.column != anchor?.column);
  }

  DocumentLocation getSelectionStart() {
    return _getSelectionStartOrEnd(true);
  }

  DocumentLocation getSelectionEnd() {
    return _getSelectionStartOrEnd(false);
  }

  DocumentLocation _getSelectionStartOrEnd(bool start) {
    if (anchor != null) {
      // Should never be -1, but dart does not seem clever enough here?
      var aLine = anchor?.line ?? -1;
      var aCol = anchor?.column ?? -1;
      var anchor2 = DocumentLocation(aLine, aCol);
      if (anchor2.line < cursor.line || anchor2.line == cursor.line && anchor2.column < cursor.column) {
        // anchor is before cursor:
        return start ? anchor2 : cursor;
      } else {
        return start ? cursor : anchor2;
      }
    } else {
      return cursor;
    }
  }

  double _currentColOffset() {
    var l = lines[cursor.line];
    tp.text = TextSpan(text: l.characters.take(cursor.column).toString(), style: style);
    tp.layout();
    return tp.width;
  }

  int _findCharIndexInStringFromOffset(String text, double offset, int index) {
    if (text.isEmpty) {
      return index;
    } else if (text.characters.length == 1) {
      // Find out which side of the char, we should return
      tp.text = TextSpan(text: text, style: style);
      tp.layout();
      if (offset <= (tp.width / 2)) {
        return index;
      } else {
        return index + 1;
      }
    } else {
      // Text is at least two chars here
      var midpoint = (text.characters.length / 2).floor();
      var halfStr = text.characters.take(midpoint).toString();
      tp.text = TextSpan(text: halfStr, style: style);
      tp.layout();
      var w = tp.width;
      if (offset <= w) {
        return _findCharIndexInStringFromOffset(halfStr, offset, index);
      } else {
        var otherHalfStr = text.characters.skip(midpoint).toString();
        return _findCharIndexInStringFromOffset(otherHalfStr, offset - w, index + midpoint);
      }
    }
  }
}
