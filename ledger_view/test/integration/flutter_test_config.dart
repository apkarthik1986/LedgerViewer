import 'dart:async';

/// Minimal test configuration for integration tests that create real HTTP
/// connections.  Unlike the parent flutter_test_config.dart, this file does
/// NOT call TestWidgetsFlutterBinding.ensureInitialized(), which would
/// intercept all dart:io HttpClient calls and return HTTP 400.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
