// Port of ink's StatePatch.cs.

import '../runtime/container.dart';
import '../runtime/ink_object.dart';

/// Changes made during lookahead, applied to the real state only if the
/// lookahead is kept. Containers are keyed by identity, as in the reference.
class StatePatch {
  StatePatch(StatePatch? toCopy) {
    if (toCopy != null) {
      _globals.addAll(toCopy._globals);
      _changedVariables.addAll(toCopy._changedVariables);
      _visitCounts.addAll(toCopy._visitCounts);
      _turnIndices.addAll(toCopy._turnIndices);
    }
  }

  Map<String, InkObject> get globals => _globals;
  Set<String> get changedVariables => _changedVariables;
  Map<Container, int> get visitCounts => _visitCounts;
  Map<Container, int> get turnIndices => _turnIndices;

  /// The reference's `TryGetGlobal`; null when absent.
  InkObject? tryGetGlobal(String? name) => _globals[name];

  void setGlobal(String name, InkObject value) => _globals[name] = value;

  void addChangedVariable(String name) => _changedVariables.add(name);

  /// The reference's `TryGetVisitCount`; null when absent.
  int? tryGetVisitCount(Container container) => _visitCounts[container];

  void setVisitCount(Container container, int count) =>
      _visitCounts[container] = count;

  void setTurnIndex(Container container, int index) =>
      _turnIndices[container] = index;

  /// The reference's `TryGetTurnIndex`; null when absent.
  int? tryGetTurnIndex(Container container) => _turnIndices[container];

  final Map<String, InkObject> _globals = {};
  final Set<String> _changedVariables = {};
  final Map<Container, int> _visitCounts = {};
  final Map<Container, int> _turnIndices = {};
}
