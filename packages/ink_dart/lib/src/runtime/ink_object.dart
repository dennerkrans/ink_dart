// Port of ink's Object.cs (inkjs Object.ts).

import 'container.dart';
import 'debug_metadata.dart';
import 'i_named_content.dart';
import 'path.dart';
import 'search_result.dart';

/// Base class for all ink runtime content.
///
/// Equality is identity, as in the reference, where `Runtime.Object`
/// compares by reference.
class InkObject {
  /// Usually a [Container].
  InkObject? parent;

  /// Source location of this content, or of its nearest ancestor that has
  /// one; null for stories compiled without debug information.
  DebugMetadata? get debugMetadata {
    if (_debugMetadata == null) {
      final p = parent;
      if (p != null) return p.debugMetadata;
    }
    return _debugMetadata;
  }

  /// Sets this object's own source location.
  set debugMetadata(DebugMetadata? value) => _debugMetadata = value;

  /// This object's own source location, without falling back to ancestors.
  DebugMetadata? get ownDebugMetadata => _debugMetadata;

  DebugMetadata? _debugMetadata;

  /// The source line number of the content at [path], if debug metadata is
  /// available; otherwise null.
  int? debugLineNumberOfPath(Path? path) {
    if (path == null) return null;

    // Try to get a line number from debug metadata
    final root = rootContentContainer;
    if (root != null) {
      final targetContent = root.contentAtPath(path).obj;
      if (targetContent != null) {
        final dm = targetContent.debugMetadata;
        if (dm != null) return dm.startLineNumber;
      }
    }
    return null;
  }

  /// The path to this object from the root of the story.
  Path get path {
    var p = _path;
    if (p == null) {
      if (parent == null) {
        p = Path();
      } else {
        // Iterate up the hierarchy from the leaves/children to the root,
        // collecting components in reverse.
        final comps = <Component>[];
        InkObject child = this;
        var container = child.parent is Container
            ? child.parent as Container
            : null;
        while (container != null) {
          final namedChild = child is INamedContent
              ? child as INamedContent
              : null;
          if (namedChild != null && namedChild.hasValidName) {
            comps.add(Component.named(namedChild.name ?? ''));
          } else {
            comps.add(Component.index(container.content.indexOf(child)));
          }
          child = container;
          final next = container.parent;
          container = next is Container ? next : null;
        }
        p = Path.fromComponents(comps.reversed);
      }
      _path = p;
    }
    return p;
  }

  Path? _path;

  /// Looks up the content at [path], relative to this object if the path is
  /// relative, else from the root.
  SearchResult resolvePath(Path path) {
    if (path.isRelative) {
      var nearestContainer = this is Container ? this as Container : null;
      if (nearestContainer == null) {
        final p = parent;
        nearestContainer = p is Container ? p : null;
        path = path.tail;
      }
      if (nearestContainer == null) {
        throw StateError(
          "Can't resolve relative path because we don't have a parent",
        );
      }
      return nearestContainer.contentAtPath(path);
    } else {
      final root = rootContentContainer;
      if (root == null) {
        throw StateError("Can't resolve path without a root container");
      }
      return root.contentAtPath(path);
    }
  }

  /// Converts [globalPath] into a path relative to this object, using `^`
  /// components to climb to the nearest shared ancestor.
  Path convertPathToRelative(Path globalPath) {
    // 1. Find last shared ancestor
    // 2. Drill up using ".." style (actually represented as "^")
    // 3. Re-build downward chain from common ancestor
    final ownPath = path;

    final minPathLength = globalPath.length < ownPath.length
        ? globalPath.length
        : ownPath.length;
    var lastSharedPathCompIndex = -1;

    for (var i = 0; i < minPathLength; ++i) {
      final ownComp = ownPath.getComponent(i);
      final otherComp = globalPath.getComponent(i);

      if (ownComp == otherComp) {
        lastSharedPathCompIndex = i;
      } else {
        break;
      }
    }

    // No shared path components, so just use global path
    if (lastSharedPathCompIndex == -1) return globalPath;

    final numUpwardsMoves = (ownPath.length - 1) - lastSharedPathCompIndex;

    final newPathComps = <Component>[];

    for (var up = 0; up < numUpwardsMoves; ++up) {
      newPathComps.add(Component.toParent());
    }

    for (
      var down = lastSharedPathCompIndex + 1;
      down < globalPath.length;
      ++down
    ) {
      newPathComps.add(globalPath.getComponent(down));
    }

    return Path.fromComponents(newPathComps, relative: true);
  }

  /// Finds the most compact representation for a path, whether relative or
  /// global.
  String compactPathString(Path otherPath) {
    String globalPathStr;
    String relativePathStr;

    if (otherPath.isRelative) {
      relativePathStr = otherPath.componentsString;
      globalPathStr = path.pathByAppendingPath(otherPath).componentsString;
    } else {
      final relativePath = convertPathToRelative(otherPath);
      relativePathStr = relativePath.componentsString;
      globalPathStr = otherPath.componentsString;
    }

    if (relativePathStr.length < globalPathStr.length) {
      return relativePathStr;
    } else {
      return globalPathStr;
    }
  }

  /// The container at the root of this object's hierarchy, or null if the
  /// root isn't a container.
  Container? get rootContentContainer {
    InkObject ancestor = this;
    for (var p = ancestor.parent; p != null; p = ancestor.parent) {
      ancestor = p;
    }
    return ancestor is Container ? ancestor : null;
  }

  /// A copy of this object; throws for kinds of content that can't be copied.
  /// The reference's default `Object.ToString()`: the runtime type's full
  /// name. Most subclasses override it.
  @override
  String toString() => 'Ink.Runtime.$runtimeType';

  InkObject copy() {
    throw UnsupportedError("$runtimeType doesn't support copying");
  }
}
