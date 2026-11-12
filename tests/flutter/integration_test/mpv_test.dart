import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_libs/mpv_libs.dart';

Future<Pointer<Void>> startPlayback() async {
  eventTrace.clear();
  final handle = mpvCreate();
  addTearDown(() => mpvDestroy(handle));
  expect(handle.address, isNot(equals(0)));
  expect(setString(handle, 'vo', 'null'), equals(0));
  expect(setString(handle, 'ao', 'null'), equals(0));
  expect(setString(handle, 'idle', 'yes'), equals(0));
  expect(mpvInitialize(handle), equals(0));
  expect(observeProperty(handle, 'pause', flagFormat), equals(0));
  expect(observeProperty(handle, 'idle-active', flagFormat), equals(0));
  expect(observeProperty(handle, 'eof-reached', flagFormat), equals(0));
  expect(observeProperty(handle, 'duration', doubleFormat), equals(0));
  expect(observeProperty(handle, 'time-pos', doubleFormat), equals(0));
  expect(loadFile(handle, testUrl), equals(0));
  expect(
    waitForTrace(handle, () => traceHas('event:start-file'), 45),
    isTrue,
    reason: 'start-file: $eventTrace',
  );
  expect(
    waitForTrace(handle, () => traceHas('event:playback-restart'), 45),
    isTrue,
    reason: 'playback-restart: $eventTrace',
  );
  return handle;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    initMpv(openMpv());
    expect(mpvVersion(), greaterThan(0));
  });

  testWidgets(
    'emits start-file before playback-restart',
    (tester) async {
      await startPlayback();
      expect(
        eventTrace.indexOf('event:start-file'),
        lessThan(eventTrace.indexOf('event:playback-restart')),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'reports duration',
    (tester) async {
      final handle = await startPlayback();
      expect(
        waitForTrace(handle, () => traceHasPropGreaterThan('duration', 0), 15),
        isTrue,
        reason: 'duration: $eventTrace',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'advances position',
    (tester) async {
      final handle = await startPlayback();
      expect(
        waitForTrace(handle, () => traceHasPropGreaterThan('time-pos', 1), 30),
        isTrue,
        reason: 'time-pos: $eventTrace',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'pauses and resumes',
    (tester) async {
      final handle = await startPlayback();
      expect(setProperty(handle, 'pause', 'yes'), equals(0));
      expect(
        waitForTrace(handle, () => traceHas('prop:pause=true'), 10),
        isTrue,
        reason: 'pause: $eventTrace',
      );
      expect(setProperty(handle, 'pause', 'no'), equals(0));
      expect(
        waitForTrace(handle, () => traceHas('prop:pause=false'), 10),
        isTrue,
        reason: 'resume: $eventTrace',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'stops back to idle',
    (tester) async {
      final handle = await startPlayback();
      expect(stopPlayback(handle), equals(0));
      expect(
        waitForTrace(
          handle,
          () => traceHas('prop:idle-active=true') || traceHas('event:end-file'),
          10,
        ),
        isTrue,
        reason: 'stop: $eventTrace',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
