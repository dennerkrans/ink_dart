// Plays a compiled ink story in the terminal.
//
//   dart run example/play.dart path/to/story.json [--seed N]
//
// At a choice, type its number, `s` to print the state JSON, or `q` to quit.

import 'dart:io';

import 'package:ink_dart/ink_dart.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run example/play.dart story.json [--seed N]');
    exitCode = 64;
    return;
  }

  final story = Story.fromJson(File(args[0]).readAsStringSync());
  story.onError = (message, type) => stderr.writeln('[$type] $message');

  final seedAt = args.indexOf('--seed');
  if (seedAt >= 0 && seedAt + 1 < args.length) {
    story.state.storySeed = int.parse(args[seedAt + 1]);
  }

  final globalTags = story.globalTags;
  if (globalTags != null) print('# ${globalTags.join(' # ')}');

  while (true) {
    while (story.canContinue) {
      stdout.write(story.continueStory());
      final tags = story.currentTags;
      if (tags.isNotEmpty) print('  # ${tags.join(' # ')}');
    }

    final choices = story.currentChoices;
    if (choices.isEmpty) {
      print('--- end ---');
      return;
    }

    print('');
    for (final c in choices) {
      final tags = c.tags;
      final tagText = tags == null ? '' : '  # ${tags.join(' # ')}';
      print('${c.index + 1}: ${c.text}$tagText');
    }

    while (true) {
      stdout.write('> ');
      final input = stdin.readLineSync()?.trim();
      if (input == null || input == 'q') return;
      if (input == 's') {
        print(story.state.toJson());
        continue;
      }
      final n = int.tryParse(input);
      if (n != null && n >= 1 && n <= choices.length) {
        print('');
        story.chooseChoiceIndex(n - 1);
        break;
      }
      print('Type 1-${choices.length}, s or q.');
    }
  }
}
