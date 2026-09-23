/// An insertion-ordered map that iterates in the same order as .NET's
/// `Dictionary<TKey, TValue>`.
///
/// .NET keeps entries in an array and reuses the slot of the most recently
/// removed entry for the next insertion, so after a removal, a new key takes
/// the removed key's place in iteration order instead of going to the end.
/// Ink's `InkList` derives from `Dictionary`, and `LIST_RANDOM` picks by
/// iteration position, so the order is observable.
class DotNetDictionary<K, V> {
  DotNetDictionary();

  /// Copies [other] in its iteration order, compacted, as .NET's copy
  /// constructor does.
  DotNetDictionary.from(DotNetDictionary<K, V> other) {
    for (final e in other.entries) {
      add(e.key, e.value);
    }
  }

  final List<_Entry<K, V>?> _entries = [];
  final Map<K, int> _indices = {};
  final List<int> _freeList = [];

  int get count => _indices.length;

  bool get isEmpty => _indices.isEmpty;

  bool containsKey(K key) => _indices.containsKey(key);

  V? operator [](K key) {
    final i = _indices[key];
    return i == null ? null : _entries[i]?.value;
  }

  /// Sets or replaces; a replaced key keeps its position.
  void operator []=(K key, V value) {
    final i = _indices[key];
    if (i != null) {
      _entries[i] = _Entry(key, value);
    } else {
      _insert(key, value);
    }
  }

  /// `Dictionary.Add`: throws if [key] is already present.
  void add(K key, V value) {
    if (_indices.containsKey(key)) {
      throw ArgumentError(
        'An item with the same key has already been added. Key: $key',
      );
    }
    _insert(key, value);
  }

  bool remove(K key) {
    final i = _indices.remove(key);
    if (i == null) return false;
    _entries[i] = null;
    _freeList.add(i);
    return true;
  }

  void clear() {
    _entries.clear();
    _indices.clear();
    _freeList.clear();
  }

  Iterable<MapEntry<K, V>> get entries sync* {
    for (final e in _entries) {
      if (e != null) yield MapEntry(e.key, e.value);
    }
  }

  Iterable<K> get keys => entries.map((e) => e.key);

  void _insert(K key, V value) {
    if (_freeList.isNotEmpty) {
      final i = _freeList.removeLast();
      _entries[i] = _Entry(key, value);
      _indices[key] = i;
    } else {
      _indices[key] = _entries.length;
      _entries.add(_Entry(key, value));
    }
  }
}

class _Entry<K, V> {
  _Entry(this.key, this.value);
  final K key;
  final V value;
}
