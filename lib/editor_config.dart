import 'package:flutter/material.dart';

class EditorConfig {
  // Style for text
  TextStyle textStyle;
  Paint selectionPaint;
  // Margins around the canvas, before anything is rendered
  double canvasMargin;

  EditorConfig(this.textStyle, this.selectionPaint, this.canvasMargin);
}
