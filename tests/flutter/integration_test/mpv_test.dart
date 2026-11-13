import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_libs/mpv_libs.dart';

const kExpectedDurationSec = 15;

// ffprobe format duration of the clip: 15.046531 s.
const kTestUrl = 'https://user-images.githubusercontent.com/28951144/229373709-603a7a89-2105-4e1b-a5a5-a6c3567c9a59.mp4';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('url playback: duration, position, pause', (tester) async {
    mpvInit(mpvOpen());

    final handle = mpvCreate();
    addTearDown(() => mpvDestroy(handle));

    expect(mpvSetOption(handle, 'vo', 'null'), 0);
    expect(mpvSetOption(handle, 'ao', 'null'), 0);
    expect(mpvInitialize(handle), 0);
    expect(mpvObserveProperty(handle, 'duration', kFormatDouble), 0);
    expect(mpvObserveProperty(handle, 'time-pos', kFormatDouble), 0);
    expect(mpvObserveProperty(handle, 'pause', kFormatFlag), 0);
    expect(mpvCommand(handle, 'loadfile $kTestUrl replace'), 0);

    // Fires once when playback starts.
    final onRestart = expectAsync0(() {}, count: 1);
    // Fires once when the file reports a positive duration.
    final onDuration = expectAsync1((int secs) {
      expect(secs, kExpectedDurationSec);
    }, count: 1);
    // Fires on every positive time-pos update.
    final onPosition = expectAsync1(
      (int secs) {
        expect(secs, greaterThan(0));
      },
      count: 1,
      max: -1,
    );
    // Fires once when pause=yes.
    final onPauseTrue = expectAsync1((bool isPaused) {
      expect(isPaused, isTrue);
    }, count: 1);
    // Fires on the initial loadfile and again on pause=no.
    final onPauseFalse = expectAsync1((bool isPaused) {
      expect(isPaused, isFalse);
    }, count: 2);

    final timer = Timer.periodic(Duration.zero, (_) {
      final eventRef = mpvWaitEvent(handle, 0);
      final event = eventRef.ref;
      if (event.id == kEventPlaybackRestart) {
        print('mpv: playback-restart');
        onRestart();
      } else if (event.id == kEventPropertyChange && event.data.address != 0) {
        final prop = event.data.cast<MpvEventProperty>().ref;
        final name = prop.name.toDartString();
        if (prop.format == kFormatDouble && name == 'duration') {
          final secs = prop.data.cast<Double>().value.floor();
          if (secs > 0) {
            print('mpv: duration=$secs');
            onDuration(secs);
          }
        } else if (prop.format == kFormatDouble && name == 'time-pos') {
          final secs = prop.data.cast<Double>().value.floor();
          if (secs > 0) {
            print('mpv: time-pos=$secs');
            onPosition(secs);
          }
        } else if (prop.format == kFormatFlag && name == 'pause') {
          final isPaused = prop.data.cast<Int32>().value != 0;
          print('mpv: pause=$isPaused');
          if (isPaused) {
            onPauseTrue(isPaused);
          } else {
            onPauseFalse(isPaused);
          }
        }
      }
    });

    await Future<void>.delayed(const Duration(seconds: 2));

    expect(mpvSetProperty(handle, 'pause', 'yes'), 0);

    await Future<void>.delayed(const Duration(seconds: 2));

    expect(mpvSetProperty(handle, 'pause', 'no'), 0);

    await Future<void>.delayed(const Duration(seconds: 2));

    timer.cancel();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
