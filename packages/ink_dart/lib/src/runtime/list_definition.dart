// Port of ink's ListDefinition.cs.

import 'ink_list_item.dart';

class ListDefinition {
  ListDefinition(this._name, Map<String, int> items)
    : _itemNameToValues = items;

  final String _name;

  /// The main representation should be simple item names rather than a
  /// RawListItem, since we mainly want to access items based on their simple
  /// name, since that's how they'll be most commonly requested from ink.
  final Map<String, int> _itemNameToValues;

  String get name => _name;

  Map<InkListItem, int> get items {
    var i = _items;
    if (i == null) {
      i = {};
      for (final itemNameAndValue in _itemNameToValues.entries) {
        i[InkListItem(name, itemNameAndValue.key)] = itemNameAndValue.value;
      }
      _items = i;
    }
    return i;
  }

  Map<InkListItem, int>? _items;

  int valueForItem(InkListItem item) => _itemNameToValues[item.itemName] ?? 0;

  bool containsItem(InkListItem item) {
    if (item.originName != name) return false;
    return _itemNameToValues.containsKey(item.itemName);
  }

  bool containsItemWithName(String itemName) =>
      _itemNameToValues.containsKey(itemName);

  /// The reference's `TryGetItemWithValue`; null when not found.
  InkListItem? tryGetItemWithValue(int val) {
    for (final namedItem in _itemNameToValues.entries) {
      if (namedItem.value == val) return InkListItem(name, namedItem.key);
    }
    return null;
  }

  /// The reference's `TryGetValueForItem`; null when not found.
  int? tryGetValueForItem(InkListItem item) => _itemNameToValues[item.itemName];
}
