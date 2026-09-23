import 'package:ink_dart/ink_dart.dart';
import 'package:test/test.dart';

/// A story that prints `name(args...)` for one external call per line.
Story storyCalling(String name, List<Object> args) {
  final argTokens = [
    for (final a in args) a is String ? '"^$a"' : '$a',
  ].join(',');
  final argPart = argTokens.isEmpty ? '' : '$argTokens,';
  return Story.fromJson(
    '{"inkVersion":21,"root":[["ev",$argPart'
    '{"x()":"$name","exArgs":${args.length}},"out","/ev","\\n","done",'
    '{"#n":"g-0"}],"done",null],"listDefs":{}}',
  );
}

void main() {
  test('no arguments', () {
    final story = storyCalling('f', [])
      ..bindExternalFunction0('f', () => 'zero');
    expect(story.continueStory(), 'zero\n');
  });

  test('two arguments, converted', () {
    final story = storyCalling('f', [2.5, 3])
      ..bindExternalFunction2<int, String>('f', (n, s) => '$n:$s');
    expect(story.continueStory(), '2:3\n');
  });

  test('three and four arguments', () {
    final three = storyCalling('f', [1, 2, 3])
      ..bindExternalFunction3<int, int, int>('f', (a, b, c) => a + b + c);
    expect(three.continueStory(), '6\n');

    final four = storyCalling('f', [1, 2.0, 1, 'x'])
      ..bindExternalFunction4<double, int, bool, String>(
        'f',
        (a, b, c, d) => '$a $b $c $d',
      );
    expect(four.continueStory(), '1.0 2 true x\n');
  });

  test('a function returning nothing returns nothing to ink', () {
    var calls = 0;
    final story = storyCalling('f', [1])
      ..bindExternalFunction1<int>('f', (_) {
        calls++;
      });
    expect(story.continueStory(), '');
    expect(calls, 1);
  });

  test('wrong number of arguments fails like the reference', () {
    final story = storyCalling('f', [1, 2])
      ..bindExternalFunction1<int>('f', (x) => x);
    expect(
      story.continueStory,
      throwsA(
        isA<SystemException>().having(
          (e) => e.message,
          'message',
          'External function expected one argument ',
        ),
      ),
    );
  });

  test('general binding passes arguments unconverted', () {
    final seen = <Object?>[];
    final story = storyCalling('f', [2.5, 7])
      ..bindExternalFunctionGeneral('f', (args) {
        seen.addAll(args);
        return null;
      });
    story.continueStory();
    expect(seen, [2.5, 7]);
  });
}
