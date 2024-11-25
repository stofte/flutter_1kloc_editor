import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_1kloc_editor/tree_sitter.dart';

// Customizable TextSpan which can be fed into TextPainter, but allows us to store some metadata
class TextSpanEx extends TextSpan {
  final bool isNewline;
  final bool isSpacing;
  final bool isSelected;
  TextSpanEx(String text, TextStyle style, this.isNewline, this.isSpacing, this.isSelected)
      : super(text: text, style: style);
}

class RenderTextResult {
  // The text to be rendered, split into lines. If a selection is present, the text is also
  // split at the location selection begins and ends. Each
  final List<List<InlineSpan>> text;

  final List<PlaceholderDimensions> placeholderDimensions;
  // If we have any selection in the returned text, we indicate it here,
  // using the selection range that was used to compute the text lists.
  final bool hasSelection;
  final DocumentLocation selectionStart;
  final DocumentLocation selectionEnd;
  RenderTextResult(this.text, this.placeholderDimensions, this.hasSelection, this.selectionStart, this.selectionEnd);
}

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

  // TODO: this should probably all live in the editor_painter, and not here. The document
  // should not be concerned with it's rendered height, etc.
  late double renderedGlyphHeight;

  late TextPainter tp;
  late String path;

  final TreeSitter treeSitter;

  Document(this.style, this.treeSitter) {
    tp = TextPainter(textDirection: textDirection);
    // More flutter snafu, must have at least two lines of text. There is presumably
    // something going on between the lines which is messing with the algorithm.

    tp.text = TextSpan(text: '\u2588\n\u2588', style: style);
    tp.layout();
    renderedGlyphHeight = tp.height / 2;
  }

  Future<bool> openFile(String path) async {
    treeSitter.setLanguage(TreeSitterLanguage.c);
    this.path = path;
    lines = await File(this.path).readAsLines();
    widths = List.filled(lines.length, 0, growable: true);
    for (var i = 0; i < lines.length; i++) {
      tp.text = TextSpan(text: lines[i], style: style);
      tp.layout();
      widths[i] = tp.width;
    }
    treeSitter.parseString(lines.join('\n'));
    return true;
  }

  RenderTextResult getText(int startLine, int lineCount, TextStyle style) {
    List<List<InlineSpan>> ls = [];
    // We should only have one widget, for the ime buffer
    List<PlaceholderDimensions> widgetWidths = [];

    var startLineByteOffset = _getLineByteOffset(startLine);
    var endLineByteOffset = _getLineByteOffset(startLine + lineCount);

    // To ensure that line heights appear consistent, we stuff each line
    // with a dummy char, before the newline. We don't want to render this
    // char, but it should still affect layout, so we make it transparent!
    var invisbleStyle = style.copyWith(color: Colors.transparent);

    var hasSel = hasSelection();
    var selStart = getSelectionStart();
    var selEnd = getSelectionEnd();

    var hlInfo = treeSitter.getHighlights(startLineByteOffset, endLineByteOffset - startLineByteOffset);
    var relByteOffset = 0;
    var hlIdx = 0;

    for (var i = 0; i < lineCount && (i + startLine) < lines.length; i++) {
      var relByteOffsetLoopStart = relByteOffset;
      List<InlineSpan> newlist = [];
      ls.add([]);
      var lineIdx = startLine + i;
      var line = lines[lineIdx].characters;
      if (cursor.line == startLine + i && imeBufferWidth > 0) {
        // Line contains IME buffer
        var firstTxt = line.take(cursor.column).toString();
        var secondText = line.skip(cursor.column).take(line.length - cursor.column).toString();
        (relByteOffset, hlIdx) =
            _splitStringByHighlightsAndAddToList(firstTxt, newlist, relByteOffset, hlInfo, hlIdx, style, false);
        // newlist.add(TextSpan(text: firstTxt, style: style));
        // Adds placeholder for IME editor buffer, sizing is set via widgetWidths list
        newlist.add(WidgetSpan(child: const SizedBox(width: 0, height: 0), style: style));
        widgetWidths.add(PlaceholderDimensions(size: Size(imeBufferWidth, 1), alignment: PlaceholderAlignment.middle));
        (relByteOffset, hlIdx) =
            _splitStringByHighlightsAndAddToList(secondText, newlist, relByteOffset, hlInfo, hlIdx, style, false);
      } else if (hasSel && selStart.line <= lineIdx && lineIdx <= selEnd.line) {
        // Line is part of selection
        var lineSelStart = lineIdx == selStart.line ? selStart.column : 0;
        var lineSelEnd = lineIdx == selEnd.line ? selEnd.column : line.length;
        assert(lineSelStart <= lineSelEnd);
        var (prefixNotSelectedSegment, selectedSegment, suffixNotSelectedSegment) =
            _splitLineInto(line, lineSelStart, lineSelEnd);
        // If the cursor is before the first char on a given line, only suffix will be non-empty
        (relByteOffset, hlIdx) = _splitStringByHighlightsAndAddToList(
            prefixNotSelectedSegment, newlist, relByteOffset, hlInfo, hlIdx, style, false);
        (relByteOffset, hlIdx) =
            _splitStringByHighlightsAndAddToList(selectedSegment, newlist, relByteOffset, hlInfo, hlIdx, style, true);
        (relByteOffset, hlIdx) = _splitStringByHighlightsAndAddToList(
            suffixNotSelectedSegment, newlist, relByteOffset, hlInfo, hlIdx, style, false);
      } else {
        (relByteOffset, hlIdx) =
            _splitStringByHighlightsAndAddToList(line.toString(), newlist, relByteOffset, hlInfo, hlIdx, style, false);
      }
      newlist.add(TextSpanEx("\u2588", invisbleStyle, false, true, false));
      newlist.add(TextSpanEx("\n", invisbleStyle, true, false, false));
      ls[i] = newlist;
      assert(relByteOffsetLoopStart + line.length == relByteOffset);
    }

    return RenderTextResult(ls, widgetWidths, hasSel, selStart, selEnd);
  }

  void deleteText({required bool backspace, required bool delete}) {
    // This works be selecting the text we want to delete first, if we don't already have a selection
    if (!hasSelection()) {
      var oldCursor = DocumentLocation(cursor.line, cursor.column);
      if (backspace) {
        if (cursor.column > 0) {
          anchor = oldCursor;
          cursor.column--;
        } else if (cursor.column == 0 && cursor.line > 0) {
          anchor = oldCursor;
          var prevLineLength = lines[cursor.line - 1].characters.length;
          var newCursor = DocumentLocation(cursor.line - 1, prevLineLength);
          cursor = newCursor;
        }
      } else if (delete) {
        var currentLength = lines[cursor.line].characters.length;
        if (cursor.column < currentLength) {
          anchor = oldCursor;
          cursor.column++;
        } else if (cursor.line < lines.length) {
          anchor = oldCursor;
          cursor.column = 0;
          cursor.line++;
        }
      }
    }
    _deleteSelection();
  }

  // Inserts the text at the cursor position
  void insertText(String text) {
    if (hasSelection()) {
      _deleteSelection();
    }
    // TODO: Need to handle \r\n newlines as well
    // Splitting the string '\n' by '\n' yields two empty strings.
    if (text.contains('\n')) {
      // Save contents after the cursor to EOL
      var afterCursorOnFirstLine = lines[cursor.line].characters.skip(cursor.column).toString();
      // Sets the current line to be without the just saved contents
      lines[cursor.line] = lines[cursor.line].characters.take(cursor.column).toString();
      // Splitting '\n' yields two empty strings (the empty string before and after the '\n')
      var newlines = text.split('\n');
      _insertText(newlines[0]); // insert whatever is before the first newline

      for (var i = 1; i < newlines.length - 1; i++) {
        cursor.line++; // move the cursor down
        lines.insert(cursor.line, newlines[i]);
        tp.text = TextSpan(text: newlines[i], style: style);
        tp.layout();
        widths.insert(cursor.line, tp.width);
      }
      cursor.line++;
      cursor.column = 0;
      lines.insert(cursor.line, afterCursorOnFirstLine);
      widths.insert(cursor.line, 0);
      _insertText(newlines.last);
    } else {
      _insertText(text);
    }
  }

  void _insertText(String text) {
    var l = lines[cursor.line];
    var l1st = l.characters.take(cursor.column);
    var l2nd = l.characters.skip(cursor.column).take(l.characters.length - cursor.column);
    lines[cursor.line] = "$l1st$text$l2nd";
    tp.text = TextSpan(text: lines[cursor.line], style: style);
    tp.layout();
    widths[cursor.line] = tp.width;
    cursor.column += text.characters.length;
    assert(lines.length == widths.length);
  }

  Size getSize() {
    var h = lines.length * renderedGlyphHeight;
    var w = widths.fold(0.0, (max, val) => val > max ? val : max);
    return Size(w, h);
  }

  Offset getCursorOffset() {
    assert(cursor.line >= 0);
    assert(cursor.column >= 0);
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

  void _deleteSelection() {
    if (hasSelection()) {
      var selStart = getSelectionStart();
      var selEnd = getSelectionEnd();
      var startLine = lines[selStart.line];
      var endLine = lines[selEnd.line];
      var startLineRest = startLine.characters.take(selStart.column).toString();
      var endLineRest = endLine.characters.skip(selEnd.column).toString();
      // The first part of the line where the selection starts (earliest in the document),
      // and the last part of the line where the selection ends (later in the document)
      var newLine = "$startLineRest$endLineRest";
      tp.text = TextSpan(text: newLine, style: style);
      tp.layout();
      lines[selStart.line] = newLine;
      widths[selStart.line] = tp.width;
      if (selStart.line < selEnd.line) {
        lines.removeRange(selStart.line + 1, selEnd.line + 1);
        widths.removeRange(selStart.line + 1, selEnd.line + 1);
      }
      anchor = null;
      cursor = selStart;
    }
  }

  DocumentLocation _getSelectionStartOrEnd(bool start) {
    // TODO: either make it more explicit that an instance is read-only (using final?),
    // with private methods, or always make a copy when returing the information outside.
    var cursor2 = DocumentLocation(cursor.line, cursor.column);
    if (anchor != null) {
      // Should never be -1, but dart does not seem clever enough here?
      var aLine = anchor?.line ?? -1;
      var aCol = anchor?.column ?? -1;
      var anchor2 = DocumentLocation(aLine, aCol);
      if (anchor2.line < cursor.line || anchor2.line == cursor.line && anchor2.column < cursor.column) {
        // anchor is before cursor:
        return start ? anchor2 : cursor2;
      } else {
        return start ? cursor2 : anchor2;
      }
    } else {
      return cursor2;
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

  (String, String, String) _splitLineInto(Characters line, int startIndex, int endIndex) {
    return (
      line.take(startIndex).toString(),
      line.skip(startIndex).take(endIndex - startIndex).toString(),
      line.skip(endIndex).take(line.length - endIndex).toString()
    );
  }

  int _getLineByteOffset(int line) {
    var offset = 0;
    for (var i = 0; i < line && i < lines.length; i++) {
      offset += lines[i].length;
    }
    return offset;
  }

  (int, int) _splitStringByHighlightsAndAddToList(String string, List<InlineSpan> spans, int lineByteOffset,
      List<HighlightInfo> hlInfo, int hlIdx, TextStyle defaultText, bool isSelected) {
    // var remaining = string;
    // var offset = lineByteOffset;
    // while (remaining.isNotEmpty && hlInfo.isNotEmpty) {
    //   // While we have more string to match against, and we still have HL info items
    //   var hl = hlInfo.first;
    //   if (hl.start > offset) {
    //     var snip = remaining.substring(0, hl.start - offset);
    //     remaining = remaining.substring(snip.length);
    //     spans.add(TextSpanEx(snip, style, false, false, isSelected));
    //   }
    //   var snip = remaining.substring(0, hl.length);
    //   spans.add(TextSpanEx(snip, style, false, false, isSelected));
    //   remaining = remaining.substring(snip.length);
    // }
    // // split text using info in hlInfo
    spans.add(TextSpanEx(string, style, false, false, isSelected));
    // Returns the new byte offset after processing the segment, and as also return the index from
    // which we can begin in hlInfo, next time, skipping previously used entries.

    return (lineByteOffset + string.length, hlIdx);
  }
}
