import 'package:ink_dart/src/dot_net_dictionary.dart';
import 'package:test/test.dart';

// Expected orders recorded from .NET 10's Dictionary<string, int>.
void main() {
  test('iteration order matches .NET after removals', () {
    final d = DotNetDictionary<String, int>();
    List<String> keys() => [...d.keys];

    d
      ..add('a', 1)
      ..add('b', 2)
      ..add('c', 3);
    expect(keys(), ['a', 'b', 'c']);

    d
      ..remove('b')
      ..add('d', 4);
    expect(keys(), ['a', 'd', 'c']);

    d
      ..remove('a')
      ..remove('c')
      ..add('e', 5)
      ..add('f', 6)
      ..add('g', 7);
    expect(keys(), ['f', 'd', 'e', 'g']);

    d['d'] = 40;
    d
      ..remove('f')
      ..['h'] = 8;
    expect(keys(), ['h', 'd', 'e', 'g']);

    final copy = DotNetDictionary<String, int>.from(d)
      ..remove('e')
      ..add('i', 9);
    expect([...copy.keys], ['h', 'd', 'i', 'g']);
  });

  test('add rejects a duplicate key, as Dictionary.Add does', () {
    final d = DotNetDictionary<String, int>()..add('a', 1);
    expect(() => d.add('a', 2), throwsArgumentError);
  });
}
