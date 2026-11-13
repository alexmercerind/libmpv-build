import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const kEventPlaybackRestart = 21;
const kEventPropertyChange = 22;
const kFormatFlag = 3;
const kFormatDouble = 5;

typedef _MpvCommandC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _MpvCommandFn = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _MpvCreateC = Pointer<Void> Function();
typedef _MpvCreateFn = Pointer<Void> Function();
typedef _MpvDestroyC = Void Function(Pointer<Void>);
typedef _MpvDestroyFn = void Function(Pointer<Void>);
typedef _MpvInitializeC = Int32 Function(Pointer<Void>);
typedef _MpvInitializeFn = int Function(Pointer<Void>);
typedef _MpvObserveC = Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>, Int32);
typedef _MpvObserveFn = int Function(Pointer<Void>, int, Pointer<Utf8>, int);
typedef _MpvOptionC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _MpvOptionFn = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _MpvWaitC = Pointer<MpvEvent> Function(Pointer<Void>, Double);
typedef _MpvWaitFn = Pointer<MpvEvent> Function(Pointer<Void>, double);

final class MpvEvent extends Struct {
  @Int32()
  external int id;

  @Int32()
  external int error;

  @Uint64()
  external int replyUserdata;

  external Pointer<Void> data;
}

final class MpvEventProperty extends Struct {
  external Pointer<Utf8> name;

  @Int32()
  external int format;

  external Pointer<Void> data;
}

late final _MpvCommandFn _mpvCommand;
late final _MpvCreateFn _mpvCreate;
late final _MpvDestroyFn _mpvDestroy;
late final _MpvInitializeFn _mpvInitialize;
late final _MpvObserveFn _mpvObserve;
late final _MpvOptionFn _mpvSetOption;
late final _MpvOptionFn _mpvSetProperty;
late final _MpvWaitFn _mpvWaitEvent;

DynamicLibrary mpvOpen() {
  if (Platform.isAndroid) return DynamicLibrary.open('libmpv.so');
  if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
  if (Platform.isWindows) return DynamicLibrary.open('libmpv-2.dll');
  return DynamicLibrary.open('libmpv.so.2');
}

void mpvInit(DynamicLibrary lib) {
  _mpvCommand = lib.lookupFunction<_MpvCommandC, _MpvCommandFn>('mpv_command_string');
  _mpvCreate = lib.lookupFunction<_MpvCreateC, _MpvCreateFn>('mpv_create');
  _mpvDestroy = lib.lookupFunction<_MpvDestroyC, _MpvDestroyFn>('mpv_terminate_destroy');
  _mpvInitialize = lib.lookupFunction<_MpvInitializeC, _MpvInitializeFn>('mpv_initialize');
  _mpvObserve = lib.lookupFunction<_MpvObserveC, _MpvObserveFn>('mpv_observe_property');
  _mpvSetOption = lib.lookupFunction<_MpvOptionC, _MpvOptionFn>('mpv_set_option_string');
  _mpvSetProperty = lib.lookupFunction<_MpvOptionC, _MpvOptionFn>('mpv_set_property_string');
  _mpvWaitEvent = lib.lookupFunction<_MpvWaitC, _MpvWaitFn>('mpv_wait_event');
}

int mpvCommand(Pointer<Void> handle, String args) {
  final c = args.toNativeUtf8();
  final code = _mpvCommand(handle, c);
  calloc.free(c);
  return code;
}

Pointer<Void> mpvCreate() {
  return _mpvCreate();
}

void mpvDestroy(Pointer<Void> handle) {
  _mpvDestroy(handle);
}

int mpvInitialize(Pointer<Void> handle) {
  return _mpvInitialize(handle);
}

int mpvObserveProperty(Pointer<Void> handle, String name, int format) {
  final n = name.toNativeUtf8();
  final code = _mpvObserve(handle, 0, n, format);
  calloc.free(n);
  return code;
}

int mpvSetOption(Pointer<Void> handle, String name, String value) {
  final n = name.toNativeUtf8();
  final v = value.toNativeUtf8();
  final code = _mpvSetOption(handle, n, v);
  calloc.free(n);
  calloc.free(v);
  return code;
}

int mpvSetProperty(Pointer<Void> handle, String name, String value) {
  final n = name.toNativeUtf8();
  final v = value.toNativeUtf8();
  final code = _mpvSetProperty(handle, n, v);
  calloc.free(n);
  calloc.free(v);
  return code;
}

Pointer<MpvEvent> mpvWaitEvent(Pointer<Void> handle, [double timeout = -1]) {
  return _mpvWaitEvent(handle, timeout);
}
