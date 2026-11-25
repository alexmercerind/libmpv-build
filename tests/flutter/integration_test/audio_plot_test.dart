import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_libs/mpv_libs.dart';

const String kAudioPcm = 'audio-pcm';
const String kAudioFft = 'audio-fft';
const String kPlotRate = '8000';
const int kFftBins = 513; // 1024-sample RDFT at audio-plot-rate -> N/2+1
const int kPcmMax = 2048;
const int kPlotUserdata = 7;
const int kPlotJsonUserdata = 8;

// ffprobe format duration of the clip: 15.046531 s.
const String kTestUrl = 'https://user-images.githubusercontent.com/28951144/229373709-603a7a89-2105-4e1b-a5a5-a6c3567c9a59.mp4';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('audio plot: pcm/fft subscribe, unsubscribe, resubscribe',
      (tester) async {
    mpvInit(mpvOpen());

    final handle = mpvCreate();
    addTearDown(() => mpvDestroy(handle));

    expect(mpvSetOption(handle, 'vo', 'null'), 0);
    expect(mpvSetOption(handle, 'ao', 'null'), 0);
    expect(mpvSetOption(handle, 'audio-plot-rate', kPlotRate), 0);
    expect(mpvInitialize(handle), 0);
    expect(mpvObserveProperty(handle, kAudioPcm, kFormatNode, kPlotUserdata),
        0);
    expect(mpvObserveProperty(handle, kAudioFft, kFormatNode, kPlotUserdata),
        0);
    expect(
        mpvObserveProperty(handle, kAudioFft, kFormatString, kPlotJsonUserdata),
        0);
    expect(mpvCommand(handle, 'loadfile $kTestUrl replace'), 0);

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
    // Fires once when the fft stream also arrives as a JSON string.
    final onJsonFft = expectAsync0(() {}, count: 1);
    // Fires once per stream when fresh data arrives after resubscribing.
    final onPcmBack = expectAsync0(() {}, count: 1);
    final onFftBack = expectAsync0(() {}, count: 1);

    bool pcmLive = false;
    bool fftLive = false;
    bool jsonLive = false;
    bool pcmBack = false;
    bool fftBack = false;
    int pcmEvents = 0;
    int fftEvents = 0;
    bool resubscribed = false;

    final timer = Timer.periodic(Duration.zero, (_) {
      final eventRef = mpvWaitEvent(handle, 0);
      final event = eventRef.ref;
      if (event.id == kEventPropertyChange && event.data.address != 0) {
        final prop = event.data.cast<MpvEventProperty>().ref;
        final String name = prop.name.toDartString();
        if (name == kAudioPcm || name == kAudioFft) {
          final bool isPcm = name == kAudioPcm;
          if (prop.format == kFormatNode && prop.data.address != 0) {
            final node = prop.data.cast<MpvNode>().ref;
            if (node.format == kFormatNodeArray) {
              final list = node.u.list.ref;
              double peak = 0.0;
              for (int i = 0; i < list.num; i++) {
                final double v = (list.values + i).ref.u.double_;
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
        }
      }
    });

    // The pump must stop even when an expect above throws; otherwise the
    // periodic timer keeps the test process alive and the CI step hangs.
    try {
      // Wait for the first subscribed pcm/fft updates, plus the JSON copy.
      for (int i = 0; i < 20 && !(pcmLive && fftLive && jsonLive); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      expect(pcmLive, isTrue, reason: 'no audio-pcm update received');
      expect(fftLive, isTrue, reason: 'no audio-fft update received');
      expect(jsonLive, isTrue, reason: 'no audio-fft JSON update received');

      // Unsubscribe: no more pcm/fft node events must arrive while the rate
      // stays configured, proving the tap idles when nobody listens. The JSON
      // observation (separate userdata) keeps flowing, proving mpv_unobserve_property
      // is selective.
      expect(mpvUnobserveProperty(handle, kPlotUserdata), 2);
      final int quietPcm = pcmEvents;
      final int quietFft = fftEvents;
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(pcmEvents, quietPcm, reason: 'audio-pcm fired after unobserve');
      expect(fftEvents, quietFft, reason: 'audio-fft fired after unobserve');

      // Resubscribe: fresh updates must resume on the same stream.
      expect(mpvObserveProperty(handle, kAudioPcm, kFormatNode, kPlotUserdata),
          0);
      expect(mpvObserveProperty(handle, kAudioFft, kFormatNode, kPlotUserdata),
          0);
      resubscribed = true;
      for (int i = 0; i < 20 && !(pcmBack && fftBack); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      expect(pcmBack, isTrue, reason: 'no audio-pcm update after resubscribe');
      expect(fftBack, isTrue, reason: 'no audio-fft update after resubscribe');
    } finally {
      timer.cancel();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
