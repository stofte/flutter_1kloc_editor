import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_1kloc_editor/cursor_painter.dart';
import 'package:flutter_1kloc_editor/document_provider.dart';
import 'package:flutter_1kloc_editor/editor_config.dart';
import 'package:flutter_1kloc_editor/editor_notifier.dart';
import 'package:flutter_1kloc_editor/editor_painter.dart';
import 'package:flutter_1kloc_editor/editor_scrollbar.dart';
import 'package:flutter_1kloc_editor/tree_sitter.dart';

class Editor extends StatefulWidget {
  final String path;
  final TreeSitter treeSitter = TreeSitter('tslib.dll', TreeSitterEncoding.Utf8,
      {TreeSitterLanguage.c: "scm\\c.scm", TreeSitterLanguage.javascript: "scm\\javascript.scm"});
  final Map<String, Color> syntaxConfig = {
    "comment": Colors.grey,
    "constant": Color(0xFFB98853),
    "delimiter": Colors.yellow,
    "function": Colors.red,
    "keyword": Color(0xFF118EE8),
    "number": Colors.black,
    "operator": Color(0xFF9A28D1),
    "property": Color(0xFF1974DD),
    "string": Color(0xFF67D827),
    "type": Colors.orange,
    "variable": Color(0xFF378B8A),
  };

  Editor({super.key, required this.path}) {
    treeSitter.initialize(false, false);
  }

  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  final stopwatch = Stopwatch();
  final textStopwatch = Stopwatch();

  final ScrollController vScroll = ScrollController();
  final ScrollController hScroll = ScrollController();
  final TextEditingController textController = TextEditingController();
  final GlobalKey editorViewBox = GlobalKey(debugLabel: "scrollview");
  final FocusNode imeFocusNode = FocusNode();
  final FocusNode keyboardFocus = FocusNode();
  final CursorBlinkTimer cursorBlinkTimer = CursorBlinkTimer();
  final OutlinedBorder scrollThumbShape = const RoundedRectangleBorder(
    side: BorderSide(
      color: Colors.grey,
    ),
  );

  late DocumentProvider doc;
  late EditorNotifier notifier;
  late EditorConfig config;
  late EditorScrollbarEvent vScrollbarNotifier = EditorScrollbarEvent("vert");
  late EditorScrollbarEvent hScrollbarNotifier = EditorScrollbarEvent("horz");

  TextPainter imePainter = TextPainter(textDirection: TextDirection.ltr);
  double imeWidth = 10;
  bool isScrollbarHovered = false;
  bool isMouseDown = false;

  @override
  void initState() {
    super.initState();
    stopwatch.start();
    textStopwatch.start();
    var textStyle = const TextStyle(
      height: 1.3,
      color: Colors.black,
      fontFamily: "Consolas",
      fontSize: 15,
    );
    var selectionPaint = Paint();
    selectionPaint.color = Colors.lightBlue.shade200;
    selectionPaint.style = PaintingStyle.fill;
    selectionPaint.isAntiAlias = false;
    config = EditorConfig(textStyle, selectionPaint, 5.0, widget.syntaxConfig);
    doc = DocumentProvider(config.textStyle, this.widget.treeSitter, config.syntaxColoring);
    notifier = EditorNotifier(doc, vScroll, hScroll);
    FocusManager.instance.addListener(() {
      // TODO: This will likely have to change, if the editor widget is embedded in a full app
      var fn = FocusManager.instance.primaryFocus;
      if (fn != imeFocusNode && buildCalled > 1) {
        imeFocusNode.requestFocus();
      }
    });

    // setState triggers new build call when eg size of document changes
    doc.addListener(() => setState(() {}));
    doc.openFile(widget.path);
    vScrollbarNotifier.addListener(scrollListener);
    hScrollbarNotifier.addListener(scrollListener);
    textController.addListener(() {
      textStopwatch.reset();
      var newText = textController.text;
      var newImeWidth = 10.0;
      doc.doc.imeBufferWidth = 0;
      doc.doc.imeCursorOffset = 0;
      if (!textController.value.isComposingRangeValid && newText.isNotEmpty) {
        // User is not composing and we have some text. Grab it and insert into the document
        textController.text = "";
        doc.doc.insertText(newText);
      } else {
        // Determine the width of the full input field
        imePainter.text = TextSpan(text: newText, style: config.textStyle);
        imePainter.layout();
        doc.doc.imeBufferWidth = imePainter.width;
        newImeWidth = imePainter.width + 10; // TODO: Fudged cursor width?
        if (newText.isNotEmpty) {
          // If we come here, it must be because we are composing,
          // so we should be delete the current selection (if any)
          assert(textController.value.isComposingRangeValid);
          if (doc.doc.hasSelection()) {
            doc.doc.insertText("");
          }
          // Determine the offset the cursor is at, only if we have something.
          var textBeforeCursor = newText.characters.take(textController.selection.baseOffset).toString();
          imePainter.text = TextSpan(text: textBeforeCursor, style: config.textStyle);
          imePainter.layout();
          doc.doc.imeCursorOffset = imePainter.width;
        }
      }
      setState(() => imeWidth = newImeWidth);
      print("input: ${textStopwatch.elapsedMicroseconds} us");
    });
  }

  void scrollListener() => isScrollbarHovered = vScrollbarNotifier.hovered || hScrollbarNotifier.hovered;
  Offset mapFromPointer(Offset p) =>
      Offset(p.dx - config.canvasMargin + hScroll.offset, p.dy - config.canvasMargin + vScroll.offset);

  void onPointerDown(PointerDownEvent event) {
    if (isScrollbarHovered) {
      return;
    }
    var offset = mapFromPointer(event.localPosition);
    if (doc.doc.setCursorFromOffset(offset, true)) {
      cursorBlinkTimer.showNow();
      doc.touch();
    }
    isMouseDown = true;
  }

  void onPointerMove(PointerMoveEvent event) {
    if (isMouseDown) {
      var offset = mapFromPointer(event.localPosition);
      if (doc.doc.setCursorFromOffset(offset, false)) {
        cursorBlinkTimer.showNow();
        doc.touch();
      }
    }
  }

  void onPointerUp(PointerUpEvent event) {
    isMouseDown = false;
  }

  void onKeyEvent(KeyEvent event) {
    if (event.runtimeType == KeyDownEvent || event.runtimeType == KeyRepeatEvent) {
      if (event.runtimeType == KeyDownEvent) {
        imeFocusNode.requestFocus();
      }
      var movedCursor = false;
      switch (event.logicalKey.keyLabel) {
        case 'Arrow Left':
          movedCursor = doc.doc.moveCursorLeft();
          break;
        case 'Arrow Right':
          movedCursor = doc.doc.moveCursorRight();
          break;
        case 'Arrow Up':
          movedCursor = doc.doc.moveCursorUp();
          break;
        case 'Arrow Down':
          movedCursor = doc.doc.moveCursorDown();
          break;
        case 'Enter':
          movedCursor = true;
          doc.doc.insertText('\n');
          break;
        case 'Backspace':
          movedCursor = true;
          doc.doc.deleteText(backspace: true, delete: false);
          break;
        case 'Delete':
          movedCursor = true;
          doc.doc.deleteText(backspace: false, delete: true);
          break;
      }
      if (movedCursor) {
        adjustScrollbarsAfterCursorMovement();
        setState(() {
          cursorBlinkTimer.showNow();
        });
      }
    }
  }

  void adjustScrollbarsAfterCursorMovement() {
    var scrollViewBox = editorViewBox.currentContext!.findRenderObject() as RenderBox;
    var svHeight = scrollViewBox.size.height;
    var svWidth = scrollViewBox.size.width;
    var cursorOffset = doc.doc.getCursorOffset();
    var offset = Offset(cursorOffset.dx - hScroll.offset, cursorOffset.dy - vScroll.offset) +
        Offset(config.canvasMargin, config.canvasMargin);

    if (offset.dx < 0) {
      hScroll.jumpTo(hScroll.offset + offset.dx);
    } else if (offset.dx > svWidth) {
      hScroll.jumpTo(hScroll.offset + (offset.dx - svWidth));
    }

    if (offset.dy < 0) {
      vScroll.jumpTo(vScroll.offset + offset.dy);
    } else if (offset.dy > svHeight - doc.doc.renderedGlyphHeight) {
      vScroll.jumpTo(vScroll.offset + (offset.dy - (svHeight - doc.doc.renderedGlyphHeight)));
    }
  }

  int buildCalled = 0;

  @override
  Widget build(BuildContext context) {
    stopwatch.reset();

    buildCalled++;

    var winSize = MediaQuery.of(context).size;
    var cursorOffsetAbs = doc.doc.getCursorOffset();
    var vScrollOffset = vScroll.hasClients ? vScroll.offset : 0;
    var hScrollOffset = hScroll.hasClients ? hScroll.offset : 0;
    // We map from the document's "absolute" coordinates and adjust for the scrollbar offsets.
    // TODO: 2 Is the diff between regular ascii lines and max height lines, but why?!
    var cursorOffset = Offset(cursorOffsetAbs.dx + config.canvasMargin - hScrollOffset,
        cursorOffsetAbs.dy + config.canvasMargin + 2 - vScrollOffset);

    var codeSize = doc.doc.getSize();
    codeSize = Size(codeSize.width + (config.canvasMargin * 2), codeSize.height + (config.canvasMargin * 2));
    var ui = KeyboardListener(
      focusNode: keyboardFocus,
      onKeyEvent: onKeyEvent,
      child: Listener(
        onPointerDown: onPointerDown,
        onPointerMove: onPointerMove,
        onPointerUp: onPointerUp,
        child: Stack(
          children: [
            Container(
              color: Colors.white,
              constraints: BoxConstraints(
                maxHeight: winSize.height,
                maxWidth: winSize.width,
              ),
              child: CustomPaint(
                key: editorViewBox,
                painter: EditorPainter(config, notifier),
                foregroundPainter: CursorPainter(
                  config: config,
                  doc: doc,
                  timer: cursorBlinkTimer,
                  hScroll: hScroll,
                  vScroll: vScroll,
                ),
                child: Container(),
              ),
            ),
            Positioned(
              left: cursorOffset.dx,
              top: cursorOffset.dy,
              // TODO: Width needs to be computed from the contents of the field ...
              width: 100,
              height: doc.doc.renderedGlyphHeight,
              child: Container(
                color: Colors.transparent, // Color(0x66FFFF00),
                child: EditableText(
                  enableIMEPersonalizedLearning: false,
                  enableInteractiveSelection: false,
                  controller: textController,
                  focusNode: imeFocusNode,
                  autofocus: true,
                  autocorrect: false,
                  style: config.textStyle,
                  scribbleEnabled: false,
                  cursorColor: Colors.transparent, // Colors.blue,
                  backgroundCursorColor: Colors.transparent,
                  maxLines: 1,
                ),
              ),
            ),
            SizedBox(
              height: winSize.height,
              width: winSize.width,
              child: EditorScrollbar(
                thickness: 15,
                minThumbLength: 30,
                trackBorderColor: Colors.transparent,
                thumbVisibility: false,
                trackVisibility: false,
                shape: scrollThumbShape,
                notifier: vScrollbarNotifier,
                controller: vScroll,
                child: EditorScrollbar(
                  thickness: 15,
                  minThumbLength: 30,
                  trackBorderColor: Colors.transparent,
                  thumbVisibility: false,
                  trackVisibility: false,
                  shape: scrollThumbShape,
                  notifier: hScrollbarNotifier,
                  controller: hScroll,
                  notificationPredicate: (notif) => notif.depth == 1,
                  child: ScrollConfiguration(
                    // Seems required if a duplicate scrollbar is not desired?
                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      controller: vScroll,
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: hScroll,
                        child: SizedBox(
                          height: codeSize.height,
                          width: codeSize.width,
                          child: Container(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    print("build: ${stopwatch.elapsedMicroseconds} us");
    return ui;
  }
}
