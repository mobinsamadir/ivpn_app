import 'dart:io';

void main() {
  var file = File('lib/widgets/config_card.dart');
  var content = file.readAsStringSync();

  // The error in config_card.dart is from:
  // error • The method '_getPingColor' isn't defined for the type 'ConfigCard'.
  // error • The method '_getTierColor' isn't defined for the type 'ConfigCard'.
  // error • The method '_getTierBorderColor' isn't defined for the type 'ConfigCard'.

  // We need to move those helpers inside ConfigCard since the errors were originally there.
  // Wait, let's see where they were called. In ConfigCard it says `_getPingColor(config.currentPing)`
  // Wait, no. The class is ConfigCard. I moved them outside the classes. Let's make them top-level functions instead of private methods if they are used across classes.

  var newContent = content.replaceAll('_getPingColor', 'getPingColor');
  newContent = newContent.replaceAll('_getTierColor', 'getTierColor');
  newContent = newContent.replaceAll('_getTierBorderColor', 'getTierBorderColor');

  file.writeAsStringSync(newContent);
}
