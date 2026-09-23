import 'package:flutter/material.dart';
import 'package:flutter_ink_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
