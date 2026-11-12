import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

const testUrl = 'https://upload.wikimedia.org/wikipedia/commons/1/1a/Aaron_Dunn_-_Minuet_-_Notebook_for_Anna_Magdalena.ogg';

typedef _VersionC = Int32 Function();
typedef _CreateC = Pointer<Void> Function();
typedef _SetOptionC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _InitC = Int32 Function(Pointer<Void>);
typedef _CommandC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _DestroyC = Void Function(Pointer<Void>);

typedef _VersionFn = int Function();
typedef _CreateFn = Pointer<Void> Function();
typedef _SetOptionFn = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _InitFn = int Function(Pointer<Void>);
typedef _CommandFn = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _DestroyFn = void Function(Pointer<Void>);

late final _VersionFn _version;
late final _CreateFn _create;
late final _SetOptionFn _setOption;
late final _InitFn _initialize;
late final _CommandFn _command;
late final _DestroyFn _destroy;

DynamicLibrary openMpv() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libmpv.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('libmpv-2.dll');
  }
  return DynamicLibrary.open('libmpv.so.2');
}

void initMpv(DynamicLibrary lib) {
  _version = lib.lookupFunction<_VersionC, _VersionFn>('mpv_client_api_version');
  _create = lib.lookupFunction<_CreateC, _CreateFn>('mpv_create');
  _setOption = lib.lookupFunction<_SetOptionC, _SetOptionFn>('mpv_set_option_string');
  _initialize = lib.lookupFunction<_InitC, _InitFn>('mpv_initialize');
  _command = lib.lookupFunction<_CommandC, _CommandFn>('mpv_command_string');
  _destroy = lib.lookupFunction<_DestroyC, _DestroyFn>('mpv_terminate_destroy');
}

int mpvVersion() {
  return _version();
}

Pointer<Void> mpvCreate() {
  return _create();
}

int mpvInitialize(Pointer<Void> handle) {
  return _initialize(handle);
}

void mpvDestroy(Pointer<Void> handle) {
  _destroy(handle);
}

int setString(Pointer<Void> handle, String name, String value) {
  final n = name.toNativeUtf8();
  final v = value.toNativeUtf8();
  final code = _setOption(handle, n, v);
  calloc.free(n);
  calloc.free(v);
  return code;
}

int loadFile(Pointer<Void> handle, String url) {
  final args = 'loadfile $url replace'.toNativeUtf8();
  final code = _command(handle, args);
  calloc.free(args);
  return code;
}

Future<int> checkPlayback(String url) async {
  initMpv(openMpv());
  if (mpvVersion() <= 0) {
    return 1;
  }
  final handle = mpvCreate();
  if (handle == nullptr) {
    return 2;
  }
  if (setString(handle, 'vo', 'null') != 0) {
    return 3;
  }
  if (setString(handle, 'ao', 'null') != 0) {
    return 4;
  }
  if (mpvInitialize(handle) != 0) {
    return 5;
  }
  if (loadFile(handle, url) != 0) {
    return 6;
  }
  await Future<void>.delayed(const Duration(seconds: 15));
  mpvDestroy(handle);
  return 0;
}
