// Runs the snippets in doc/*.md and lib/ink_dart.dart against a real story,
// so the guides stay true to the API. Keep each test beside the guide
// section it checks.

import 'dart:io';

import 'package:ink_dart/ink_dart.dart';
import 'package:test/test.dart';

final storyJson = File('test/unit/fixtures/docs_story.json').readAsStringSync();

Story boundStory() => Story.fromJson(storyJson)
  ..bindExternalFunction1<int>('roll', (sides) => 3)
  ..bindExternalFunction2<String, int>('give', (item, count) {});

void main() {
  group('getting started', () {
    test('the play loop, tags and choices', () {
      final story = boundStory();
      final errors = <String>[];
      story.onError = (message, type) => errors.add('$type: $message');

      final lines = <String>[];
      final tags = <List<String>>[];
      while (story.canContinue) {
        lines.add(story.continueStory());
        tags.add(story.currentTags);
      }
      // `roll` isn't lookahead-safe, so the engine stops before calling it
      // and calls it in a second, empty continue.
      expect(lines, ['Hello, nobody.\n', '']);
      expect(tags.first, ['title: Docs story', 'greeting']);
      expect(story.globalTags, ['title: Docs story']);
      expect(story.tagsForContentAtPath('market'), ['market tag']);

      expect(story.currentChoices.map((c) => c.text), ['Market', 'Leave']);
      story.chooseChoiceIndex(story.currentChoices.first.index);
      expect(story.continueMaximally(), 'The market. Gold 4.\n');
      expect(story.currentChoices, isEmpty);
      expect(errors, isEmpty);
    });

    test('without onError, the first problem is thrown', () {
      final story = Story.fromJson(storyJson);
      expect(story.continueStory, throwsA(isA<StoryException>()));
    });

    test('jumping and restarting', () {
      final story = boundStory()..continueMaximally();
      story.choosePathString('market');
      expect(story.continueStory(), 'The market. Gold 4.\n');
      story.resetState();
      expect(story.variablesState['gold'], 0);
    });
  });

  group('game functions and variables', () {
    test('variables and observers', () {
      final story = boundStory();
      story.variablesState['strength'] = 3;
      story.variablesState['name'] = 'Ada';
      expect([...story.variablesState], contains('gold'));
      expect(
        () => story.variablesState['undeclared'] = 1,
        throwsA(isA<StoryException>()),
      );

      final seen = <Object?>[];
      story.observeVariable('gold', (name, value) => seen.add(value));
      expect(story.continueMaximally(), 'Hello, Ada.\n');
      expect(seen, [3]);
      expect(story.variablesState['gold'], 3);
    });

    test('an unbound function throws at the first continue', () {
      final story = Story.fromJson(storyJson)..onError = (_, _) {};
      expect(
        story.continueStory,
        throwsA(
          isA<StoryException>().having(
            (e) => e.message,
            'message',
            contains("'roll', 'give'"),
          ),
        ),
      );
    });

    test('fallbacks call the ink function instead', () {
      final story = Story.fromJson(storyJson)
        ..allowExternalFunctionFallbacks = true
        ..bindExternalFunction2<String, int>('give', (item, count) {})
        ..state.storySeed = 1;
      story.continueMaximally();
      expect(story.variablesState['gold'], inInclusiveRange(1, 6));
    });

    test('calling ink functions', () {
      final story = boundStory();
      expect(story.evaluateFunction('price_of', ['sword']), 10);
      final r = story.evaluateFunctionWithOutput('describe', ['sword']);
      expect(r.textOutput, 'A fine sword.\n');
      expect(r.result, 'described');
    });

    test('lists', () {
      final story = boundStory();
      final inventory = story.variablesState['inventory'] as InkList;
      expect(inventory.containsItemNamed('lantern'), isTrue);
      expect('$inventory', 'lantern, map');
    });
  });

  test('saving and loading', () {
    final story = boundStory()..continueMaximally();
    final saved = story.state.toJson();

    final restored = boundStory()..state.loadJson(saved);
    expect(restored.currentChoices.map((c) => c.text), ['Market', 'Leave']);
    restored.chooseChoiceIndex(0);
    expect(restored.continueMaximally(), 'The market. Gold 4.\n');

    final frozen = story.copyStateForBackgroundThreadSave();
    story.chooseChoiceIndex(1);
    expect(frozen.toJson(), saved);
    story.backgroundSaveComplete();
  });

  test('flows', () {
    final story = boundStory()..continueMaximally();
    story.switchFlow('market');
    story.choosePathString('market');
    expect(story.continueMaximally(), 'The market. Gold 4.\n');

    story.switchToDefaultFlow();
    expect(story.currentFlowName, 'DEFAULT_FLOW');
    expect(story.aliveFlowNames, ['market']);
    expect(story.currentChoices, hasLength(2));
    story.removeFlow('market');
    expect(story.aliveFlowNames, isEmpty);
  });

  test('matching Unity and Inky: numbers', () {
    // 7 / 3.0 prints as .NET prints a 32-bit float.
    final story = Story.fromJson(
      '{"inkVersion":21,"root":[["ev",7,3.0,"/","out","/ev","\\n","done",'
      '{"#n":"g-0"}],"done",null],"listDefs":{}}',
    );
    expect(story.continueStory(), '2.3333333\n');
  });
}
