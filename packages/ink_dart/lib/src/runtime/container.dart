// Port of ink's Container.cs (inkjs Container.ts).

import 'i_named_content.dart';
import 'ink_object.dart';
import 'path.dart';
import 'search_result.dart';
import 'string_value.dart';

class Container extends InkObject implements INamedContent {
  @override
  String? name;

  final List<InkObject> _content = [];

  Map<String, INamedContent> namedContent = {};

  bool visitsShouldBeCounted = false;
  bool turnIndexShouldBeCounted = false;
  bool countingAtStartOnly = false;

  static const countFlagVisits = 1;
  static const countFlagTurns = 2;
  static const countFlagCountStartOnly = 4;

  List<InkObject> get content => _content;

  set content(List<InkObject> value) => addContentList(value);

  Map<String, InkObject>? get namedOnlyContent {
    Map<String, InkObject>? namedOnlyContentDict = {};
    for (final entry in namedContent.entries) {
      namedOnlyContentDict[entry.key] = entry.value as InkObject;
    }

    for (final c in content) {
      if (c is INamedContent) {
        final named = c as INamedContent;
        if (named.hasValidName) namedOnlyContentDict.remove(named.name);
      }
    }

    if (namedOnlyContentDict.isEmpty) namedOnlyContentDict = null;

    return namedOnlyContentDict;
  }

  set namedOnlyContent(Map<String, InkObject>? value) {
    final existingNamedOnly = namedOnlyContent;
    if (existingNamedOnly != null) {
      for (final key in existingNamedOnly.keys) {
        namedContent.remove(key);
      }
    }

    if (value == null) return;

    for (final val in value.values) {
      if (val is INamedContent) addToNamedContentOnly(val as INamedContent);
    }
  }

  int get countFlags {
    var flags = 0;
    if (visitsShouldBeCounted) flags |= countFlagVisits;
    if (turnIndexShouldBeCounted) flags |= countFlagTurns;
    if (countingAtStartOnly) flags |= countFlagCountStartOnly;

    // If we're only storing CountStartOnly, it serves no purpose,
    // since it's dependent on the other two to be used at all.
    // (e.g. for setting the fact that *if* a gather or choice's
    // content is counted, then is should only be counter at the start)
    // So this is just an optimisation for storage.
    if (flags == countFlagCountStartOnly) flags = 0;

    return flags;
  }

  set countFlags(int value) {
    if ((value & countFlagVisits) > 0) visitsShouldBeCounted = true;
    if ((value & countFlagTurns) > 0) turnIndexShouldBeCounted = true;
    if ((value & countFlagCountStartOnly) > 0) countingAtStartOnly = true;
  }

  @override
  bool get hasValidName {
    final n = name;
    return n != null && n.isNotEmpty;
  }

  Path get pathToFirstLeafContent => _pathToFirstLeafContent ??= path
      .pathByAppendingPath(_internalPathToFirstLeafContent);

  Path? _pathToFirstLeafContent;

  Path get _internalPathToFirstLeafContent {
    final components = <Component>[];
    Container? container = this;
    while (container != null) {
      // The reference loops forever on an empty container; stop instead.
      if (container.content.isEmpty) break;
      components.add(Component.index(0));
      final first = container.content[0];
      container = first is Container ? first : null;
    }
    return Path.fromComponents(components);
  }

  void addContent(InkObject contentObj) {
    content.add(contentObj);

    if (contentObj.parent != null) {
      throw StateError('content is already in ${contentObj.parent}');
    }

    contentObj.parent = this;

    tryAddNamedContent(contentObj);
  }

  void addContentList(List<InkObject> contentList) {
    for (final c in contentList) {
      addContent(c);
    }
  }

  void insertContent(InkObject contentObj, int index) {
    content.insert(index, contentObj);

    if (contentObj.parent != null) {
      throw StateError('content is already in ${contentObj.parent}');
    }

    contentObj.parent = this;

    tryAddNamedContent(contentObj);
  }

  void tryAddNamedContent(InkObject contentObj) {
    if (contentObj is INamedContent) {
      final namedContentObj = contentObj as INamedContent;
      if (namedContentObj.hasValidName) addToNamedContentOnly(namedContentObj);
    }
  }

  void addToNamedContentOnly(INamedContent namedContentObj) {
    final runtimeObj = namedContentObj as InkObject;
    runtimeObj.parent = this;

    namedContent[namedContentObj.name ?? ''] = namedContentObj;
  }

  void addContentsOfContainer(Container otherContainer) {
    content.addAll(otherContainer.content);
    for (final obj in otherContainer.content) {
      obj.parent = this;
      tryAddNamedContent(obj);
    }
  }

  InkObject? contentWithPathComponent(Component component) {
    if (component.isIndex) {
      if (component.index >= 0 && component.index < content.length) {
        return content[component.index];
      }
      // When path is out of range, quietly return nil
      // (useful as we step/increment forwards through content)
      else {
        return null;
      }
    } else if (component.isParent) {
      return parent;
    } else {
      final foundContent = namedContent[component.name];
      return foundContent == null ? null : foundContent as InkObject;
    }
  }

  SearchResult contentAtPath(
    Path path, {
    int partialPathStart = 0,
    int partialPathLength = -1,
  }) {
    if (partialPathLength == -1) partialPathLength = path.length;

    final result = SearchResult()..approximate = false;

    Container? currentContainer = this;
    InkObject currentObj = this;

    for (var i = partialPathStart; i < partialPathLength; ++i) {
      final comp = path.getComponent(i);

      // Path component was wrong type
      if (currentContainer == null) {
        result.approximate = true;
        break;
      }

      final foundObj = currentContainer.contentWithPathComponent(comp);

      // Couldn't resolve entire path?
      if (foundObj == null) {
        result.approximate = true;
        break;
      }

      // Are we about to loop into another container?
      // Is the object a container as expected? It might
      // no longer be if the content has shuffled around, so what
      // was originally a container no longer is.
      final nextContainer = foundObj is Container ? foundObj : null;
      if (i < partialPathLength - 1 && nextContainer == null) {
        result.approximate = true;
        break;
      }

      currentObj = foundObj;
      currentContainer = nextContainer;
    }

    result.obj = currentObj;

    return result;
  }

  void buildStringOfHierarchy(
    StringBuffer sb,
    int indentation,
    InkObject? pointedObj,
  ) {
    void appendIndentation() {
      const spacesPerIndent = 4;
      for (var i = 0; i < spacesPerIndent * indentation; ++i) {
        sb.write(' ');
      }
    }

    appendIndentation();
    sb.write('[');

    if (hasValidName) sb.write(' ($name)');

    if (identical(this, pointedObj)) sb.write('  <---');

    sb.writeln();

    indentation++;

    for (var i = 0; i < content.length; ++i) {
      final obj = content[i];

      if (obj is Container) {
        obj.buildStringOfHierarchy(sb, indentation, pointedObj);
      } else {
        appendIndentation();
        if (obj is StringValue) {
          sb.write('"');
          sb.write(obj.toString().replaceAll('\n', '\\n'));
          sb.write('"');
        } else {
          sb.write(obj.toString());
        }
      }

      if (i != content.length - 1) sb.write(',');

      if (obj is! Container && identical(obj, pointedObj)) sb.write('  <---');

      sb.writeln();
    }

    final onlyNamed = <String, INamedContent>{};

    for (final entry in namedContent.entries) {
      if (content.contains(entry.value as InkObject)) {
        continue;
      } else {
        onlyNamed[entry.key] = entry.value;
      }
    }

    if (onlyNamed.isNotEmpty) {
      appendIndentation();
      sb.writeln('-- named: --');

      for (final value in onlyNamed.values) {
        (value as Container).buildStringOfHierarchy(
          sb,
          indentation,
          pointedObj,
        );
        sb.writeln();
      }
    }

    indentation--;

    appendIndentation();
    sb.write(']');
  }
}
