import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_libs/mpv_libs.dart';

final record = <String, void Function(String)>{};

void expectEvent(String entry) {
  record[entry] = expectAsync1((String _) {}, count: 1);
}

void pump(Pointer<Void> handle, bool Function() done, int seconds, String reason) {
  expect(
    waitForTrace(
      handle,
      done,
      seconds,
      onEvent: (event) => record[event]?.call(event),
    ),
    isTrue,
    reason: '$reason: $eventTrace',
  );
}

Pointer<Void> startPlayback() {
  eventTrace.clear();
  record.clear();
  expectEvent('event:start-file');
  expectEvent('event:playback-restart');
  final handle = mpvCreate();
  addTearDown(() => mpvDestroy(handle));
  expect(setString(handle, 'vo', 'null'), equals(0));
  expect(setString(handle, 'ao', 'null'), equals(0));
  expect(setString(handle, 'idle', 'yes'), equals(0));
  expect(mpvInitialize(handle), equals(0));
  expect(observeProperty(handle, 'pause', flagFormat), equals(0));
  expect(observeProperty(handle, 'idle-active', flagFormat), equals(0));
  expect(observeProperty(handle, 'eof-reached', flagFormat), equals(0));
  expect(observeProperty(handle, 'duration', doubleFormat), equals(0));
  expect(observeProperty(handle, 'time-pos', doubleFormat), equals(0));
  expect(requestLogMessages(handle, 'warn'), equals(0));
  expect(loadFile(handle, testUrl), equals(0));
  pump(handle, () => traceHas('event:start-file'), 45, 'start-file');
  pump(handle, () => traceHas('event:playback-restart'), 45, 'restart');
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
      startPlayback();
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
      final handle = startPlayback();
      pump(handle, () => traceHasPropGreaterThan('duration', 0), 15, 'duration');
      final durations = eventTrace
          .where((entry) => entry.startsWith('prop:duration='))
          .map((entry) => double.parse(entry.split('=').last))
          .toList();
      expect(durations, isNotEmpty);
      expect(durations.every((value) => value >= 0), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'advances position',
    (tester) async {
      final handle = startPlayback();
      pump(handle, () => traceHasPropGreaterThan('time-pos', 1), 30, 'time-pos');
      final positions = eventTrace
          .where((entry) => entry.startsWith('prop:time-pos='))
          .map((entry) => double.parse(entry.split('=').last))
          .toList();
      expect(positions, isNotEmpty);
      expect(positions.every((value) => value >= 0), isTrue);
      expect(positions.last, greaterThan(1));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'pauses and resumes',
    (tester) async {
      final handle = startPlayback();
      expectEvent('prop:pause=true');
      expectEvent('prop:pause=false');
      expect(setProperty(handle, 'pause', 'yes'), equals(0));
      pump(handle, () => traceHas('prop:pause=true'), 10, 'pause');
      expect(setProperty(handle, 'pause', 'no'), equals(0));
      pump(handle, () => traceHas('prop:pause=false'), 10, 'resume');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'stops back to idle',
    (tester) async {
      final handle = startPlayback();
      expect(stopPlayback(handle), equals(0));
      pump(
        handle,
        () => traceHas('prop:idle-active=true') || traceHasPrefix('event:end-file:'),
        10,
        'stop',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
