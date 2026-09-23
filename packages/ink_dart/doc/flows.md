Run several independent threads of story in one `Story`, such as a main
plot and side conversations.

A flow has its own position, output and choices, and shares everything
else: global variables, visit counts and the random seed.

```dart
story.switchFlow('market');        // created on first use
story.choosePathString('market');  // position the new flow
story.continueMaximally();

story.switchToDefaultFlow();       // back to the main story
print(story.currentFlowName);      // DEFAULT_FLOW
print(story.aliveFlowNames);       // [market]
story.removeFlow('market');
```

The default flow can't be removed. Saves hold every flow and which one is
current.
