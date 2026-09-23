// A complete app: a story on the left, its debug view on the right.
//
// Replace storyJson with your own story compiled by Inky or inklecate.

import 'package:flutter/material.dart';
import 'package:flutter_ink/flutter_ink.dart';

const storyJson =
    r'{"inkVersion":21,"root":[["^The door is locked. ","#","^location: '
    r'cellar","/#","\n","ev","str","^Knock","/str","/ev",{"*":"0.c-0",'
    r'"flg":20},"ev","str","^Leave","/str","/ev",{"*":"0.c-1","flg":20},'
    r'{"c-0":["\n","^Someone answers.","\n","end",{"#f":5}],"c-1":["\n",'
    r'"^You walk away.","\n","end",{"#f":5}]}],"done",null],"listDefs":{}}';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final controller = StoryController.fromJson(storyJson)..continueMaximally();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_ink')),
        body: Row(
          children: [
            Expanded(child: StoryView(controller: controller)),
            const VerticalDivider(),
            Expanded(child: StoryDebugView(controller: controller)),
          ],
        ),
      ),
    );
  }
}
