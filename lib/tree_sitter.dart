import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'dart:io' show Directory, File;
import 'package:path/path.dart' as path;
import 'package:ffi/ffi.dart';

class HighlightInfo {
  final int start;
  final int length;
  late String name;
  HighlightInfo(this.start, this.length, this.name);
}

enum TreeSitterLanguage {
  none(0),
  javascript(1),
  c(2);

  const TreeSitterLanguage(this.value);
  final int value;
}

// For now, we only support UTF8, since it seems that darts usage of code units
// is the same meaning as bytes, and this eases lots of interopt with tree-sitter.
// See https://api.dart.dev/stable/3.3.4/dart-convert/Utf8Codec-class.html for support
enum TreeSitterEncoding {
  Utf8(0);

  const TreeSitterEncoding(this.value);
  final int value;
}

// From tree-sitter
final class TSPoint extends ffi.Struct {
  @ffi.Uint32()
  external final int row;
  @ffi.Uint32()
  external final int column;
}

// 'initialize'
typedef InitializeLib = ffi.Pointer Function(ffi.Bool);
typedef InitializeDart = ffi.Pointer Function(bool);
// 'set_language'
typedef SetLanguageLib = ffi.Bool Function(ffi.Pointer, ffi.Uint32, ffi.Pointer<Utf8>, ffi.Uint32);
typedef SetLanguageDart = bool Function(ffi.Pointer, int, ffi.Pointer<Utf8>, int);
// 'parse_string'
typedef ParseStringUtf8Lib = ffi.Bool Function(ffi.Pointer, ffi.Pointer<Utf8>, ffi.Uint32, ffi.Uint8);
typedef ParseStringUtf8Dart = bool Function(ffi.Pointer, ffi.Pointer<Utf8>, int, int);
// 'edit_string'
typedef EditStringUtf8Callback = ffi.Pointer<Utf8> Function(
    ffi.Pointer<ffi.Void>, ffi.Uint32, TSPoint, ffi.Pointer<ffi.Uint32>);
typedef EditStringPayloadCallback = ffi.Void Function();
typedef EditStringUtf8Lib = ffi.Bool Function(
    ffi.Pointer,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Pointer<ffi.NativeFunction<EditStringUtf8Callback>>,
    ffi.Uint32);
typedef EditStringUtf8Dart = bool Function(ffi.Pointer, int, int, int, int, int, int, int, int, int,
    ffi.Pointer<ffi.NativeFunction<EditStringUtf8Callback>>, int);
typedef GetHighlightsCallback = ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Uint32, ffi.Pointer<Utf8>);
typedef GetHighlightsLib = ffi.Bool Function(
    ffi.Pointer, ffi.Uint32, ffi.Uint32, ffi.Pointer<ffi.NativeFunction<GetHighlightsCallback>>);
typedef GetHighlightsDart = bool Function(
    ffi.Pointer, int, int, ffi.Pointer<ffi.NativeFunction<GetHighlightsCallback>>);

bool loadedLibrary = false;

class TreeSitter {
  static late ffi.DynamicLibrary library;

  final Map<TreeSitterLanguage, String> scmPaths;
  final TreeSitterEncoding encoding;
  late InitializeDart _initialize;
  late SetLanguageDart _setLanguage;
  late ParseStringUtf8Dart _parseStringUtf8;
  late EditStringUtf8Dart _editStringUtf8;
  late GetHighlightsDart _getHighlights;
  late NativeCallable<GetHighlightsCallback> _hlcallback;

  List<HighlightInfo> _capturedHighlight = [];
  int _highlightStartByte = 0;

  ffi.Pointer ctx = ffi.nullptr;

  TreeSitter(String tslibPath, this.encoding, this.scmPaths) {
    if (!loadedLibrary) {
      var libraryPath = path.join(Directory.current.path, tslibPath);
      library = ffi.DynamicLibrary.open(libraryPath);
      loadedLibrary = true;
    }
    _initialize = library.lookupFunction<InitializeLib, InitializeDart>('initialize');
    _setLanguage = library.lookupFunction<SetLanguageLib, SetLanguageDart>('set_language');
    _parseStringUtf8 = library.lookupFunction<ParseStringUtf8Lib, ParseStringUtf8Dart>('parse_string');
    _editStringUtf8 = library.lookupFunction<EditStringUtf8Lib, EditStringUtf8Dart>('edit_string');
    _getHighlights = library.lookupFunction<GetHighlightsLib, GetHighlightsDart>('get_highlights');
    _hlcallback = NativeCallable<GetHighlightsCallback>.isolateLocal(_highlightsCallback);
  }

  void initialize(bool logToStdout) {
    ctx = _initialize(logToStdout);
    if (ctx == ffi.nullptr) {
      throw Exception('Failed to initialize tree-sitter');
    }
  }

  void setLanguage(TreeSitterLanguage language) async {
    var scmPath = scmPaths[language];
    if (scmPath == null) {
      throw Exception('Failed to load scm path');
    }
    var scm = await File(scmPath).readAsString();
    if (!_setLanguage(ctx, language.value, scm.toNativeUtf8(), scm.length)) {
      throw Exception('Failed to set tree-sitter parser languager: $language');
    }
  }

  bool parseString(String source) {
    var sourceCodePointer = source.toNativeUtf8();
    return _parseStringUtf8(ctx, sourceCodePointer, sourceCodePointer.length, encoding.value);
  }

  bool editString(
      int startByte,
      int oldEndByte,
      int newEndByte,
      int startPointRow,
      int startPointColumn,
      int oldEndPointRow,
      int oldEndPointColumn,
      int newEndPointRow,
      int newEndPointColumn,
      ffi.Pointer<ffi.NativeFunction<EditStringUtf8Callback>> bufferCallback) {
    return _editStringUtf8(ctx, startByte, oldEndByte, newEndByte, startPointRow, startPointColumn, oldEndPointRow,
        oldEndPointColumn, newEndPointRow, newEndPointColumn, bufferCallback, encoding.value);
  }

  void _highlightsCallback(int start, int length, int captureId, Pointer<Utf8> captureName) {
    var replacedOld = false;
    assert(_highlightStartByte <= start);
    start -= _highlightStartByte;
    for (var i = 0; i < _capturedHighlight.length; i++) {
      if (start == _capturedHighlight[i].start) {
        assert(length == _capturedHighlight[i].length); // Assumption
        _capturedHighlight[i].name = captureName.toDartString();
        replacedOld = true;
      }
    }
    if (!replacedOld) {
      // Also assume we should be beyond the previous one
      if (_capturedHighlight.isNotEmpty) {
        var prev = _capturedHighlight.last;
        assert(prev.start + prev.length <= start);
      }
      _capturedHighlight.add(HighlightInfo(start, length, captureName.toDartString()));
    }
  }

  List<HighlightInfo> getHighlights(int startByte, int byteLength) {
    // start by resetting the internal list of captures
    _capturedHighlight = [];
    _highlightStartByte = startByte;
    _getHighlights(ctx, startByte, byteLength, _hlcallback.nativeFunction);
    return _capturedHighlight;
  }
}
