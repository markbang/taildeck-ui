import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'term.dart';

const _snapshotCells = 4;
const _metaLen = 16;
const _extraCap = 8192;

typedef _CreateNative = Pointer<Void> Function(
  Int32 cols,
  Int32 rows,
  Int32 scrollback,
  Int32 fg,
  Int32 bg,
  Int32 cursor,
);
typedef _Create = Pointer<Void> Function(
  int cols,
  int rows,
  int scrollback,
  int fg,
  int bg,
  int cursor,
);

typedef _TermNative = Void Function(Pointer<Void>);
typedef _Term = void Function(Pointer<Void>);

typedef _BytesNative = Pointer<Uint8> Function(
  Pointer<Void> term,
  Pointer<Uint8> data,
  IntPtr len,
  Pointer<IntPtr> outLen,
);
typedef _Bytes = Pointer<Uint8> Function(
  Pointer<Void> term,
  Pointer<Uint8> data,
  int len,
  Pointer<IntPtr> outLen,
);

typedef _ReplyNative = Pointer<Uint8> Function(
  Pointer<Void> term,
  Pointer<IntPtr> outLen,
);
typedef _Reply = Pointer<Uint8> Function(Pointer<Void> term, Pointer<IntPtr> outLen);

typedef _ResizeNative = Pointer<Uint8> Function(
  Pointer<Void> term,
  Int32 cols,
  Int32 rows,
  Int32 cellWidth,
  Int32 cellHeight,
  Pointer<IntPtr> outLen,
);
typedef _Resize = Pointer<Uint8> Function(
  Pointer<Void> term,
  int cols,
  int rows,
  int cellWidth,
  int cellHeight,
  Pointer<IntPtr> outLen,
);

typedef _ScrollNative = Void Function(Pointer<Void> term, Int32 delta);
typedef _Scroll = void Function(Pointer<Void> term, int delta);

typedef _SnapshotNative = Int32 Function(
  Pointer<Void> term,
  Pointer<Int32> cells,
  Int32 cellsCap,
  Pointer<Int32> meta,
  Pointer<Int32> extra,
  Int32 extraCap,
);
typedef _Snapshot = int Function(
  Pointer<Void> term,
  Pointer<Int32> cells,
  int cellsCap,
  Pointer<Int32> meta,
  Pointer<Int32> extra,
  int extraCap,
);

typedef _KeyNative = Pointer<Uint8> Function(
  Pointer<Void> term,
  Int32 key,
  Int32 mods,
  Pointer<Uint8> text,
  Int32 textLen,
  Uint32 unshifted,
  Pointer<IntPtr> outLen,
);
typedef _Key = Pointer<Uint8> Function(
  Pointer<Void> term,
  int key,
  int mods,
  Pointer<Uint8> text,
  int textLen,
  int unshifted,
  Pointer<IntPtr> outLen,
);

typedef _MouseNative = Pointer<Uint8> Function(
  Pointer<Void> term,
  Int32 action,
  Int32 button,
  Int32 pressed,
  Float x,
  Float y,
  Int32 width,
  Int32 height,
  Int32 cellWidth,
  Int32 cellHeight,
  Pointer<IntPtr> outLen,
);
typedef _Mouse = Pointer<Uint8> Function(
  Pointer<Void> term,
  int action,
  int button,
  int pressed,
  double x,
  double y,
  int width,
  int height,
  int cellWidth,
  int cellHeight,
  Pointer<IntPtr> outLen,
);

typedef _FocusNative = Pointer<Uint8> Function(Pointer<Void> term, Int32 gained, Pointer<IntPtr> outLen);
typedef _Focus = Pointer<Uint8> Function(Pointer<Void> term, int gained, Pointer<IntPtr> outLen);

typedef _SelectNative = Void Function(Pointer<Void> term, Int32 x0, Int32 y0, Int32 x1, Int32 y1);
typedef _Select = void Function(Pointer<Void> term, int x0, int y0, int x1, int y1);

typedef _WidthNative = Int32 Function(Uint32 codepoint);
typedef _Width = int Function(int codepoint);

typedef _FreeNative = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);

class _Lib {
  _Lib(DynamicLibrary lib)
    : create = lib.lookupFunction<_CreateNative, _Create>('td_term_create'),
      destroy = lib.lookupFunction<_TermNative, _Term>('td_term_destroy'),
      write = lib.lookupFunction<_BytesNative, _Bytes>('td_term_write'),
      resize = lib.lookupFunction<_ResizeNative, _Resize>('td_term_resize'),
      scroll = lib.lookupFunction<_ScrollNative, _Scroll>('td_term_scroll'),
      snapshot = lib.lookupFunction<_SnapshotNative, _Snapshot>('td_term_snapshot'),
      encodeKey = lib.lookupFunction<_KeyNative, _Key>('td_term_encode_key'),
      encodeMouse = lib.lookupFunction<_MouseNative, _Mouse>('td_term_encode_mouse'),
      encodeFocus = lib.lookupFunction<_FocusNative, _Focus>('td_term_encode_focus'),
      encodePaste = lib.lookupFunction<_BytesNative, _Bytes>('td_term_encode_paste'),
      takeClipboard = lib.lookupFunction<_ReplyNative, _Reply>('td_term_take_clipboard'),
      select = lib.lookupFunction<_SelectNative, _Select>('td_term_select'),
      selectionText = lib.lookupFunction<_ReplyNative, _Reply>('td_term_selection_text'),
      title = lib.lookupFunction<_ReplyNative, _Reply>('td_term_title'),
      codepointWidth = lib.lookupFunction<_WidthNative, _Width>('td_term_codepoint_width'),
      free = lib.lookupFunction<_FreeNative, _Free>('td_term_free');

  final _Create create;
  final _Term destroy;
  final _Bytes write;
  final _Resize resize;
  final _Scroll scroll;
  final _Snapshot snapshot;
  final _Key encodeKey;
  final _Mouse encodeMouse;
  final _Focus encodeFocus;
  final _Bytes encodePaste;
  final _Reply takeClipboard;
  final _Select select;
  final _Reply selectionText;
  final _Reply title;
  final _Width codepointWidth;
  final _Free free;
}

_Lib? _lib;
bool _libTried = false;

/// Same lookup order as the bridge: env override, then the bundle's lib/.
_Lib? _openLib() {
  if (_libTried) return _lib;
  _libTried = true;
  final override = Platform.environment['TAILDECK_TERM'];
  final candidates = <String>[
    if (override != null && override.isNotEmpty) override,
    if (Platform.isLinux)
      '${File(Platform.resolvedExecutable).parent.path}/lib/libtaildeck_term.so',
    if (Platform.isAndroid) 'libtaildeck_term.so',
    if (Platform.isWindows) 'taildeck_term.dll',
    if (Platform.isMacOS)
      '${File(Platform.resolvedExecutable).parent.path}/../Frameworks/libtaildeck_term.dylib',
  ];
  for (final path in candidates) {
    if (path.contains('/') && !File(path).existsSync()) continue;
    try {
      _lib = _Lib(DynamicLibrary.open(path));
      return _lib;
    } on Object {
      continue;
    }
  }
  return null;
}

bool get termSupported => _openLib() != null;
bool get termAvailable => termSupported;

class _FfiTerm implements NativeTerm {
  _FfiTerm(this._lib, this._term, this.cols, this.rows) {
    _alloc(cols, rows);
  }

  final _Lib _lib;
  final Pointer<Void> _term;
  Pointer<Int32> _cells = nullptr;
  Pointer<Int32> _meta = nullptr;
  Pointer<Int32> _extra = nullptr;
  int _cellsCap = 0;
  bool _closed = false;

  @override
  int cols;
  @override
  int rows;

  void _alloc(int cols, int rows) {
    final cap = cols * rows * _snapshotCells;
    if (cap > _cellsCap) {
      if (_cells != nullptr) calloc.free(_cells);
      _cells = calloc<Int32>(cap);
      _cellsCap = cap;
    }
    _meta = _meta == nullptr ? calloc<Int32>(_metaLen) : _meta;
    _extra = _extra == nullptr ? calloc<Int32>(_extraCap) : _extra;
  }

  Uint8List? _copy(Pointer<Uint8> data, int len) {
    if (data == nullptr) return null;
    if (len <= 0) {
      _lib.free(data.cast());
      return null;
    }
    final out = Uint8List.fromList(data.asTypedList(len));
    _lib.free(data.cast());
    return out;
  }

  Uint8List? _reply(_Reply fn) {
    final len = calloc<IntPtr>();
    try {
      return _copy(fn(_term, len), len.value);
    } finally {
      calloc.free(len);
    }
  }

  Uint8List? _withBytes(_Bytes fn, List<int> data) {
    final ptr = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final len = calloc<IntPtr>();
    try {
      ptr.asTypedList(data.length).setAll(0, data);
      return _copy(fn(_term, ptr, data.length, len), len.value);
    } finally {
      calloc.free(ptr);
      calloc.free(len);
    }
  }

  @override
  Uint8List? write(Uint8List data) => _withBytes(_lib.write, data);

  @override
  Uint8List? resize(int cols, int rows, int cellWidth, int cellHeight) {
    final len = calloc<IntPtr>();
    try {
      _alloc(cols, rows);
      final out = _lib.resize(_term, cols, rows, cellWidth, cellHeight, len);
      this.cols = cols;
      this.rows = rows;
      return _copy(out, len.value);
    } finally {
      calloc.free(len);
    }
  }

  @override
  void scroll(int delta) => _lib.scroll(_term, delta);

  @override
  TermSnapshot snapshot() {
    var n = _lib.snapshot(_term, _cells, _cellsCap, _meta, _extra, _extraCap);
    final meta = _meta.asTypedList(_metaLen);
    final cols = meta[TermMeta.cols];
    final rows = meta[TermMeta.rows];
    if (cols * rows * _snapshotCells > _cellsCap) {
      // The terminal grew between resize and this frame; snapshot again.
      _alloc(cols, rows);
      n = _lib.snapshot(_term, _cells, _cellsCap, _meta, _extra, _extraCap);
    }
    return TermSnapshot(
      cols: cols,
      rows: rows,
      cells: Int32List.fromList(_cells.asTypedList(cols * rows * _snapshotCells)),
      meta: Int32List.fromList(_meta.asTypedList(_metaLen)),
      graphemes: _graphemes(n),
    );
  }

  Map<int, String> _graphemes(int len) {
    if (len <= 0) return const {};
    final extra = _extra.asTypedList(len);
    final out = <int, String>{};
    var i = 0;
    while (i + 1 < len) {
      final index = extra[i];
      final count = extra[i + 1];
      final text = StringBuffer();
      for (var k = 0; k < count && i + 2 + k < len; k++) {
        text.writeCharCode(extra[i + 2 + k]);
      }
      out[index] = text.toString();
      i += 2 + count;
    }
    return out;
  }

  @override
  Uint8List? encodeKey(int key, int mods, {String? text, int unshifted = 0}) {
    final bytes = text == null ? null : utf8.encode(text);
    final ptr = bytes == null ? nullptr : calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final len = calloc<IntPtr>();
    try {
      if (bytes != null) ptr.cast<Uint8>().asTypedList(bytes.length).setAll(0, bytes);
      return _copy(
        _lib.encodeKey(_term, key, mods, ptr.cast<Uint8>(), bytes?.length ?? 0, unshifted, len),
        len.value,
      );
    } finally {
      if (ptr != nullptr) calloc.free(ptr);
      calloc.free(len);
    }
  }

  @override
  Uint8List? encodeMouse({
    required int action,
    required int button,
    required bool pressed,
    required double x,
    required double y,
    required int width,
    required int height,
    required int cellWidth,
    required int cellHeight,
  }) {
    final len = calloc<IntPtr>();
    try {
      return _copy(
        _lib.encodeMouse(
          _term,
          action,
          button,
          pressed ? 1 : 0,
          x,
          y,
          width,
          height,
          cellWidth,
          cellHeight,
          len,
        ),
        len.value,
      );
    } finally {
      calloc.free(len);
    }
  }

  @override
  Uint8List? encodeFocus(bool gained) {
    final len = calloc<IntPtr>();
    try {
      return _copy(_lib.encodeFocus(_term, gained ? 1 : 0, len), len.value);
    } finally {
      calloc.free(len);
    }
  }

  @override
  Uint8List? encodePaste(Uint8List data) => _withBytes(_lib.encodePaste, data);

  @override
  Uint8List? takeClipboard() => _reply(_lib.takeClipboard);

  @override
  void select(int x0, int y0, int x1, int y1) => _lib.select(_term, x0, y0, x1, y1);

  @override
  String? selectionText() {
    final bytes = _reply(_lib.selectionText);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  @override
  String? title() {
    final bytes = _reply(_lib.title);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  @override
  int codepointWidth(int codepoint) => _lib.codepointWidth(codepoint);

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _lib.destroy(_term);
    if (_cells != nullptr) calloc.free(_cells);
    if (_meta != nullptr) calloc.free(_meta);
    if (_extra != nullptr) calloc.free(_extra);
    _cells = _meta = _extra = nullptr;
  }
}

NativeTerm? createPlatformTerm({
  required int cols,
  required int rows,
  required int scrollback,
  required int fg,
  required int bg,
  required int cursor,
  String? libraryPath,
}) {
  _Lib? lib;
  if (libraryPath != null) {
    try {
      lib = _Lib(DynamicLibrary.open(libraryPath));
    } on Object {
      return null;
    }
  }
  lib ??= _openLib();
  if (lib == null) return null;
  final term = lib.create(cols, rows, scrollback, fg, bg, cursor);
  if (term == nullptr) return null;
  return _FfiTerm(lib, term, cols, rows);
}
