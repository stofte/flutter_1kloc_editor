import 'dart:ffi' show NativeCallable, Pointer, Void, Uint32, Uint32Pointer, nullptr;
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
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
  // The text to be rendered
  final List<InlineSpan> text;

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
  final stopwatch = Stopwatch();

  List<String> lines = [''];
  List<double> widths = [];

  List<Rect> selectionRects = [];

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

  late NativeCallable<EditStringUtf8Callback> _bufferReaderWrapped;
  final TreeSitter treeSitter;

  Map<String, Color> syntaxColoring;

  Document(this.style, this.treeSitter, this.syntaxColoring) {
    tp = TextPainter(textDirection: textDirection);
    // More flutter snafu, must have at least two lines of text. There is presumably
    // something going on between the lines which is messing with the algorithm.

    tp.text = TextSpan(text: '\u2588\n\u2588', style: style);
    tp.layout();
    renderedGlyphHeight = tp.height / 2;

    _bufferReaderWrapped = NativeCallable<EditStringUtf8Callback>.isolateLocal(_bufferReaderCallback);
  }

  Future<bool> openFile(String path) async {
    treeSitter.setLanguage(TreeSitterLanguage.javascript);
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

  List<Rect> getSelectionRects(int startLine, int lineCount, TextStyle style, Offset offset) {
    List<Rect> rects = [];
    var hasSel = hasSelection();
    var selStart = getSelectionStart();
    var selEnd = getSelectionEnd();
    var offsetY = 0.0;
    for (var i = 0; i < lineCount && (i + startLine) < lines.length; i++) {
      var lineIdx = startLine + i;
      if (hasSel && selStart.line <= lineIdx && lineIdx <= selEnd.line) {
        var line = lines[lineIdx].characters;
        var lineSelStart = lineIdx == selStart.line ? selStart.column : 0;
        var lineSelEnd = lineIdx == selEnd.line ? selEnd.column : line.length;
        assert(lineSelStart <= lineSelEnd);
        var (prefixNotSelectedSegment, selectedSegment, suffixNotSelectedSegment) =
            _splitLineInto(line, lineSelStart, lineSelEnd);
        var prefixW = 0.0;
        var selectedW = 0.0;
        if (prefixNotSelectedSegment.isNotEmpty) {
          tp.text = TextSpan(text: prefixNotSelectedSegment, style: style);
          tp.layout();
          prefixW = tp.width;
        }
        if (selectedSegment.isNotEmpty) {
          tp.text = TextSpan(text: selectedSegment, style: style);
          tp.layout();
          selectedW = tp.width;
        }
        rects.add(Rect.fromLTRB(offset.dx + prefixW, offset.dy + offsetY, offset.dx + prefixW + selectedW,
            offset.dy + offsetY + renderedGlyphHeight));
      }
      offsetY += renderedGlyphHeight;
    }

    return rects;
  }

  RenderTextResult getText(int startLine, int lineCount, TextStyle style) {
    List<InlineSpan> ls = [];
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

    stopwatch.reset();
    stopwatch.start();
    var hlInfo = treeSitter.getHighlights(startLineByteOffset, endLineByteOffset - startLineByteOffset);
    stopwatch.stop();

    var hlIdx = 0;
    var relByteOffset = startLineByteOffset;
    if (hlInfo.isNotEmpty && hlInfo.first.start < startLineByteOffset) {
      for (var i = 0; i < hlInfo.length; i++) {
        var bytesToChomp = startLineByteOffset - hlInfo[i].start;
        if (hlInfo[i].length > bytesToChomp) {
          // This hlinfo should be used for rendering, so we know we can stop now.
          hlInfo[i].length -= bytesToChomp;
          break;
        } else {
          // The current hlinfo is completely ellided, so we increment hlIdx
          hlIdx++;
        }
      }
    }

    for (var i = 0; i < lineCount && (i + startLine) < lines.length; i++) {
      var relByteOffsetLoopStart = relByteOffset;
      var lineIdx = startLine + i;
      var line = lines[lineIdx].characters;

      if (cursor.line == startLine + i && imeBufferWidth > 0) {
        // Line contains IME buffer
        var firstTxt = line.take(cursor.column).toString();
        var secondText = line.skip(cursor.column).take(line.length - cursor.column).toString();
        (relByteOffset, hlIdx) =
            _splitStringByHighlightsAndAddToList(firstTxt, ls, relByteOffset, hlInfo, hlIdx, style, false);
        // newlist.add(TextSpan(text: firstTxt, style: style));
        // Adds placeholder for IME editor buffer, sizing is set via widgetWidths list
        ls.add(WidgetSpan(child: const SizedBox(width: 0, height: 0), style: style));
        widgetWidths.add(PlaceholderDimensions(size: Size(imeBufferWidth, 1), alignment: PlaceholderAlignment.middle));
        (relByteOffset, hlIdx) =
            _splitStringByHighlightsAndAddToList(secondText, ls, relByteOffset, hlInfo, hlIdx, style, true);
      } else {
        (relByteOffset, hlIdx) =
            _splitStringByHighlightsAndAddToList(line.toString(), ls, relByteOffset, hlInfo, hlIdx, style, true);
      }
      ls.add(TextSpanEx("\u2588", invisbleStyle, false, true, false));
      ls.add(TextSpanEx("\n", invisbleStyle, true, false, false));
      assert(relByteOffsetLoopStart + lines[lineIdx].length + 1 == relByteOffset);
      // relByteOffset++; // newline
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

  Pointer<Utf8> _bufferReaderCallback(Pointer<Void> payload, int byteOffset, TSPoint point, Pointer<Uint32> dataRead) {
    var (lineNum, colNum) = _getLineAndColumnFromByteOffset(byteOffset);
    if (lineNum >= lines.length) {
      dataRead.value = 0;
      return nullptr;
    }
    // we want to be sure we don't return a split graphmeme/character
    var line = lines[lineNum];
    var linePartFirst = line.substring(0, colNum);
    var linePartNoNl = line.substring(colNum);
    assert(linePartNoNl.characters.length + linePartFirst.characters.length == line.characters.length);
    var linePart = linePartNoNl + '\n';
    var zz = linePart.toNativeUtf8();
    assert(zz.length == linePart.length);
    dataRead.value = zz.length;
    return zz;
  }

  void _insertText(String text) {
    assert(!text.contains('\n'));
    var l = lines[cursor.line];
    var l1st = l.characters.take(cursor.column);
    var l2nd = l.characters.skip(cursor.column).take(l.characters.length - cursor.column);
    // Careful with multibyte chars. tree-sitter is byte based.
    var textByteOffset = _getLineByteOffset(cursor.line) + l1st.length;
    var textByteLength = text.length;
    var cursorLine = cursor.line;

    lines[cursor.line] = "$l1st$text$l2nd";
    tp.text = TextSpan(text: lines[cursor.line], style: style);
    tp.layout();
    widths[cursor.line] = tp.width;
    cursor.column += text.characters.length;
    assert(lines.length == widths.length);

    // pass the edit to tree-sitter as well
    assert(treeSitter.editString(
        textByteOffset,
        textByteOffset,
        textByteOffset + textByteLength,
        cursorLine,
        l1st.length,
        cursorLine,
        l1st.length,
        cursorLine,
        l1st.length + textByteLength,
        _bufferReaderWrapped.nativeFunction));
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
      var selStartByteOffset = _getByteOffsetFromDocumentLocation(selStart);
      var selEndByteOffset = _getByteOffsetFromDocumentLocation(selEnd);
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
      assert(treeSitter.editString(
          selStartByteOffset,
          selEndByteOffset,
          selStartByteOffset,
          selStart.line,
          selStart.column,
          selEnd.line,
          selEnd.column,
          selStart.line,
          selStart.column,
          _bufferReaderWrapped.nativeFunction));
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
      offset += lines[i].length + 1;
    }
    return offset;
  }

  // The column returned is in bytes, not characters!
  (int, int) _getLineAndColumnFromByteOffset(int byteOffset) {
    var line = 0;
    while (byteOffset > 0) {
      if (byteOffset - (lines[line].length + 1) < 0) {
        break;
      } else {
        byteOffset -= lines[line].length + 1;
        line++;
      }
    }
    return (line, byteOffset);
  }

  int _getByteOffsetFromDocumentLocation(DocumentLocation location) {
    var line = location.line;
    var offset = 0;
    var i = 0;
    for (i = 0; i < line && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    return offset + lines[i].characters.take(location.column).toString().length;
  }

  (int, int) _splitStringByHighlightsAndAddToList(String string, List<InlineSpan> spans, int byteOffset,
      List<HighlightInfo> hlInfo, int hlIdx, TextStyle defaultText, bool newlineFollows) {
    var remaining = string;
    var remainingHlInfo = false;

    while (remaining.isNotEmpty && hlIdx < hlInfo.length) {
      var hl = hlInfo[hlIdx];
      remainingHlInfo = false;
      if (hl.start > byteOffset) {
        // Text before the next hlInfo starts, eg whitespace, etc.
        var maxRemaining = min(hl.start - byteOffset, remaining.length);
        var snip = remaining.substring(0, maxRemaining);
        assert(snip.isNotEmpty);
        // print("HL: $snip (default)");
        spans.add(TextSpanEx(snip, defaultText, false, false, false));
        remaining = remaining.substring(snip.length);
        byteOffset += snip.length;
        continue;
      }

      if (hl.length < 0) {
        print("booboo!");
      }

      var snipLength = hl.length;
      if (hl.length > remaining.length) {
        snipLength = remaining.length;
      }

      var snip = remaining.substring(0, snipLength);
      var s = style.copyWith(color: syntaxColoring[hl.name]);
      spans.add(TextSpanEx(snip, s, false, false, false));
      byteOffset += snip.length;
      hl.length -= snipLength;
      remaining = remaining.substring(snip.length);

      assert(hl.length >= 0);
      if (hl.length <= 0) {
        hlIdx++;
      } else {
        remainingHlInfo = true;
      }
    }

    if (remaining.isNotEmpty) {
      spans.add(TextSpanEx(remaining, defaultText, false, false, false));
      byteOffset += remaining.length;
    }

    // we chop one from the length, due to newlines.
    // this really needs some other fix. the newline
    // can potentially not be part of any hlinfo, so
    // this is somewhat tricky.

    // ideally, we would not have the buffer be line based.
    if (hlIdx < hlInfo.length && hlInfo[hlIdx].length > 0 && newlineFollows && remainingHlInfo) {
      hlInfo[hlIdx].length--;
    }

    // Returns the new byte offset after processing the segment, and as also return the index from
    // which we can begin in hlInfo, next time, skipping previously used entries.
    return (byteOffset + (newlineFollows ? 1 : 0), hlIdx);
  }
}
