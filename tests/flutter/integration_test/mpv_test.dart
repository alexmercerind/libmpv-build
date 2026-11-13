import 'dart:async';
import 'dart:ffi';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_libs/mpv_libs.dart';

final class PlaybackSession {
  PlaybackSession._(this.handle, this.trace, this.events);

  final Pointer<Void> handle;
  final List<String> trace;
  final StreamQueue<String> events;
  final record = <String, void Function(String)>{};

  void expectEvent(String entry) {
    record[entry] = expectAsync1((String _) {}, count: 1);
  }

  static PlaybackSession open() {
    final trace = <String>[];
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
    final events = StreamQueue<String>(watchEvents(handle, trace));
    addTearDown(events.cancel);
    expect(loadFile(handle, testUrl), equals(0));
    return PlaybackSession._(handle, trace, events);
  }

  Future<String> next(
    bool Function(String event) matches,
    String Function() onTimeout, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TestFailure(onTimeout());
      }
      late final String event;
      try {
        event = await events.next.timeout(remaining);
      } on TimeoutException {
        throw TestFailure(onTimeout());
      }
      record[event]?.call(event);
      if (matches(event)) {
        return event;
      }
    }
  }
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
      final session = PlaybackSession.open();
      session.expectEvent('event:start-file');
      session.expectEvent('event:playback-restart');
      await session.next((event) => event == 'event:start-file', () => 'start: ${session.trace}');
      await session.next((event) => event == 'event:playback-restart', () => 'restart: ${session.trace}');
      expect(
        session.trace.indexOf('event:start-file'),
        lessThan(session.trace.indexOf('event:playback-restart')),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'reports duration',
    (tester) async {
      final session = PlaybackSession.open();
      session.expectEvent('event:start-file');
      session.expectEvent('event:playback-restart');
      await session.next((event) => event == 'event:start-file', () => 'start: ${session.trace}');
      await session.next((event) => event == 'event:playback-restart', () => 'restart: ${session.trace}');
      final event = await session.next(
        (event) {
          if (!event.startsWith('prop:duration=')) {
            return false;
          }
          final value = double.tryParse(event.split('=').last);
          return value != null && value > 0;
        },
        () => 'duration: ${session.trace}',
        timeout: const Duration(seconds: 15),
      );
      expect(double.parse(event.split('=').last), greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'advances position',
    (tester) async {
      final session = PlaybackSession.open();
      session.expectEvent('event:start-file');
      session.expectEvent('event:playback-restart');
      await session.next((event) => event == 'event:start-file', () => 'start: ${session.trace}');
      await session.next((event) => event == 'event:playback-restart', () => 'restart: ${session.trace}');
      final event = await session.next(
        (event) {
          if (!event.startsWith('prop:time-pos=')) {
            return false;
          }
          final value = double.tryParse(event.split('=').last);
          return value != null && value > 1;
        },
        () => 'time-pos: ${session.trace}',
        timeout: const Duration(seconds: 30),
      );
      expect(double.parse(event.split('=').last), greaterThan(1));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'pauses and resumes',
    (tester) async {
      final session = PlaybackSession.open();
      session.expectEvent('event:start-file');
      session.expectEvent('event:playback-restart');
      session.expectEvent('prop:pause=true');
      session.expectEvent('prop:pause=false');
      await session.next((event) => event == 'event:start-file', () => 'start: ${session.trace}');
      await session.next((event) => event == 'event:playback-restart', () => 'restart: ${session.trace}');
      expect(setProperty(session.handle, 'pause', 'yes'), equals(0));
      await session.next(
        (event) => event == 'prop:pause=true',
        () => 'pause: ${session.trace}',
        timeout: const Duration(seconds: 10),
      );
      expect(setProperty(session.handle, 'pause', 'no'), equals(0));
      await session.next(
        (event) => event == 'prop:pause=false',
        () => 'resume: ${session.trace}',
        timeout: const Duration(seconds: 10),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'stops back to idle',
    (tester) async {
      final session = PlaybackSession.open();
      session.expectEvent('event:start-file');
      session.expectEvent('event:playback-restart');
      await session.next((event) => event == 'event:start-file', () => 'start: ${session.trace}');
      await session.next((event) => event == 'event:playback-restart', () => 'restart: ${session.trace}');
      expect(stopPlayback(session.handle), equals(0));
      await session.next(
        (event) => event == 'prop:idle-active=true' || event.startsWith('event:end-file:'),
        () => 'stop: ${session.trace}',
        timeout: const Duration(seconds: 10),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
