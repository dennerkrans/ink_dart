// Port of ink's SimpleJson.cs: a minimal JSON reader and writer that keep
// ink's number handling. A number token with `.`, `e` or `E` is a 32-bit
// float ([JsonFloat]); any other is a 32-bit int. Floats are written in
// .NET's round-trip form with a `.0` added when needed.

import '../float32.dart';
import '../system_exception.dart';

/// A float token read from JSON. Kept distinct from `int` so that `3.0`
/// stays a float on every platform.
class JsonFloat {
  const JsonFloat(this.value);

  final double value;

  @override
  bool operator ==(Object other) => other is JsonFloat && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => formatFloat32(value);
}

abstract final class SimpleJson {
  static Map<String, Object?> textToDictionary(String text) =>
      Reader(text).toDictionary();

  static List<Object?> textToArray(String text) => Reader(text).toArray();
}

class Reader {
  Reader(this._text) {
    _skipWhitespace();
    _rootObject = _readObject();
  }

  final String _text;
  int _offset = 0;
  Object? _rootObject;

  Map<String, Object?> toDictionary() => _rootObject as Map<String, Object?>;

  List<Object?> toArray() => _rootObject as List<Object?>;

  static bool _isNumberChar(String c) =>
      c.compareTo('0') >= 0 && c.compareTo('9') <= 0 ||
      c == '.' ||
      c == '-' ||
      c == '+' ||
      c == 'E' ||
      c == 'e';

  static bool _isFirstNumberChar(String c) =>
      c.compareTo('0') >= 0 && c.compareTo('9') <= 0 || c == '-' || c == '+';

  Object? _readObject() {
    final currentChar = _text[_offset];

    if (currentChar == '{') {
      return _readDictionary();
    } else if (currentChar == '[') {
      return _readArray();
    } else if (currentChar == '"') {
      return _readString();
    } else if (_isFirstNumberChar(currentChar)) {
      return _readNumber();
    } else if (_tryRead('true')) {
      return true;
    } else if (_tryRead('false')) {
      return false;
    } else if (_tryRead('null')) {
      return null;
    }

    final end = _offset + 30 < _text.length ? _offset + 30 : _text.length;
    throw SystemException(
      'Unhandled object type in JSON: ${_text.substring(_offset, end)}',
    );
  }

  Map<String, Object?> _readDictionary() {
    final dict = <String, Object?>{};

    _expect('{');

    _skipWhitespace();

    // Empty dictionary?
    if (_tryRead('}')) return dict;

    do {
      _skipWhitespace();

      // Key
      final key = _readString();

      _skipWhitespace();

      // :
      _expect(':');

      _skipWhitespace();

      // Value
      final val = _readObject();
      _expectCondition(val != null, 'dictionary value');

      // Add to dictionary
      dict[key] = val;

      _skipWhitespace();
    } while (_tryRead(','));

    _expect('}');

    return dict;
  }

  List<Object?> _readArray() {
    final list = <Object?>[];

    _expect('[');

    _skipWhitespace();

    // Empty list?
    if (_tryRead(']')) return list;

    do {
      _skipWhitespace();

      // Value
      final val = _readObject();

      // Add to array
      list.add(val);

      _skipWhitespace();
    } while (_tryRead(','));

    _expect(']');

    return list;
  }

  String _readString() {
    _expect('"');

    final sb = StringBuffer();

    for (; _offset < _text.length; _offset++) {
      var c = _text[_offset];

      if (c == '\\') {
        // Escaped character
        _offset++;
        if (_offset >= _text.length) {
          throw SystemException('Unexpected EOF while reading string');
        }
        c = _text[_offset];
        switch (c) {
          case '"':
          case '\\':
          case '/': // Yes, JSON allows this to be escaped
            sb.write(c);
          case 'n':
            sb.write('\n');
          case 't':
            sb.write('\t');
          case 'r':
          case 'b':
          case 'f':
            // Ignore other control characters
            break;
          case 'u':
            // 4-digit Unicode
            if (_offset + 4 >= _text.length) {
              throw SystemException('Unexpected EOF while reading string');
            }
            final digits = _text.substring(_offset + 1, _offset + 5);
            final uchar = RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(digits)
                ? int.parse(digits, radix: 16)
                : null;
            if (uchar != null) {
              sb.writeCharCode(uchar);
              _offset += 4;
            } else {
              throw SystemException(
                'Invalid Unicode escape character at offset ${_offset - 1}',
              );
            }
          default:
            // The escape character is invalid.
            throw SystemException(
              'Invalid Unicode escape character at offset ${_offset - 1}',
            );
        }
      } else if (c == '"') {
        break;
      } else {
        sb.write(c);
      }
    }

    _expect('"');
    return sb.toString();
  }

  Object _readNumber() {
    final startOffset = _offset;

    var isFloat = false;
    for (; _offset < _text.length; _offset++) {
      final c = _text[_offset];
      if (c == '.' || c == 'e' || c == 'E') isFloat = true;
      if (_isNumberChar(c)) {
        continue;
      } else {
        break;
      }
    }

    final numStr = _text.substring(startOffset, _offset);

    if (isFloat) {
      final f = parseFloat32(numStr);
      if (f != null) return JsonFloat(f);
    } else {
      final i = _tryParseInt32(numStr);
      if (i != null) return i;
    }

    throw SystemException('Failed to parse number value: $numStr');
  }

  static int? _tryParseInt32(String s) {
    if (!RegExp(r'^\s*[+-]?[0-9]+\s*$').hasMatch(s)) return null;
    final v = int.tryParse(s.trim());
    if (v == null || v < -0x80000000 || v > 0x7fffffff) return null;
    return v;
  }

  bool _tryRead(String textToRead) {
    if (_offset + textToRead.length > _text.length) return false;

    for (var i = 0; i < textToRead.length; i++) {
      if (textToRead[i] != _text[_offset + i]) return false;
    }

    _offset += textToRead.length;

    return true;
  }

  void _expect(String expectedStr) {
    if (!_tryRead(expectedStr)) _expectCondition(false, expectedStr);
  }

  void _expectCondition(bool condition, [String? message]) {
    if (!condition) {
      var m = message == null ? 'Unexpected token' : 'Expected $message';
      m += ' at offset $_offset';
      throw SystemException(m);
    }
  }

  void _skipWhitespace() {
    while (_offset < _text.length) {
      final c = _text[_offset];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        _offset++;
      } else {
        break;
      }
    }
  }
}

enum _State { none, object, array, property, propertyName, string }

class _StateElement {
  _StateElement(this.type);
  final _State type;
  int childCount = 0;
}

class Writer {
  final StringBuffer _writer = StringBuffer();
  final List<_StateElement> _stateStack = [];

  void clear() => _writer.clear();

  void writeObject(void Function(Writer) inner) {
    writeObjectStart();
    inner(this);
    writeObjectEnd();
  }

  void writeObjectStart() {
    _startNewObject(container: true);
    _stateStack.add(_StateElement(_State.object));
    _writer.write('{');
  }

  void writeObjectEnd() {
    _assert(_state == _State.object);
    _writer.write('}');
    _stateStack.removeLast();
  }

  void writePropertyWith(Object name, void Function(Writer) inner) {
    writePropertyStart(name);
    inner(this);
    writePropertyEnd();
  }

  void writeProperty(String name, String? content) {
    writePropertyStart(name);
    write(content);
    writePropertyEnd();
  }

  void writeIntProperty(String name, int content) {
    writePropertyStart(name);
    writeInt(content);
    writePropertyEnd();
  }

  void writeBoolProperty(String name, bool content) {
    writePropertyStart(name);
    writeBool(content);
    writePropertyEnd();
  }

  /// [name] is a string or an int, written without escaping.
  void writePropertyStart(Object name) {
    _assert(_state == _State.object);

    if (_childCount > 0) _writer.write(',');

    _writer.write('"');
    _writer.write(name);
    _writer.write('":');

    _incrementChildCount();

    _stateStack.add(_StateElement(_State.property));
  }

  void writePropertyEnd() {
    _assert(_state == _State.property);
    _assert(_childCount == 1);
    _stateStack.removeLast();
  }

  void writePropertyNameStart() {
    _assert(_state == _State.object);

    if (_childCount > 0) _writer.write(',');

    _writer.write('"');

    _incrementChildCount();

    _stateStack.add(_StateElement(_State.property));
    _stateStack.add(_StateElement(_State.propertyName));
  }

  void writePropertyNameEnd() {
    _assert(_state == _State.propertyName);

    _writer.write('":');

    // Pop PropertyName, leaving Property state
    _stateStack.removeLast();
  }

  void writePropertyNameInner(String str) {
    _assert(_state == _State.propertyName);
    _writer.write(str);
  }

  void writeArrayStart() {
    _startNewObject(container: true);
    _stateStack.add(_StateElement(_State.array));
    _writer.write('[');
  }

  void writeArrayEnd() {
    _assert(_state == _State.array);
    _writer.write(']');
    _stateStack.removeLast();
  }

  void writeInt(int i) {
    _startNewObject(container: false);
    _writer.write(i);
  }

  /// A 32-bit float, as `SimpleJson.Writer.Write(float)`.
  void writeFloat(double f) {
    _startNewObject(container: false);
    _writer.write(writeJsonFloat32(f));
  }

  void write(String? str, {bool escape = true}) {
    _startNewObject(container: false);

    _writer.write('"');
    if (escape) {
      _writeEscapedString(str ?? '');
    } else {
      _writer.write(str ?? '');
    }
    _writer.write('"');
  }

  void writeBool(bool b) {
    _startNewObject(container: false);
    _writer.write(b ? 'true' : 'false');
  }

  void writeNull() {
    _startNewObject(container: false);
    _writer.write('null');
  }

  void writeStringStart() {
    _startNewObject(container: false);
    _stateStack.add(_StateElement(_State.string));
    _writer.write('"');
  }

  void writeStringEnd() {
    _assert(_state == _State.string);
    _writer.write('"');
    _stateStack.removeLast();
  }

  void writeStringInner(String str, {bool escape = true}) {
    _assert(_state == _State.string);
    if (escape) {
      _writeEscapedString(str);
    } else {
      _writer.write(str);
    }
  }

  void _writeEscapedString(String str) {
    for (var i = 0; i < str.length; i++) {
      final c = str[i];
      if (c.codeUnitAt(0) < 0x20) {
        // Don't write any control characters except \n and \t
        switch (c) {
          case '\n':
            _writer.write('\\n');
          case '\t':
            _writer.write('\\t');
        }
      } else {
        switch (c) {
          case '\\':
          case '"':
            _writer.write('\\');
            _writer.write(c);
          default:
            _writer.write(c);
        }
      }
    }
  }

  void _startNewObject({required bool container}) {
    if (container) {
      _assert(
        _state == _State.none ||
            _state == _State.property ||
            _state == _State.array,
      );
    } else {
      _assert(_state == _State.property || _state == _State.array);
    }

    if (_state == _State.array && _childCount > 0) _writer.write(',');

    if (_state == _State.property) _assert(_childCount == 0);

    if (_state == _State.array || _state == _State.property) {
      _incrementChildCount();
    }
  }

  _State get _state =>
      _stateStack.isNotEmpty ? _stateStack.last.type : _State.none;

  int get _childCount =>
      _stateStack.isNotEmpty ? _stateStack.last.childCount : 0;

  void _incrementChildCount() {
    _assert(_stateStack.isNotEmpty);
    _stateStack.last.childCount++;
  }

  // Debug-only in the reference; the release DLL skips it.
  void _assert(bool condition) {
    assert(condition, 'Assert failed while writing JSON');
  }

  @override
  String toString() => _writer.toString();
}
