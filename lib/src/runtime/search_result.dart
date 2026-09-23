// Port of ink's SearchResult.cs.

import 'container.dart';
import 'ink_object.dart';

/// The result of looking up content by path; a struct in the reference.
class SearchResult {
  InkObject? obj;
  bool approximate = false;

  InkObject? get correctObj => approximate ? null : obj;

  Container? get container {
    final o = obj;
    return o is Container ? o : null;
  }
}
