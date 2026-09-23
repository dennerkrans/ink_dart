// Port of ink's ChoicePoint.cs.

import 'container.dart';
import 'ink_object.dart';
import 'path.dart';

/// The ChoicePoint represents the point within the Story where a Choice
/// instance gets generated. The distinction is made because the text of the
/// Choice can be dynamically generated.
class ChoicePoint extends InkObject {
  ChoicePoint([this.onceOnly = true]);

  Path? get pathOnChoice {
    // Resolve any relative paths to global ones as we come across them
    final p = _pathOnChoice;
    if (p != null && p.isRelative) {
      final choiceTargetObj = choiceTarget;
      if (choiceTargetObj != null) _pathOnChoice = choiceTargetObj.path;
    }
    return _pathOnChoice;
  }

  set pathOnChoice(Path? value) => _pathOnChoice = value;

  Path? _pathOnChoice;

  Container? get choiceTarget {
    final p = _pathOnChoice;
    return p == null ? null : resolvePath(p).container;
  }

  String get pathStringOnChoice {
    final p = pathOnChoice;
    return p == null ? '' : compactPathString(p);
  }

  set pathStringOnChoice(String value) => pathOnChoice = Path.fromString(value);

  bool hasCondition = false;
  bool hasStartContent = false;
  bool hasChoiceOnlyContent = false;
  bool onceOnly;
  bool isInvisibleDefault = false;

  int get flags {
    var flags = 0;
    if (hasCondition) flags |= 1;
    if (hasStartContent) flags |= 2;
    if (hasChoiceOnlyContent) flags |= 4;
    if (isInvisibleDefault) flags |= 8;
    if (onceOnly) flags |= 16;
    return flags;
  }

  set flags(int value) {
    hasCondition = (value & 1) > 0;
    hasStartContent = (value & 2) > 0;
    hasChoiceOnlyContent = (value & 4) > 0;
    isInvisibleDefault = (value & 8) > 0;
    onceOnly = (value & 16) > 0;
  }

  @override
  String toString() {
    final targetLineNum = debugLineNumberOfPath(pathOnChoice);
    var targetString = pathOnChoice.toString();

    if (targetLineNum != null) {
      targetString = ' line $targetLineNum($targetString)';
    }

    return 'Choice: -> $targetString';
  }
}
