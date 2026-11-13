import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const kMediaTypeAudio = 1;

typedef _AvVersionInfoC = Pointer<Utf8> Function();
typedef _AvVersionInfoFn = Pointer<Utf8> Function();
typedef _AvcodecVersionC = Uint32 Function();
typedef _AvcodecVersionFn = int Function();
typedef _AvDictSetC = Int32 Function(Pointer<Pointer<Void>>, Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _AvDictSetFn = int Function(Pointer<Pointer<Void>>, Pointer<Utf8>, Pointer<Utf8>, int);
typedef _AvDictFreeC = Void Function(Pointer<Pointer<Void>>);
typedef _AvDictFreeFn = void Function(Pointer<Pointer<Void>>);
typedef _AvformatOpenInputC = Int32 Function(Pointer<Pointer<AvFormatContext>>, Pointer<Utf8>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _AvformatOpenInputFn = int Function(Pointer<Pointer<AvFormatContext>>, Pointer<Utf8>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _AvformatFindStreamInfoC = Int32 Function(Pointer<AvFormatContext>, Pointer<Void>);
typedef _AvformatFindStreamInfoFn = int Function(Pointer<AvFormatContext>, Pointer<Void>);
typedef _AvFindBestStreamC = Int32 Function(Pointer<AvFormatContext>, Int32, Int32, Int32, Pointer<Pointer<Void>>, Int32);
typedef _AvFindBestStreamFn = int Function(Pointer<AvFormatContext>, int, int, int, Pointer<Pointer<Void>>, int);
typedef _AvcodecAllocContext3C = Pointer<Void> Function(Pointer<Void>);
typedef _AvcodecAllocContext3Fn = Pointer<Void> Function(Pointer<Void>);
typedef _AvcodecParametersToContextC = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _AvcodecParametersToContextFn = int Function(Pointer<Void>, Pointer<Void>);
typedef _AvcodecFreeContextC = Void Function(Pointer<Pointer<Void>>);
typedef _AvcodecFreeContextFn = void Function(Pointer<Pointer<Void>>);
typedef _AvcodecOpen2C = Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _AvcodecOpen2Fn = int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _AvPacketAllocC = Pointer<AvPacket> Function();
typedef _AvPacketAllocFn = Pointer<AvPacket> Function();
typedef _AvPacketFreeC = Void Function(Pointer<Pointer<AvPacket>>);
typedef _AvPacketFreeFn = void Function(Pointer<Pointer<AvPacket>>);
typedef _AvFrameAllocC = Pointer<AvFrame> Function();
typedef _AvFrameAllocFn = Pointer<AvFrame> Function();
typedef _AvFrameFreeC = Void Function(Pointer<Pointer<AvFrame>>);
typedef _AvFrameFreeFn = void Function(Pointer<Pointer<AvFrame>>);
typedef _AvReadFrameC = Int32 Function(Pointer<AvFormatContext>, Pointer<AvPacket>);
typedef _AvReadFrameFn = int Function(Pointer<AvFormatContext>, Pointer<AvPacket>);
typedef _AvPacketUnrefC = Void Function(Pointer<AvPacket>);
typedef _AvPacketUnrefFn = void Function(Pointer<AvPacket>);
typedef _AvcodecSendPacketC = Int32 Function(Pointer<Void>, Pointer<AvPacket>);
typedef _AvcodecSendPacketFn = int Function(Pointer<Void>, Pointer<AvPacket>);
typedef _AvcodecReceiveFrameC = Int32 Function(Pointer<Void>, Pointer<AvFrame>);
typedef _AvcodecReceiveFrameFn = int Function(Pointer<Void>, Pointer<AvFrame>);
typedef _AvformatCloseInputC = Void Function(Pointer<Pointer<AvFormatContext>>);
typedef _AvformatCloseInputFn = void Function(Pointer<Pointer<AvFormatContext>>);

// Prefix of AVFormatContext up to the stream list.
// The full struct is larger; only these leading fields are mapped.
final class AvFormatContext extends Struct {
  external Pointer<Void> avClass;

  external Pointer<Void> iformat;

  external Pointer<Void> oformat;

  external Pointer<Void> privData;

  external Pointer<Void> pb;

  @Int32()
  external int ctxFlags;

  @UnsignedInt()
  external int nbStreams;

  external Pointer<Pointer<AvStream>> streams;
}

// Prefix of AVStream up to the codec parameters.
// The full struct is larger; only these leading fields are mapped.
final class AvStream extends Struct {
  external Pointer<Void> avClass;

  @Int32()
  external int index;

  @Int32()
  external int id;

  external Pointer<Void> codecpar;
}

// Prefix of AVPacket up to the stream index.
// The full struct is larger; only these leading fields are mapped.
final class AvPacket extends Struct {
  external Pointer<Void> buf;

  @Int64()
  external int pts;

  @Int64()
  external int dts;

  external Pointer<Uint8> data;

  @Int32()
  external int size;

  @Int32()
  external int streamIndex;
}

// Prefix of AVFrame up to the audio fields the test reads.
// The full struct is larger; only these leading fields are mapped.
final class AvFrame extends Struct {
  @Array(8)
  external Array<Pointer<Uint8>> data;

  @Array(8)
  external Array<Int32> linesize;

  external Pointer<Pointer<Uint8>> extendedData;

  @Int32()
  external int width;

  @Int32()
  external int height;

  @Int32()
  external int nbSamples;
}

late final _AvVersionInfoFn _avVersionInfo;
late final _AvcodecVersionFn _avcodecVersion;
late final _AvDictSetFn _avDictSet;
late final _AvDictFreeFn _avDictFree;
late final _AvformatOpenInputFn _avformatOpenInput;
late final _AvformatFindStreamInfoFn _avformatFindStreamInfo;
late final _AvFindBestStreamFn _avFindBestStream;
late final _AvcodecAllocContext3Fn _avcodecAllocContext3;
late final _AvcodecParametersToContextFn _avcodecParametersToContext;
late final _AvcodecFreeContextFn _avcodecFreeContext;
late final _AvcodecOpen2Fn _avcodecOpen2;
late final _AvPacketAllocFn _avPacketAlloc;
late final _AvPacketFreeFn _avPacketFree;
late final _AvFrameAllocFn _avFrameAlloc;
late final _AvFrameFreeFn _avFrameFree;
late final _AvReadFrameFn _avReadFrame;
late final _AvPacketUnrefFn _avPacketUnref;
late final _AvcodecSendPacketFn _avcodecSendPacket;
late final _AvcodecReceiveFrameFn _avcodecReceiveFrame;
late final _AvformatCloseInputFn _avformatCloseInput;

DynamicLibrary ffmpegOpen() {
  if (Platform.isAndroid) return DynamicLibrary.open('libmpv.so');
  if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
  if (Platform.isWindows) return DynamicLibrary.open('libmpv-2.dll');
  return DynamicLibrary.open('libmpv.so.2');
}

void ffmpegInit(DynamicLibrary lib) {
  _avVersionInfo = lib.lookupFunction<_AvVersionInfoC, _AvVersionInfoFn>('av_version_info');
  _avcodecVersion = lib.lookupFunction<_AvcodecVersionC, _AvcodecVersionFn>('avcodec_version');
  _avDictSet = lib.lookupFunction<_AvDictSetC, _AvDictSetFn>('av_dict_set');
  _avDictFree = lib.lookupFunction<_AvDictFreeC, _AvDictFreeFn>('av_dict_free');
  _avformatOpenInput = lib.lookupFunction<_AvformatOpenInputC, _AvformatOpenInputFn>('avformat_open_input');
  _avformatFindStreamInfo = lib.lookupFunction<_AvformatFindStreamInfoC, _AvformatFindStreamInfoFn>('avformat_find_stream_info');
  _avFindBestStream = lib.lookupFunction<_AvFindBestStreamC, _AvFindBestStreamFn>('av_find_best_stream');
  _avcodecAllocContext3 = lib.lookupFunction<_AvcodecAllocContext3C, _AvcodecAllocContext3Fn>('avcodec_alloc_context3');
  _avcodecParametersToContext = lib.lookupFunction<_AvcodecParametersToContextC, _AvcodecParametersToContextFn>('avcodec_parameters_to_context');
  _avcodecFreeContext = lib.lookupFunction<_AvcodecFreeContextC, _AvcodecFreeContextFn>('avcodec_free_context');
  _avcodecOpen2 = lib.lookupFunction<_AvcodecOpen2C, _AvcodecOpen2Fn>('avcodec_open2');
  _avPacketAlloc = lib.lookupFunction<_AvPacketAllocC, _AvPacketAllocFn>('av_packet_alloc');
  _avPacketFree = lib.lookupFunction<_AvPacketFreeC, _AvPacketFreeFn>('av_packet_free');
  _avFrameAlloc = lib.lookupFunction<_AvFrameAllocC, _AvFrameAllocFn>('av_frame_alloc');
  _avFrameFree = lib.lookupFunction<_AvFrameFreeC, _AvFrameFreeFn>('av_frame_free');
  _avReadFrame = lib.lookupFunction<_AvReadFrameC, _AvReadFrameFn>('av_read_frame');
  _avPacketUnref = lib.lookupFunction<_AvPacketUnrefC, _AvPacketUnrefFn>('av_packet_unref');
  _avcodecSendPacket = lib.lookupFunction<_AvcodecSendPacketC, _AvcodecSendPacketFn>('avcodec_send_packet');
  _avcodecReceiveFrame = lib.lookupFunction<_AvcodecReceiveFrameC, _AvcodecReceiveFrameFn>('avcodec_receive_frame');
  _avformatCloseInput = lib.lookupFunction<_AvformatCloseInputC, _AvformatCloseInputFn>('avformat_close_input');
}

String avVersionInfo() {
  return _avVersionInfo().toDartString();
}

int avcodecVersion() {
  return _avcodecVersion();
}

int avDictSet(Pointer<Pointer<Void>> dict, String key, String value) {
  final k = key.toNativeUtf8();
  final v = value.toNativeUtf8();
  final code = _avDictSet(dict, k, v, 0);
  calloc.free(k);
  calloc.free(v);
  return code;
}

void avDictFree(Pointer<Pointer<Void>> dict) {
  _avDictFree(dict);
}

int avformatOpenInput(Pointer<Pointer<AvFormatContext>> handle, String url, Pointer<Pointer<Void>> options) {
  final u = url.toNativeUtf8();
  final code = _avformatOpenInput(handle, u, nullptr, options);
  calloc.free(u);
  return code;
}

int avformatFindStreamInfo(Pointer<AvFormatContext> handle) {
  return _avformatFindStreamInfo(handle, nullptr);
}

int avFindBestStream(Pointer<AvFormatContext> handle, Pointer<Pointer<Void>> decoder) {
  return _avFindBestStream(handle, kMediaTypeAudio, -1, -1, decoder, 0);
}

Pointer<Void> avcodecAllocContext3(Pointer<Void> codec) {
  return _avcodecAllocContext3(codec);
}

int avcodecParametersToContext(Pointer<Void> handle, Pointer<Void> params) {
  return _avcodecParametersToContext(handle, params);
}

void avcodecFreeContext(Pointer<Void> handle) {
  final h = calloc<Pointer<Void>>()..value = handle;
  _avcodecFreeContext(h);
  calloc.free(h);
}

int avcodecOpen2(Pointer<Void> handle, Pointer<Void> codec) {
  return _avcodecOpen2(handle, codec, nullptr);
}

Pointer<AvPacket> avPacketAlloc() {
  return _avPacketAlloc();
}

void avPacketFree(Pointer<AvPacket> packet) {
  final p = calloc<Pointer<AvPacket>>()..value = packet;
  _avPacketFree(p);
  calloc.free(p);
}

Pointer<AvFrame> avFrameAlloc() {
  return _avFrameAlloc();
}

void avFrameFree(Pointer<AvFrame> frame) {
  final f = calloc<Pointer<AvFrame>>()..value = frame;
  _avFrameFree(f);
  calloc.free(f);
}

int avReadFrame(Pointer<AvFormatContext> handle, Pointer<AvPacket> packet) {
  return _avReadFrame(handle, packet);
}

void avPacketUnref(Pointer<AvPacket> packet) {
  return _avPacketUnref(packet);
}

int avcodecSendPacket(Pointer<Void> handle, Pointer<AvPacket> packet) {
  return _avcodecSendPacket(handle, packet);
}

int avcodecReceiveFrame(Pointer<Void> handle, Pointer<AvFrame> frame) {
  return _avcodecReceiveFrame(handle, frame);
}

void avformatCloseInput(Pointer<AvFormatContext> handle) {
  final h = calloc<Pointer<AvFormatContext>>()..value = handle;
  _avformatCloseInput(h);
  calloc.free(h);
}
