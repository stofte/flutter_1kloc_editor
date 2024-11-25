import 'dart:io';

import 'package:flutter/material.dart';

class DocumentLocation {
  int line;
  int column;
  DocumentLocation(this.line, this.column);

  @override
  bool operator ==(covariant DocumentLocation other) {
    return other.line == line && other.column == column;
  }

  @override
  int get hashCode => line.hashCode ^ column.hashCode;
}

class Document {
  List<String> lines = [''];
  List<double> widths = [];

  DocumentLocation cursor = DocumentLocation(0, 0);
  DocumentLocation anchor = DocumentLocation(0, 0);

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

  bool setCursorFromOffset(Offset offset, double vScrollOffset, double hScrollOffset) {
    // Assumes that the offset has been adjusted for canvas margins, etc
    var lineNum = ((vScrollOffset + offset.dy) / renderedGlyphHeight).floor();
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
