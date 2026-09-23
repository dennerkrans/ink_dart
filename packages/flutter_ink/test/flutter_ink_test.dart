import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_ink/flutter_ink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../example/example.dart';

StoryController load(String name) => StoryController.fromJson(
  File('test/fixtures/$name.json').readAsStringSync(),
);

Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('StoryController', () {
    test('does not continue until asked, then collects lines and tags', () {
      final c = load('tavern');
      expect(c.lines, isEmpty);
      expect(c.canContinue, isTrue);

      var notified = 0;
      c.addListener(() => notified++);
      c.continueMaximally();

      expect(notified, 1);
      expect(c.lines.map((l) => l.text), [
        'The tavern is loud.\n',
        'The barkeep nods.\n',
      ]);
      expect(c.lines.first.tags, ['scene: tavern']);
      expect(c.choices.map((ch) => ch.text), ['Buy a drink', 'Leave']);
      expect(c.isEnded, isFalse);
    });

    test('choose continues to the end; watch follows a variable', () {
      final c = load('tavern');
      final gold = c.watch('gold');
      expect(gold.value, 3);

      c.continueMaximally();
      c.choose(0);

      expect(c.lines.last.text, 'You drink. Gold left: 2.\n');
      expect(gold.value, 2);
      expect(c.isEnded, isTrue);
      c.dispose();
    });

    test('errors are collected, not thrown', () {
      final c = load('broken');
      c.continueMaximally();
      expect(c.errors, hasLength(1));
      expect(c.errors.single.type, ErrorType.error);
      expect(c.errors.single.message, contains("variable (target)"));
    });

    test('save and load round-trip through the controller', () {
      final c = load('tavern')..continueMaximally();
      final saved = c.toJson();
      c.choose(1);
      expect(c.lines.last.text, 'You leave.\n');

      c.loadJson(saved);
      expect(c.lines, isEmpty);
      expect(c.choices, hasLength(2));
      c.choose(0);
      expect(c.lines.single.text, 'You drink. Gold left: 2.\n');
    });
  });

  group('StoryView', () {
    testWidgets('shows lines and choices; tapping a choice plays on', (
      tester,
    ) async {
      final c = load('tavern')..continueMaximally();
      await tester.pumpWidget(app(StoryView(controller: c)));

      expect(find.text('The tavern is loud.'), findsOneWidget);
      expect(find.text('Buy a drink'), findsOneWidget);

      await tester.tap(find.text('Leave'));
      await tester.pump();

      expect(find.text('You leave.'), findsOneWidget);
      expect(find.text('Buy a drink'), findsNothing);
    });

    testWidgets('custom builders replace the defaults', (tester) async {
      final c = load('tavern')..continueMaximally();
      await tester.pumpWidget(
        app(
          StoryView(
            controller: c,
            lineBuilder: (context, line) => Text('> ${line.text.trim()}'),
            choiceBuilder: (context, choice, onSelected) => ElevatedButton(
              onPressed: onSelected,
              child: Text('[${choice.text}]'),
            ),
          ),
        ),
      );

      expect(find.text('> The barkeep nods.'), findsOneWidget);
      await tester.tap(find.text('[Buy a drink]'));
      await tester.pump();
      expect(find.text('> You drink. Gold left: 2.'), findsOneWidget);
    });
  });

  testWidgets('StoryDebugView shows position, variables and errors', (
    tester,
  ) async {
    final c = load('broken')..continueMaximally();
    final story = c.story;
    await tester.pumpWidget(app(StoryDebugView(controller: c)));

    expect(find.text('flow: ${story.currentFlowName}'), findsOneWidget);
    expect(find.text('target: 0'), findsOneWidget);
    expect(find.textContaining('error: RUNTIME ERROR'), findsOneWidget);
  });

  testWidgets('the example app plays', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('The door is locked.'), findsOneWidget);
    await tester.tap(find.text('Knock'));
    await tester.pump();
    expect(find.text('Someone answers.'), findsOneWidget);
  });
}
