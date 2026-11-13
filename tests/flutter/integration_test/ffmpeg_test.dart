import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpv_libs/ffmpeg_libs.dart';

const kAssetPath = 'assets/tone.mp3';
const kMinFrames = 5;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('asset audio decode: version, open, frames', (tester) async {
    ffmpegInit(ffmpegOpen());

    expect(avVersionInfo(), isNotEmpty);
    expect(avcodecVersion(), greaterThan(0));

    final dir = await Directory.systemTemp.createTemp('ffmpeg_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/tone.mp3');
    final asset = await rootBundle.load(kAssetPath);
    await file.writeAsBytes(asset.buffer.asUint8List());

    final ctxPtr = calloc<Pointer<AvFormatContext>>();
    addTearDown(() => calloc.free(ctxPtr));
    expect(avformatOpenInput(ctxPtr, file.path), 0);

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
  });
}
