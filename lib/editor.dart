import 'package:flutter/material.dart';
import 'package:flutter_1kloc_editor/document_provider.dart';
import 'package:flutter_1kloc_editor/editor_config.dart';
import 'package:flutter_1kloc_editor/editor_notifier.dart';
import 'package:flutter_1kloc_editor/editor_painter.dart';

class Editor extends StatefulWidget {
  final String path;

  Editor({super.key, required this.path});

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
  final FocusNode imeFocusNode = FocusNode();
  bool isMouseDown = false;

  TextPainter imePainter = TextPainter(textDirection: TextDirection.ltr);
  double imeWidth = 10;

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
    // Triggers new build call when eg size of document changes
    doc.addListener(() => setState(() {}));
    doc.openFile(widget.path);
    textController.addListener(() {
      var newText = textController.text;
      if (!textController.value.isComposingRangeValid && newText.isNotEmpty) {
        textController.text = "";
        doc.doc.insertText(newText);
        setState(() {
          imeWidth = 10;
        });
      } else {
        imePainter.text = TextSpan(text: newText, style: config.textStyle);
        imePainter.layout();
        setState(() {
          imeWidth = imePainter.width + 10; // TODO: Fudged cursor width?
        });
      }
    });
  }

  void onPointerDown(PointerDownEvent event) {
    var p = event.localPosition;
    var offset = Offset(p.dx - config.canvasMargin, p.dy - config.canvasMargin);
    if (doc.doc.setCursorFromOffset(offset, vScroll.offset, hScroll.offset)) {
      doc.touch();
    }
    isMouseDown = true;
  }

  void onPointerMove(PointerMoveEvent event) {
    if (isMouseDown) {
      var p = event.localPosition;
      var offset = Offset(p.dx - config.canvasMargin, p.dy - config.canvasMargin);
      if (doc.doc.setCursorFromOffset(offset, vScroll.offset, hScroll.offset)) {
        doc.touch();
      }
    }
  }

  void onPointerUp(PointerUpEvent event) {
    var p = event.localPosition;
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
    var cursorOffset = doc.doc.getCursorOffset();
    var codeSize = doc.doc.getSize();
    codeSize = Size(codeSize.width + (config.canvasMargin * 2), codeSize.height + (config.canvasMargin * 2));
    var ui = Listener(
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
          SizedBox(
            height: winSize.height,
            width: winSize.width,
            child: Scrollbar(
              controller: vScroll,
              child: Scrollbar(
                controller: hScroll,
                notificationPredicate: (notif) => notif.depth == 1,
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
          Positioned(
            left: config.canvasMargin + cursorOffset.dx,
            // TODO: 2 Is the diff between regular ascii lines and max height lines, but why?!
            top: config.canvasMargin + cursorOffset.dy + 2,
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
        ],
      ),
    );
    print("build: ${stopwatch.elapsedMicroseconds} us");
    return ui;
  }
}
