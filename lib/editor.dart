import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_1kloc_editor/document_provider.dart';
import 'package:flutter_1kloc_editor/editor_config.dart';
import 'package:flutter_1kloc_editor/editor_notifier.dart';
import 'package:flutter_1kloc_editor/editor_painter.dart';
import 'package:flutter_1kloc_editor/editor_scrollbar.dart';

class Editor extends StatefulWidget {
  final String path;

  const Editor({super.key, required this.path});

  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  final stopwatch = Stopwatch();

  final ScrollController vScroll = ScrollController();
  final ScrollController hScroll = ScrollController();
  final TextEditingController textController = TextEditingController();
  late DocumentProvider doc;
  late EditorNotifier notifier;
  late EditorConfig config;
  late EditorScrollbarEvent vScrollbarNotifier;
  late EditorScrollbarEvent hScrollbarNotifier;
  final FocusNode imeFocusNode = FocusNode();
  final FocusNode keyboardFocus = FocusNode();
  final OutlinedBorder scrollThumbShape = const RoundedRectangleBorder(
    side: BorderSide(
      color: Colors.grey,
    ),
  );

  TextPainter imePainter = TextPainter(textDirection: TextDirection.ltr);
  double imeWidth = 10;
  bool isScrollbarHovered = false;
  bool isMouseDown = false;

  @override
  void initState() {
    super.initState();
    stopwatch.start();
    var textStyle = const TextStyle(
      color: Colors.black,
      fontFamily: "Consolas",
      fontSize: 15,
    );
    config = EditorConfig(textStyle, 5.0);
    doc = DocumentProvider(config.textStyle);
    notifier = EditorNotifier(doc, vScroll, hScroll);
    vScrollbarNotifier = EditorScrollbarEvent("vert");
    hScrollbarNotifier = EditorScrollbarEvent("horz");

    // setState triggers new build call when eg size of document changes
    doc.addListener(() => setState(() {}));
    doc.openFile(widget.path);
    vScrollbarNotifier.addListener(scrollListener);
    hScrollbarNotifier.addListener(scrollListener);
    textController.addListener(() {
      var newText = textController.text;
      var newImeWidth = 10.0;
      if (!textController.value.isComposingRangeValid && newText.isNotEmpty) {
        textController.text = "";
        doc.doc.insertText(newText);
        doc.doc.cursorImeWidth = 0;
      } else {
        imePainter.text = TextSpan(text: newText, style: config.textStyle);
        imePainter.layout();
        doc.doc.cursorImeWidth = imePainter.width;
        newImeWidth = imePainter.width + 10; // TODO: Fudged cursor width?
      }
      setState(() => imeWidth = newImeWidth);
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
    if (doc.doc.setCursorFromOffset(offset)) {
      doc.touch();
    }
    isMouseDown = true;
  }

  void onPointerMove(PointerMoveEvent event) {
    if (isMouseDown) {
      var offset = mapFromPointer(event.localPosition);
      if (doc.doc.setCursorFromOffset(offset)) {
        doc.touch();
      }
    }
  }

  void onPointerUp(PointerUpEvent event) {
    isMouseDown = false;
  }

  @override
  Widget build(BuildContext context) {
    stopwatch.reset();

    // TODO: Fix this to be less hacky.
    // Only true after initial build?
    if (imeFocusNode.hasListeners) {
      imeFocusNode.requestFocus();
    }

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
      onKeyEvent: (event) {
        if (event.runtimeType == KeyDownEvent || event.runtimeType == KeyRepeatEvent) {
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
          }
          if (movedCursor) {
            setState(() {});
          }
        }
      },
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
                painter: EditorPainter(config, notifier),
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
                color: Color(0x66FFFF00),
                child: EditableText(
                  enableIMEPersonalizedLearning: false,
                  enableInteractiveSelection: false,
                  controller: textController,
                  focusNode: imeFocusNode,
                  autofocus: true,
                  autocorrect: false,
                  style: config.textStyle,
                  scribbleEnabled: false,
                  cursorColor: Colors.blue,
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
