import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ink_dart/ink_dart.dart';

import 'story_controller.dart';

/// A panel for writers and developers: where the story is, its variables,
/// visit counts, errors, and optionally a [profiler] report. Rebuilds as
/// the [controller] changes.
///
/// Everything shown comes from the story's public API and its save state,
/// so it matches what a save file would hold.
class StoryDebugView extends StatelessWidget {
  /// Creates a debug view of [controller]'s story.
  const StoryDebugView({super.key, required this.controller, this.profiler});

  /// The story to inspect.
  final StoryController controller;

  /// A profiler from [Story.startProfiling], whose report to show.
  final Profiler? profiler;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final story = controller.story;
        final save = controller.toJson();
        final state = jsonDecode(save) as Map<String, Object?>;
        final visits = (state['visitCounts'] as Map?) ?? const {};
        final turns = (state['turnIndices'] as Map?) ?? const {};
        final theme = Theme.of(context).textTheme;

        Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(text, style: theme.titleSmall),
        );
        Widget row(String key, Object? value) =>
            SelectableText('$key: $value', style: theme.bodySmall);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            heading('Position'),
            row('path', story.state.currentPathString ?? '(none)'),
            row('flow', story.currentFlowName),
            row('can continue', story.canContinue),
            row('choices', controller.choices.length),
            row('turn', story.state.currentTurnIndex),
            row('save size', '${save.length} bytes'),
            heading('Variables'),
            for (final name in story.variablesState)
              row(name, story.variablesState[name]),
            if (visits.isNotEmpty) heading('Visit counts'),
            for (final e in visits.entries) row('${e.key}', e.value),
            if (turns.isNotEmpty) heading('Turn indices'),
            for (final e in turns.entries) row('${e.key}', e.value),
            if (controller.errors.isNotEmpty) heading('Errors and warnings'),
            for (final e in controller.errors) row(e.type.name, e.message),
            if (profiler case final p?) ...[
              heading('Profiler'),
              SelectableText(p.report(), style: theme.bodySmall),
            ],
          ],
        );
      },
    );
  }
}
