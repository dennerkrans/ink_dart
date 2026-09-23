// Port of ink's InkList.cs: InkListItem.

/// The name of a list item, qualified by the list it comes from.
/// A struct in the reference: an immutable value here.
class InkListItem {
  const InkListItem(this.originName, this.itemName);

  /// Splits `"Origin.item"`.
  factory InkListItem.fromFullName(String fullName) {
    final nameParts = fullName.split('.');
    return InkListItem(nameParts[0], nameParts[1]);
  }

  static const InkListItem nullItem = InkListItem(null, null);

  final String? originName;
  final String? itemName;

  bool get isNull => originName == null && itemName == null;

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
