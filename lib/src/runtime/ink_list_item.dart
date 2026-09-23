// Port of ink's InkList.cs: InkListItem.

/// The name of a list item, qualified by the list it comes from.
/// A struct in the reference: an immutable value here.
class InkListItem {
  /// Creates the item [itemName] of the list [originName].
  const InkListItem(this.originName, this.itemName);

  /// Splits `"Origin.item"`.
  factory InkListItem.fromFullName(String fullName) {
    final nameParts = fullName.split('.');
    return InkListItem(nameParts[0], nameParts[1]);
  }

  /// The item with neither origin nor name; `InkListItem.Null` in C#.
  static const InkListItem nullItem = InkListItem(null, null);

  /// The name of the list definition the item belongs to, or null if unknown.
  final String? originName;

  /// The item's own name within its list.
  final String? itemName;

  /// Whether this is [nullItem].
  bool get isNull => originName == null && itemName == null;

  /// The qualified name, `Origin.item` (`?.item` when the origin is unknown).
  String get fullName => '${originName ?? '?'}.$itemName';

  @override
  String toString() => fullName;

  @override
  bool operator ==(Object other) =>
      other is InkListItem &&
      other.itemName == itemName &&
      other.originName == originName;

  @override
  int get hashCode => Object.hash(originName, itemName);
}
