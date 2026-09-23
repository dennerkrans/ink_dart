import 'package:flutter/material.dart';
import 'package:ink_dart/ink_dart.dart';

import 'story_controller.dart';

/// Shows a story's lines and its current choices, and rebuilds as the
/// [controller] changes.
///
/// By default lines are plain [Text] and choices are [TextButton]s, so the
/// view needs a [Material] ancestor; pass [lineBuilder] and [choiceBuilder]
/// to draw them your own way.
class StoryView extends StatelessWidget {
  /// Creates a view of [controller]'s story.
  const StoryView({
    super.key,
    required this.controller,
    this.lineBuilder,
    this.choiceBuilder,
    this.padding = const EdgeInsets.all(16),
  });

  /// The story to show.
  final StoryController controller;

  /// Builds one line of output; defaults to its text without the trailing
  /// newline.
  final Widget Function(BuildContext context, StoryLine line)? lineBuilder;

  /// Builds one choice; call `onSelected` to choose it. Defaults to a
  /// [TextButton].
  final Widget Function(
    BuildContext context,
    Choice choice,
    VoidCallback onSelected,
  )?
  choiceBuilder;

  /// Space around the list.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final lines = controller.lines;
        final choices = controller.choices;
        return ListView(
          padding: padding,
          children: [
            for (final line in lines)
              lineBuilder?.call(context, line) ?? _defaultLine(line),
            for (final choice in choices)
              choiceBuilder?.call(
                    context,
                    choice,
                    () => controller.choose(choice.index),
                  ) ??
                  _defaultChoice(choice),
          ],
        );
      },
    );
  }

  Widget _defaultLine(StoryLine line) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(line.text.trimRight()),
  );

  Widget _defaultChoice(Choice choice) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton(
      onPressed: () => controller.choose(choice.index),
      child: Text(choice.text),
    ),
  );
}
