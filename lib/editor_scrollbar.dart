import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class EditorScrollbar extends RawScrollbar {
  final EditorScrollbarEvent notifier;

  const EditorScrollbar({
    required this.notifier,
    required super.controller,
    required super.child,
    super.notificationPredicate,
    super.shape,
    super.thickness,
    super.crossAxisMargin,
    super.minThumbLength,
    super.trackVisibility,
    super.trackBorderColor,
    super.trackColor,
    super.thumbVisibility,
    super.thumbColor,
    super.key,
  });

  @override
  EditorScrollbarState createState() => EditorScrollbarState(notifier);
}

class EditorScrollbarState extends RawScrollbarState {
  final EditorScrollbarEvent notifier;
  int count = 0;

  EditorScrollbarState(this.notifier);

  @override
  bool isPointerOverScrollbar(Offset position, PointerDeviceKind kind, {bool forHover = false}) {
    var res = super.isPointerOverScrollbar(position, kind, forHover: forHover);
    notifier.touch(res);
    return res;
  }
}

class EditorScrollbarEvent extends ChangeNotifier {
  String name;
  EditorScrollbarEvent(this.name);
  bool hovered = false;
  void touch(bool isHovered) {
    if (isHovered != hovered) {
      hovered = isHovered;
      notifyListeners();
    }
  }
}
