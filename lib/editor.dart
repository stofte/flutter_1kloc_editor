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
  late DocumentProvider doc;
  late EditorNotifier notifier;
  late EditorConfig config;

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
  }

  @override
  Widget build(BuildContext context) {
    stopwatch.reset();
    var winSize = MediaQuery.of(context).size;
    var codeSize = doc.doc.getSize();
    codeSize = Size(codeSize.width + (config.canvasMargin * 2), codeSize.height + (config.canvasMargin * 2));
    var ui = Stack(
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
      ],
    );
    print("build: ${stopwatch.elapsedMicroseconds} us");
    return ui;
  }
}
