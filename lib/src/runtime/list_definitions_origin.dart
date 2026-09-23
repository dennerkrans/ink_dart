// Port of ink's ListDefinitionsOrigin.cs.

import 'list_definition.dart';
import 'list_value.dart';

class ListDefinitionsOrigin {
  ListDefinitionsOrigin(List<ListDefinition> lists) {
    for (final list in lists) {
      _lists[list.name] = list;

      for (final itemWithValue in list.items.entries) {
        final item = itemWithValue.key;
        final val = itemWithValue.value;
        final listValue = ListValue.single(item, val);

        // May be ambiguous, but compiler should've caught that,
        // so we may be doing some replacement here, but that's okay.
        _allUnambiguousListValueCache[item.itemName ?? ''] = listValue;
        _allUnambiguousListValueCache[item.fullName] = listValue;
      }
    }
  }

  final Map<String, ListDefinition> _lists = {};
  final Map<String, ListValue> _allUnambiguousListValueCache = {};

  List<ListDefinition> get lists => [..._lists.values];

  /// The reference's `TryListGetDefinition`; null when not found.
  ListDefinition? tryListGetDefinition(String? name) => _lists[name];

  ListValue? findSingleItemListWithName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    return _allUnambiguousListValueCache[name];
  }
}
