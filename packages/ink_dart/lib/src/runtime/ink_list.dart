// Port of ink's InkList.cs (inkjs InkList.ts).

import '../dot_net_dictionary.dart';
import '../story.dart';
import '../system_exception.dart';
import 'ink_list_item.dart';
import 'list_definition.dart';

/// The value of an ink list variable: a set of items, each with its int
/// value. Derives from `Dictionary<InkListItem, int>` in the reference;
/// iteration follows .NET's dictionary order (see [DotNetDictionary]).
///
/// {@category Game functions and variables}
class InkList {
  /// Creates an empty list with no origins.
  InkList();

  /// Copy constructor.
  InkList.from(InkList otherList)
    : _items = DotNetDictionary.from(otherList._items) {
    final otherOriginNames = otherList.originNames;
    if (otherOriginNames != null) _originNames = [...otherOriginNames];
    final otherOrigins = otherList.origins;
    if (otherOrigins != null) origins = [...otherOrigins];
  }

  /// Creates a new empty list with a single origin, looked up in the story.
  InkList.withOrigin(String singleOriginListName, Story originStory) {
    setInitialOriginName(singleOriginListName);

    final def = originStory.listDefinitions?.tryListGetDefinition(
      singleOriginListName,
    );
    if (def != null) {
      origins = [def];
    } else {
      throw SystemException(
        'InkList origin could not be found in story when constructing new '
        'list: $singleOriginListName',
      );
    }
  }

  /// Creates a list holding one item with its int value.
  InkList.single(MapEntry<InkListItem, int> singleElement) {
    add(singleElement.key, singleElement.value);
  }

  /// Creates a list holding the single item named [myListItem] (`item` or
  /// `List.item`), looked up in [originStory]'s list definitions. An empty
  /// name gives an empty list; an unknown name throws.
  static InkList fromString(String myListItem, Story originStory) {
    if (myListItem.isEmpty) return InkList();
    final listValue = originStory.listDefinitions?.findSingleItemListWithName(
      myListItem,
    );
    if (listValue != null) {
      return InkList.from(listValue.value);
    } else {
      throw SystemException(
        "Could not find the InkListItem from the string '$myListItem' to "
        "create an InkList because it doesn't exist in the original list "
        'definition in ink.',
      );
    }
  }

  DotNetDictionary<InkListItem, int> _items = DotNetDictionary();

  // Dictionary members.

  /// The number of items in the list.
  int get count => _items.count;

  /// The int value of [item], or null if the list doesn't contain it.
  int? operator [](InkListItem item) => _items[item];

  /// Adds [item] with [value], or changes its value if already present.
  void operator []=(InkListItem item, int value) => _items[item] = value;

  /// Adds [item] with [value]; throws if the list already contains it
  /// (C#'s `Dictionary.Add`).
  void add(InkListItem item, int value) => _items.add(item, value);

  /// Removes [item]; returns whether it was present.
  bool remove(InkListItem item) => _items.remove(item);

  /// Whether the list contains [item].
  bool containsKey(InkListItem item) => _items.containsKey(item);

  /// The items with their int values, in .NET dictionary order.
  Iterable<MapEntry<InkListItem, int>> get entries => _items.entries;

  /// The items, in .NET dictionary order.
  Iterable<InkListItem> get keys => _items.keys;

  /// Adds [item], taking its int value from its origin list definition. The
  /// origin must be one of this list's [origins]; otherwise this throws.
  void addItem(InkListItem item) {
    if (item.originName == null) {
      addItemNamed(item.itemName ?? '');
      return;
    }

    for (final origin in origins ?? const <ListDefinition>[]) {
      if (origin.name == item.originName) {
        final intVal = origin.tryGetValueForItem(item);
        if (intVal != null) {
          this[item] = intVal;
          return;
        } else {
          throw SystemException(
            'Could not add the item $item to this list because it doesn\'t '
            'exist in the original list definition in ink.',
          );
        }
      }
    }

    throw SystemException(
      'Failed to add item to list because the item was from a new list '
      "definition that wasn't previously known to this list. Only items from "
      'previously known lists can be used, so that the int value can be '
      'found.',
    );
  }

  /// Adds the item named [itemName] from one of this list's [origins], or
  /// looks it up in [storyObject] when the list has no matching origin.
  /// Throws if the name is ambiguous or unknown. `AddItem(string)` in C#.
  void addItemNamed(String itemName, [Story? storyObject]) {
    ListDefinition? foundListDef;

    for (final origin in origins ?? const <ListDefinition>[]) {
      if (origin.containsItemWithName(itemName)) {
        if (foundListDef != null) {
          throw SystemException(
            'Could not add the item $itemName to this list because it could '
            'come from either ${origin.name} or ${foundListDef.name}',
          );
        } else {
          foundListDef = origin;
        }
      }
    }

    if (foundListDef == null) {
      if (storyObject == null) {
        throw SystemException(
          'Could not add the item $itemName to this list because it isn\'t '
          'known to any list definitions previously associated with this '
          'list, and no ink Story object was provided to create it from.',
        );
      } else {
        final newItem = fromString(itemName, storyObject)._orderedItems[0];
        this[newItem.key] = newItem.value;
      }
    } else {
      final item = InkListItem(foundListDef.name, itemName);
      final itemVal = foundListDef.valueForItem(item);
      this[item] = itemVal;
    }
  }

  /// Whether the list contains an item named [itemName], from any origin.
  bool containsItemNamed(String itemName) {
    for (final item in keys) {
      if (item.itemName == itemName) return true;
    }
    return false;
  }

  /// Story has to set this so that the value knows its origin,
  /// necessary for certain operations (e.g. interacting with ints).
  /// Only the story has access to the full set of lists, so that
  /// the origin can be resolved from the originListName.
  List<ListDefinition>? origins;

  /// The list definition of the item with the highest value, or null.
  ListDefinition? get originOfMaxItem {
    final o = origins;
    if (o == null) return null;

    final maxOriginName = maxItem.key.originName;
    for (final origin in o) {
      if (origin.name == maxOriginName) return origin;
    }

    return null;
  }

  /// Origin name needs to be serialised when content is empty,
  /// assuming a name is availble, for list definitions with variable
  /// that is currently empty.
  List<String>? get originNames {
    if (count > 0) {
      final names = _originNames ??= [];
      names.clear();
      for (final item in keys) {
        names.add(item.originName ?? '');
      }
    }
    return _originNames;
  }

  List<String>? _originNames;

  /// Sets the origin name kept while the list is empty.
  void setInitialOriginName(String initialOriginName) {
    _originNames = [initialOriginName];
  }

  /// Sets the origin names kept while the list is empty.
  void setInitialOriginNames(List<String>? initialOriginNames) {
    _originNames = initialOriginNames == null ? null : [...initialOriginNames];
  }

  /// The item with the highest value, or [InkListItem.nullItem] with value 0
  /// when the list is empty.
  MapEntry<InkListItem, int> get maxItem {
    var max = const MapEntry(InkListItem.nullItem, 0);
    for (final kv in entries) {
      if (max.key.isNull || kv.value > max.value) max = kv;
    }
    return max;
  }

  /// The item with the lowest value, or [InkListItem.nullItem] with value 0
  /// when the list is empty.
  MapEntry<InkListItem, int> get minItem {
    var min = const MapEntry(InkListItem.nullItem, 0);
    for (final kv in entries) {
      if (min.key.isNull || kv.value < min.value) min = kv;
    }
    return min;
  }

  /// The items of this list's origins that it doesn't contain (`LIST_INVERT`).
  InkList get inverse {
    final list = InkList();
    for (final origin in origins ?? const <ListDefinition>[]) {
      for (final itemAndValue in origin.items.entries) {
        if (!containsKey(itemAndValue.key)) {
          list.add(itemAndValue.key, itemAndValue.value);
        }
      }
    }
    return list;
  }

  /// Every item of this list's origins (`LIST_ALL`).
  InkList get all {
    final list = InkList();
    for (final origin in origins ?? const <ListDefinition>[]) {
      for (final itemAndValue in origin.items.entries) {
        list[itemAndValue.key] = itemAndValue.value;
      }
    }
    return list;
  }

  /// The items in this list or [otherList] (ink's `+` on lists).
  InkList union(InkList otherList) {
    final union = InkList.from(this);
    for (final kv in otherList.entries) {
      union[kv.key] = kv.value;
    }
    return union;
  }

  /// The items in both this list and [otherList] (ink's `^`).
  InkList intersect(InkList otherList) {
    final intersection = InkList();
    for (final kv in entries) {
      if (otherList.containsKey(kv.key)) intersection.add(kv.key, kv.value);
    }
    return intersection;
  }

  /// Whether this list and [otherList] share any item.
  bool hasIntersection(InkList otherList) {
    for (final item in keys) {
      if (otherList.containsKey(item)) return true;
    }
    return false;
  }

  /// This list without the items of [listToRemove] (ink's `-` on lists).
  InkList without(InkList listToRemove) {
    final result = InkList.from(this);
    for (final item in listToRemove.keys) {
      result.remove(item);
    }
    return result;
  }

  /// Whether this list contains every item of [otherList] (ink's `?`). False
  /// when either list is empty.
  bool contains(InkList otherList) {
    if (otherList.count == 0 || count == 0) return false;
    for (final item in otherList.keys) {
      if (!containsKey(item)) return false;
    }
    return true;
  }

  /// Whether the list contains an item named [listItemName].
  /// `Contains(string)` in C#.
  bool containsName(String listItemName) {
    for (final item in keys) {
      if (item.itemName == listItemName) return true;
    }
    return false;
  }

  /// Whether every item here has a higher value than every item in
  /// [otherList] (ink's `>` on lists).
  bool greaterThan(InkList otherList) {
    if (count == 0) return false;
    if (otherList.count == 0) return true;

    // All greater
    return minItem.value > otherList.maxItem.value;
  }

  /// Ink's `>=` on lists: this list's lowest and highest values are at least
  /// [otherList]'s.
  bool greaterThanOrEquals(InkList otherList) {
    if (count == 0) return false;
    if (otherList.count == 0) return true;

    return minItem.value >= otherList.minItem.value &&
        maxItem.value >= otherList.maxItem.value;
  }

  /// Whether every item here has a lower value than every item in
  /// [otherList] (ink's `<` on lists).
  bool lessThan(InkList otherList) {
    if (otherList.count == 0) return false;
    if (count == 0) return true;

    return maxItem.value < otherList.minItem.value;
  }

  /// Ink's `<=` on lists: this list's highest and lowest values are at most
  /// [otherList]'s.
  bool lessThanOrEquals(InkList otherList) {
    if (otherList.count == 0) return false;
    if (count == 0) return true;

    return maxItem.value <= otherList.maxItem.value &&
        minItem.value <= otherList.minItem.value;
  }

  /// A list holding only the highest item (`LIST_MAX`), or an empty list.
  InkList maxAsList() => count > 0 ? InkList.single(maxItem) : InkList();

  /// A list holding only the lowest item (`LIST_MIN`), or an empty list.
  InkList minAsList() => count > 0 ? InkList.single(minItem) : InkList();

  /// [minBound] and [maxBound] are each an `int` or an [InkList].
  InkList listWithSubRange(Object? minBound, Object? maxBound) {
    if (count == 0) return InkList();

    var minValue = 0;
    var maxValue = 0x7fffffff;

    if (minBound is int) {
      minValue = minBound;
    } else if (minBound is InkList && minBound.count > 0) {
      minValue = minBound.minItem.value;
    }

    if (maxBound is int) {
      maxValue = maxBound;
    } else if (maxBound is InkList && maxBound.count > 0) {
      maxValue = maxBound.maxItem.value;
    }

    final subList = InkList();
    subList.setInitialOriginNames(originNames);
    for (final item in entries) {
      if (item.value >= minValue && item.value <= maxValue) {
        subList.add(item.key, item.value);
      }
    }

    return subList;
  }

  /// Set equality, as the reference's `Equals`.
  @override
  bool operator ==(Object other) {
    if (other is! InkList) return false;
    if (other.count != count) return false;

    for (final item in keys) {
      if (!other.containsKey(item)) return false;
    }

    return true;
  }

  @override
  int get hashCode {
    var ownHash = 0;
    for (final item in keys) {
      ownHash += item.hashCode;
    }
    return ownHash;
  }

  List<MapEntry<InkListItem, int>> get _orderedItems {
    final ordered = [...entries];
    // Stable, like the reference's List.Sort would need to be for ties
    // (ties only occur between items of different origins, which compare
    // by origin name).
    ordered.sort((x, y) {
      // Ensure consistent ordering of mixed lists.
      if (x.value == y.value) {
        return (x.key.originName ?? '').compareTo(y.key.originName ?? '');
      } else {
        return x.value.compareTo(y.value);
      }
    });
    return ordered;
  }

  /// The first item in dictionary order, or [InkListItem.nullItem] when empty.
  InkListItem get singleItem {
    for (final item in keys) {
      return item;
    }
    return InkListItem.nullItem;
  }

  @override
  String toString() {
    final ordered = _orderedItems;

    final sb = StringBuffer();
    for (var i = 0; i < ordered.length; i++) {
      if (i > 0) sb.write(', ');

      final item = ordered[i].key;
      sb.write(item.itemName);
    }

    return sb.toString();
  }
}
