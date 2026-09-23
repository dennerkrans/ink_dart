// Port of ink's Path.cs (inkjs Path.ts).

/// One step of a [Path]: an index into a container's content, or a name.
///
/// Nested as `Path.Component` in the reference; immutable.
class Component {
  Component.index(this.index) : name = null;

  Component.named(String this.name) : index = -1;

  factory Component.toParent() => Component.named(Path.parentId);

  final int index;
  final String? name;

  bool get isIndex => index >= 0;

  bool get isParent => name == Path.parentId;

  @override
  String toString() => isIndex ? '$index' : (name ?? '');

  @override
  bool operator ==(Object other) {
    if (other is Component && other.isIndex == isIndex) {
      if (isIndex) {
        return index == other.index;
      } else {
        return name == other.name;
      }
    }
    return false;
  }

  @override
  int get hashCode => isIndex ? index : name.hashCode;
}

class Path {
  static const parentId = '^';

  Path() : _components = [];

  Path.fromHead(Component head, Path tail)
    : _components = [head, ...tail._components];

  Path.fromComponents(Iterable<Component> components, {bool relative = false})
    : _components = [...components],
      _isRelative = relative;

  Path.fromString(String componentsString) : _components = [] {
    _setComponentsString(componentsString);
  }

  static Path get self => Path().._isRelative = true;

  final List<Component> _components;
  bool _isRelative = false;
  String? _componentsString;

  bool get isRelative => _isRelative;

  Component getComponent(int index) => _components[index];

  Component? get head => _components.isNotEmpty ? _components.first : null;

  Path get tail {
    if (_components.length >= 2) {
      return Path.fromComponents(_components.sublist(1));
    } else {
      return Path.self;
    }
  }

  int get length => _components.length;

  Component? get lastComponent =>
      _components.isNotEmpty ? _components.last : null;

  bool get containsNamedComponent {
    for (final comp in _components) {
      if (!comp.isIndex) return true;
    }
    return false;
  }

  Path pathByAppendingPath(Path pathToAppend) {
    final p = Path();

    var upwardMoves = 0;
    for (var i = 0; i < pathToAppend._components.length; ++i) {
      if (pathToAppend._components[i].isParent) {
        upwardMoves++;
      } else {
        break;
      }
    }

    for (var i = 0; i < _components.length - upwardMoves; ++i) {
      p._components.add(_components[i]);
    }

    for (var i = upwardMoves; i < pathToAppend._components.length; ++i) {
      p._components.add(pathToAppend._components[i]);
    }

    return p;
  }

  Path pathByAppendingComponent(Component c) {
    final p = Path();
    p._components.addAll(_components);
    p._components.add(c);
    return p;
  }

  String get componentsString {
    var s = _componentsString;
    if (s == null) {
      s = _components.join('.');
      if (isRelative) s = '.$s';
      _componentsString = s;
    }
    return s;
  }

  void _setComponentsString(String value) {
    _components.clear();

    var s = value;
    _componentsString = s;

    // Empty path, empty components
    // (path is to root, like "/" in file system)
    if (s.isEmpty) return;

    // When components start with ".", it indicates a relative path, e.g.
    //   .^.^.hello.5
    // is equivalent to file system style path:
    //  ../../hello/5
    if (s[0] == '.') {
      _isRelative = true;
      s = s.substring(1);
      _componentsString = s;
    } else {
      _isRelative = false;
    }

    for (final str in s.split('.')) {
      final index = tryParseInt32(str);
      if (index != null) {
        _components.add(Component.index(index));
      } else {
        _components.add(Component.named(str));
      }
    }
  }

  @override
  String toString() => componentsString;

  @override
  bool operator ==(Object other) {
    if (other is! Path) return false;
    if (other._components.length != _components.length) return false;
    if (other.isRelative != isRelative) return false;
    for (var i = 0; i < _components.length; i++) {
      if (other._components[i] != _components[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => toString().hashCode;
}

final _int32Pattern = RegExp(r'^\s*[+-]?[0-9]+\s*$');

/// C#'s `int.TryParse(s, out i)` with the default integer style: optional
/// surrounding whitespace and sign, decimal digits, 32-bit range.
int? tryParseInt32(String s) {
  if (!_int32Pattern.hasMatch(s)) return null;
  final value = int.tryParse(s.trim());
  if (value == null || value < -0x80000000 || value > 0x7fffffff) return null;
  return value;
}
