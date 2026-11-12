import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_libs/mpv_libs.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('mpv playback', (tester) async {
    final code = await checkPlayback(testUrl);
    expect(code, 0);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
