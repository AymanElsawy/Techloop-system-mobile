// Dev-only entry point: the app with the Flutter Driver extension, so tools can tap through screens.
// Run: flutter run -t test_driver/app.dart
import 'package:flutter_driver/driver_extension.dart';
import 'package:techloop_mobile/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
