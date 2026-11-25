import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_libs/mpv_libs.dart';

const kExpectedDurationSec = 15;
const kAudioDeviceList = 'audio-device-list';
const kAudioPcm = 'audio-pcm';
const kAudioFft = 'audio-fft';
const kPlotRate = '8000';
const kFftBins = 513; // 1024-sample RDFT at audio-plot-rate -> N/2+1 magnitudes
const kPcmMax = 2048;
const kPlotUserdata = 7;
const kPlotJsonUserdata = 8;

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
    expect(mpvSetOption(handle, 'audio-plot-rate', kPlotRate), 0);
    expect(mpvInitialize(handle), 0);
    expect(mpvObserveProperty(handle, 'duration', kFormatDouble), 0);
    expect(mpvObserveProperty(handle, 'time-pos', kFormatDouble), 0);
    expect(mpvObserveProperty(handle, 'pause', kFormatFlag), 0);
    expect(mpvObserveProperty(handle, kAudioDeviceList, kFormatNode), 0);
    expect(mpvObserveProperty(handle, kAudioPcm, kFormatNode, kPlotUserdata), 0);
    expect(mpvObserveProperty(handle, kAudioFft, kFormatNode, kPlotUserdata), 0);
    expect(
        mpvObserveProperty(handle, kAudioFft, kFormatString, kPlotJsonUserdata),
        0);
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
    // Fires once with the initial audio-device-list value. Building the list
    // enumerates system audio devices (ALSA hotplug on Linux); freeing those
    // system-allocated strings with the wrong allocator crashes the process.
    final onAudioDeviceList = expectAsync1((String name) {
      expect(name, kAudioDeviceList);
    }, count: 1);
    // Fires on every non-silent audio-pcm update (resampled mono samples).
    final onPcm = expectAsync1(
      (int count) {
        expect(count, inInclusiveRange(1, kPcmMax));
      },
      count: 1,
      max: -1,
    );
    // Fires on every non-zero audio-fft update (magnitudes, same stream).
    final onFft = expectAsync1(
      (int count) {
        expect(count, kFftBins);
      },
      count: 1,
      max: -1,
    );
    // Fires once per stream when fresh data arrives after resubscribing.
    final onPcmBack = expectAsync0(() {}, count: 1);
    final onFftBack = expectAsync0(() {}, count: 1);
    // Fires once when the fft stream also arrives as a JSON string.
    final onJsonFft = expectAsync0(() {}, count: 1);

    bool pcmLive = false;
    bool fftLive = false;
    bool pcmBack = false;
    bool fftBack = false;
    bool jsonLive = false;
    int pcmEvents = 0;
    int fftEvents = 0;
    bool resubscribed = false;

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
        } else if (prop.format == kFormatNode && name == kAudioDeviceList) {
          print('mpv: audio-device-list received');
          onAudioDeviceList(name);
        } else if (name == kAudioPcm || name == kAudioFft) {
          final isPcm = name == kAudioPcm;
          if (prop.format == kFormatNode && prop.data.address != 0) {
            final node = prop.data.cast<MpvNode>().ref;
            if (node.format == kFormatNodeArray) {
              final list = node.u.list.ref;
              double peak = 0.0;
              for (int i = 0; i < list.num; i++) {
                final v = (list.values + i).ref.u.double_;
                if (v.isNaN) {
                  fail('mpv: $name contains NaN at [$i]');
                }
                peak = peak > v.abs() ? peak : v.abs();
              }
              print('mpv: $name count=${list.num} peak=$peak');
              if (peak > 0) {
                if (isPcm) {
                  pcmLive = true;
                  pcmEvents++;
                  onPcm(list.num);
                  if (resubscribed && !pcmBack) {
                    pcmBack = true;
                    onPcmBack();
                  }
                } else {
                  fftLive = true;
                  fftEvents++;
                  onFft(list.num);
                  if (resubscribed && !fftBack) {
                    fftBack = true;
                    onFftBack();
                  }
                }
              }
            }
          } else if (!isPcm &&
              prop.format == kFormatString &&
              prop.data.address != 0) {
            final String raw =
                prop.data.cast<Pointer<Utf8>>().value.toDartString();
            final dynamic decoded = jsonDecode(raw);
            expect(decoded, isList);
            final List<dynamic> bins = decoded as List<dynamic>;
            expect(bins.length, kFftBins);
            if (!jsonLive) {
              print('mpv: $name json bins=${bins.length}');
              jsonLive = true;
              onJsonFft();
            }
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

    // Wait for the first subscribed pcm/fft updates, plus the JSON copy.
    for (int i = 0; i < 20 && !(pcmLive && fftLive && jsonLive); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(pcmLive, isTrue, reason: 'no audio-pcm update received');
    expect(fftLive, isTrue, reason: 'no audio-fft update received');
    expect(jsonLive, isTrue, reason: 'no audio-fft JSON update received');

    // Unsubscribe: no more pcm/fft events must arrive while the rate stays
    // configured, proving the tap idles when nobody listens.
    expect(mpvUnobserveProperty(handle, kPlotUserdata), 2);
    final quietPcm = pcmEvents;
    final quietFft = fftEvents;
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(pcmEvents, quietPcm, reason: 'audio-pcm fired after unobserve');
    expect(fftEvents, quietFft, reason: 'audio-fft fired after unobserve');

    // Resubscribe: fresh updates must resume on the same stream.
    expect(mpvObserveProperty(handle, kAudioPcm, kFormatNode, kPlotUserdata), 0);
    expect(mpvObserveProperty(handle, kAudioFft, kFormatNode, kPlotUserdata), 0);
    resubscribed = true;
    for (int i = 0; i < 20 && !(pcmBack && fftBack); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(pcmBack, isTrue, reason: 'no audio-pcm update after resubscribe');
    expect(fftBack, isTrue, reason: 'no audio-fft update after resubscribe');

    expect(mpvSetProperty(handle, 'pause', 'yes'), 0);

    await Future<void>.delayed(const Duration(seconds: 2));

    expect(mpvSetProperty(handle, 'pause', 'no'), 0);

    await Future<void>.delayed(const Duration(seconds: 2));

    timer.cancel();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
