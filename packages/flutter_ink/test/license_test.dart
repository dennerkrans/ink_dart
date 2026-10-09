import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Flutter's licence collector splits a package's LICENSE at every line of
  // exactly 80 hyphens and names each part by its first paragraph, so such a
  // line turns the notices into made-up packages on an app's licences page.
  test('the LICENSE reads as one licence in a Flutter app', () {
    final text = File('LICENSE').readAsStringSync();
    expect(text, isNot(contains('\n${'-' * 80}\n')));
  });
}
