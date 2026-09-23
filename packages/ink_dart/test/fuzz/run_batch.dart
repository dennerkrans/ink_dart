// The differential fuzzer's Dart side (tool/fuzz.mjs): plays each run
// {name, story (path to compiled JSON), seed, script} with the conformance
// harness and writes [{name, events, finalState}], as the C# oracle's
// `--runs` mode does.
//
// Usage: dart run test/fuzz/run_batch.dart runs.json out.json

import 'dart:convert';
import 'dart:io';

import '../conformance/harness.dart';

void main(List<String> args) {
  final runs = jsonDecode(File(args[0]).readAsStringSync()) as List;
  final results = [
    for (final run in runs.cast<Map<String, Object?>>())
      () {
        final result = replay(
          ConformanceCase.run(
            name: run['name'] as String,
            json: File(run['story'] as String).readAsStringSync(),
            seed: run['seed'] as int,
            script: (run['script'] as List).cast<Map<String, Object?>>(),
          ),
        );
        return {
          'name': run['name'],
          'events': result.events,
          'finalState': result.finalState,
        };
      }(),
  ];
  File(args[1]).writeAsStringSync(jsonEncode(results));
}
