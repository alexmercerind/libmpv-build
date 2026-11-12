import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

const testUrl = 'https://upload.wikimedia.org/wikipedia/commons/1/1a/Aaron_Dunn_-_Minuet_-_Notebook_for_Anna_Magdalena.ogg';

typedef _VersionC = Int32 Function();
typedef _CreateC = Pointer<Void> Function();
typedef _SetOptionC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SetPropertyC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _GetPropertyC = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _WaitEventC = Pointer<MpvEvent> Function(Pointer<Void>, Double);
typedef _InitC = Int32 Function(Pointer<Void>);
typedef _CommandC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _DestroyC = Void Function(Pointer<Void>);

typedef _VersionFn = int Function();
typedef _CreateFn = Pointer<Void> Function();
typedef _SetOptionFn = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SetPropertyFn = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _GetPropertyFn = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _FreeFn = void Function(Pointer<Void>);
typedef _WaitEventFn = Pointer<MpvEvent> Function(Pointer<Void>, double);
typedef _InitFn = int Function(Pointer<Void>);
typedef _CommandFn = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _DestroyFn = void Function(Pointer<Void>);

final class MpvEvent extends Struct {
  @Int32()
  external int id;

  @Int32()
  external int error;

  @Uint64()
  external int replyUserdata;

  external Pointer<Void> data;
}

const shutdownEvent = 1;
const startFileEvent = 6;
const endFileEvent = 7;
const playbackRestartEvent = 21;

late final _VersionFn _version;
late final _CreateFn _create;
late final _SetOptionFn _setOption;
late final _SetPropertyFn _setProperty;
late final _GetPropertyFn _getProperty;
late final _FreeFn _free;
late final _WaitEventFn _waitEvent;
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
  _setProperty = lib.lookupFunction<_SetPropertyC, _SetPropertyFn>('mpv_set_property_string');
  _getProperty = lib.lookupFunction<_GetPropertyC, _GetPropertyFn>('mpv_get_property_string');
  _free = lib.lookupFunction<_FreeC, _FreeFn>('mpv_free');
  _waitEvent = lib.lookupFunction<_WaitEventC, _WaitEventFn>('mpv_wait_event');
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

int setProperty(Pointer<Void> handle, String name, String value) {
  final n = name.toNativeUtf8();
  final v = value.toNativeUtf8();
  final code = _setProperty(handle, n, v);
  calloc.free(n);
  calloc.free(v);
  return code;
}

String? getProperty(Pointer<Void> handle, String name) {
  final n = name.toNativeUtf8();
  final v = _getProperty(handle, n);
  calloc.free(n);
  if (v == nullptr) {
    return null;
  }
  final value = v.toDartString();
  _free(v.cast());
  return value;
}

int loadFile(Pointer<Void> handle, String url) {
  final args = 'loadfile $url replace'.toNativeUtf8();
  final code = _command(handle, args);
  calloc.free(args);
  return code;
}

int stopPlayback(Pointer<Void> handle) {
  final args = 'stop'.toNativeUtf8();
  final code = _command(handle, args);
  calloc.free(args);
  return code;
}

Future<String?> downloadToTemp(String url) async {
  final client = HttpClient();
  try {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != 200) {
          await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        final chunks = await response.toList();
        final file = File(
            '${Directory.systemTemp.path}/libmpv_check_${DateTime.now().millisecondsSinceEpoch}.ogg');
        await file.writeAsBytes(chunks.expand((chunk) => chunk).toList());
        return file.path;
      } catch (_) {
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    return null;
  } finally {
    client.close();
  }
}

double? waitForDuration(Pointer<Void> handle, int timeoutSeconds) {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
  while (DateTime.now().isBefore(deadline)) {
    final duration = double.tryParse(getProperty(handle, 'duration') ?? '');
    if (duration != null && duration > 0) {
      return duration;
    }
    sleep(const Duration(milliseconds: 200));
  }
  return null;
}

int waitForEvent(Pointer<Void> handle, int id, int timeoutSeconds) {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
  while (DateTime.now().isBefore(deadline)) {
    final event = _waitEvent(handle, 0.5).ref;
    if (event.id == id) {
      return 0;
    }
    if (event.id == endFileEvent || event.id == shutdownEvent) {
      return -1;
    }
  }
  return -2;
}

int waitForIdle(Pointer<Void> handle, int timeoutSeconds) {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
  while (DateTime.now().isBefore(deadline)) {
    if (getProperty(handle, 'idle-active') == 'yes') {
      return 0;
    }
    sleep(const Duration(milliseconds: 200));
  }
  return -1;
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
  if (setString(handle, 'idle', 'yes') != 0) {
    return 5;
  }
  if (mpvInitialize(handle) != 0) {
    return 6;
  }
  final path = await downloadToTemp(url);
  if (path == null) {
    return 7;
  }
  if (loadFile(handle, path) != 0) {
    return 8;
  }
  if (waitForEvent(handle, startFileEvent, 45) != 0) {
    return 9;
  }
  if (waitForEvent(handle, playbackRestartEvent, 45) != 0) {
    return 10;
  }
  if (waitForDuration(handle, 15) == null) {
    return 11;
  }
  final first = double.tryParse(getProperty(handle, 'time-pos') ?? '');
  if (first == null || first < 0) {
    return 12;
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  final second = double.tryParse(getProperty(handle, 'time-pos') ?? '');
  if (second != null && second < first) {
    return 12;
  }
  if (setProperty(handle, 'pause', 'yes') != 0 || getProperty(handle, 'pause') != 'yes') {
    return 13;
  }
  if (setProperty(handle, 'pause', 'no') != 0 || getProperty(handle, 'pause') != 'no') {
    return 14;
  }
  stopPlayback(handle);
  if (waitForIdle(handle, 10) != 0) {
    return 15;
  }
  mpvDestroy(handle);
  return 0;
}
