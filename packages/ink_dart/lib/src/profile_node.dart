// Port of ink's Profiler.cs: ProfileNode.

import 'profiler.dart';

/// Node used in the hierarchical tree of timings used by the Profiler.
/// Each node corresponds to a single line viewable in a UI-based
/// representation.
class ProfileNode {
  /// Creates a node; the profiler builds the tree as it samples.
  ProfileNode([this.key]);

  /// The key for the node corresponds to the printable name of the callstack
  /// element.
  final String? key;

  /// Horribly hacky field only used by ink unity integration, but saves
  /// constructing an entire data structure that mirrors the one in here
  /// purely to store the state of whether each node in the UI has been
  /// opened or not.
  bool openInUI = false;

  /// Whether this node contains any sub-nodes - i.e. does it call anything
  /// else that has been recorded?
  bool get hasChildren {
    final n = _nodes;
    return n != null && n.isNotEmpty;
  }

  /// Total number of milliseconds this node has been active for.
  int get totalMillisecs => _totalMillisecs.toInt();

  /// How many steps were recorded under this node, including its children.
  int get totalSampleCount => _totalSampleCount;

  /// How many steps were recorded at exactly this node.
  int get selfSampleCount => _selfSampleCount;

  /// Records a step with the given call stack, root first.
  void addSample(List<String> stack, double duration) {
    _addSample(stack, -1, duration);
  }

  void _addSample(List<String> stack, int stackIdx, double duration) {
    _totalSampleCount++;
    _totalMillisecs += duration;

    if (stackIdx == stack.length - 1) {
      _selfSampleCount++;
      _selfMillisecs += duration;
    }

    if (stackIdx + 1 < stack.length) {
      _addSampleToNode(stack, stackIdx + 1, duration);
    }
  }

  void _addSampleToNode(List<String> stack, int stackIdx, double duration) {
    final nodeKey = stack[stackIdx];
    final nodes = _nodes ??= {};

    final node = nodes.putIfAbsent(nodeKey, () => ProfileNode(nodeKey));

    node._addSample(stack, stackIdx, duration);
  }

  /// Returns a sorted enumerable of the nodes in descending order of how
  /// long they took to run.
  Iterable<MapEntry<String, ProfileNode>>? get descendingOrderedNodes {
    final n = _nodes;
    if (n == null) return null;
    return [...n.entries]..sort(
      (a, b) => b.value._totalMillisecs.compareTo(a.value._totalMillisecs),
    );
  }

  void _printHierarchy(StringBuffer sb, int indent) {
    _pad(sb, indent);

    sb
      ..write(key ?? '')
      ..write(': ')
      ..writeln(ownReport);

    final nodes = descendingOrderedNodes;
    if (nodes == null) return;

    for (final keyNode in nodes) {
      keyNode.value._printHierarchy(sb, indent + 1);
    }
  }

  /// Generates a string giving timing information for this single node,
  /// including total milliseconds spent on the piece of ink, the time spent
  /// within itself (v.s. spent in children), as well as the number of
  /// samples (instruction steps) recorded for both too.
  String get ownReport =>
      'total ${Profiler.formatMillisecs(_totalMillisecs)}, '
      'self ${Profiler.formatMillisecs(_selfMillisecs)} '
      '($_selfSampleCount self samples, $_totalSampleCount total)';

  void _pad(StringBuffer sb, int spaces) {
    for (var i = 0; i < spaces; i++) {
      sb.write('   ');
    }
  }

  /// String is a report of the sub-tree from this node, but without any of
  /// the header information that's prepended by the Profiler in its
  /// Report() method.
  @override
  String toString() {
    final sb = StringBuffer();
    _printHierarchy(sb, 0);
    return sb.toString();
  }

  Map<String, ProfileNode>? _nodes;
  double _selfMillisecs = 0;
  double _totalMillisecs = 0;
  int _selfSampleCount = 0;
  int _totalSampleCount = 0;
}
