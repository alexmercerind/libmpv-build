import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_libs/ffmpeg_libs.dart';

const kTestUrl = 'https://user-images.githubusercontent.com/28951144/229373709-603a7a89-2105-4e1b-a5a6-c3567c9a59.mp4';
const kMinFrames = 5;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('url audio decode: version, open, frames', (tester) async {
    ffmpegInit(ffmpegOpen());

    expect(avVersionInfo(), isNotEmpty);
    expect(avcodecVersion(), greaterThan(0));

    final ctxPtr = calloc<Pointer<AvFormatContext>>();
    addTearDown(() => calloc.free(ctxPtr));

    // Same user agent mpv sends; the default Lavf agent is refused the clip.
    final optionsPtr = calloc<Pointer<Void>>();
    addTearDown(() => calloc.free(optionsPtr));
    expect(avDictSet(optionsPtr, 'user_agent', 'libmpv'), 0);
    expect(avformatOpenInput(ctxPtr, kTestUrl, optionsPtr), 0);
    avDictFree(optionsPtr);

    final fmt = ctxPtr.value;
    expect(fmt, isNot(nullptr));
    addTearDown(() => avformatCloseInput(fmt));

    expect(avformatFindStreamInfo(fmt), greaterThanOrEqualTo(0));

    final decoderPtr = calloc<Pointer<Void>>();
    addTearDown(() => calloc.free(decoderPtr));
    final streamIndex = avFindBestStream(fmt, decoderPtr);
    expect(streamIndex, greaterThanOrEqualTo(0));

    final codec = decoderPtr.value;
    expect(codec, isNot(nullptr));

    final handle = avcodecAllocContext3(codec);
    expect(handle, isNot(nullptr));
    addTearDown(() => avcodecFreeContext(handle));

    final stream = fmt.ref.streams[streamIndex];
    expect(avcodecParametersToContext(handle, stream.ref.codecpar), 0);
    expect(avcodecOpen2(handle, codec), 0);

    final packet = avPacketAlloc();
    expect(packet, isNot(nullptr));
    addTearDown(() => avPacketFree(packet));

    final frame = avFrameAlloc();
    expect(frame, isNot(nullptr));
    addTearDown(() => avFrameFree(frame));

    int frames = 0;
    int samples = 0;
    while (frames < kMinFrames && avReadFrame(fmt, packet) == 0) {
      if (packet.ref.streamIndex == streamIndex) {
        if (avcodecSendPacket(handle, packet) == 0) {
          while (frames < kMinFrames && avcodecReceiveFrame(handle, frame) == 0) {
            frames++;
            samples += frame.ref.nbSamples;
            print('ffmpeg: frame=$frames nbSamples=${frame.ref.nbSamples}');
          }
        }
      }
      avPacketUnref(packet);
    }
    expect(frames, kMinFrames);
    expect(samples, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
