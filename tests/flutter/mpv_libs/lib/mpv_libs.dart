import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

const testUrl = 'https://user-images.githubusercontent.com/28951144/229373709-603a7a89-2105-4e1b-a5a5-a6c3567c9a59.mp4';

typedef _VersionC = Int32 Function();
typedef _CreateC = Pointer<Void> Function();
typedef _SetOptionC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SetPropertyC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _ObserveC = Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>, Int32);
typedef _RequestLogC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _WaitEventC = Pointer<MpvEvent> Function(Pointer<Void>, Double);
typedef _InitC = Int32 Function(Pointer<Void>);
typedef _CommandC = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _DestroyC = Void Function(Pointer<Void>);

typedef _VersionFn = int Function();
typedef _CreateFn = Pointer<Void> Function();
typedef _SetOptionFn = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SetPropertyFn = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _ObserveFn = int Function(Pointer<Void>, int, Pointer<Utf8>, int);
typedef _RequestLogFn = int Function(Pointer<Void>, Pointer<Utf8>);
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

final class MpvEventProperty extends Struct {
  external Pointer<Utf8> name;

  @Int32()
  external int format;

  external Pointer<Void> data;
}

final class MpvEventEndFile extends Struct {
  @Int32()
  external int reason;

  @Int32()
  external int error;
}

final class MpvEventLogMessage extends Struct {
  external Pointer<Utf8> prefix;

  external Pointer<Utf8> level;

  external Pointer<Utf8> text;

  @Int32()
  external int logLevel;
}

const noEvent = 0;
const shutdownEvent = 1;
const logMessageEvent = 2;
const startFileEvent = 6;
const endFileEvent = 7;
const playbackRestartEvent = 21;
const propertyChangeEvent = 22;
const flagFormat = 3;
const doubleFormat = 5;

const eventNames = <int, String>{
  0: 'none',
  1: 'shutdown',
  2: 'log-message',
  6: 'start-file',
  7: 'end-file',
  8: 'file-loaded',
  21: 'playback-restart',
  22: 'property-change',
};

const endFileReasons = <int, String>{
  0: 'eof',
  2: 'stop',
  3: 'quit',
  4: 'error',
  5: 'redirect',
};

final List<String> eventTrace = [];

late final _VersionFn _version;
late final _CreateFn _create;
late final _SetOptionFn _setOption;
late final _SetPropertyFn _setProperty;
late final _ObserveFn _observe;
late final _RequestLogFn _requestLog;
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
  _observe = lib.lookupFunction<_ObserveC, _ObserveFn>('mpv_observe_property');
  _requestLog = lib.lookupFunction<_RequestLogC, _RequestLogFn>('mpv_request_log_messages');
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

int observeProperty(Pointer<Void> handle, String name, int format) {
  final n = name.toNativeUtf8();
  final code = _observe(handle, 0, n, format);
  calloc.free(n);
  return code;
}

int requestLogMessages(Pointer<Void> handle, String minLevel) {
  final l = minLevel.toNativeUtf8();
  final code = _requestLog(handle, l);
  calloc.free(l);
  return code;
}

String formatPropValue(int format, Pointer<Void> data) {
  if (format == flagFormat) {
    return (data.cast<Int32>().value != 0).toString();
  }
  if (format == doubleFormat) {
    return data.cast<Double>().value.toString();
  }
  return data.address.toRadixString(16);
}

String? describeEvent(MpvEvent event) {
  if (event.id == propertyChangeEvent && event.data != nullptr) {
    final prop = event.data.cast<MpvEventProperty>().ref;
    return 'prop:${prop.name.toDartString()}=${formatPropValue(prop.format, prop.data)}';
  }
  if (event.id == endFileEvent && event.data != nullptr) {
    final end = event.data.cast<MpvEventEndFile>().ref;
    final reason = endFileReasons[end.reason] ?? end.reason;
    if (end.reason == 4) {
      return 'event:end-file:$reason:${end.error}';
    }
    return 'event:end-file:$reason';
  }
  if (event.id == logMessageEvent && event.data != nullptr) {
    final log = event.data.cast<MpvEventLogMessage>().ref;
    if (log.logLevel <= 30) {
      return 'log:${log.prefix.toDartString()}:${log.text.toDartString().trim()}';
    }
    return null;
  }
  return 'event:${eventNames[event.id] ?? event.id}';
}

bool waitForTrace(
  Pointer<Void> handle,
  bool Function() done,
  int timeoutSeconds, {
  void Function(String entry)? onEvent,
}) {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
  while (DateTime.now().isBefore(deadline)) {
    final event = _waitEvent(handle, 0.5).ref;
    if (event.id == shutdownEvent) {
      eventTrace.add('event:shutdown');
      return false;
    }
    if (event.id != noEvent) {
      final described = describeEvent(event);
      if (described != null) {
        eventTrace.add(described);
        onEvent?.call(described);
      }
    }
    if (done()) {
      return true;
    }
  }
  return false;
}

bool traceHas(String entry) {
  return eventTrace.contains(entry);
}

bool traceHasPrefix(String prefix) {
  return eventTrace.any((entry) => entry.startsWith(prefix));
}

bool traceHasPropGreaterThan(String name, double value) {
  final prefix = 'prop:$name=';
  for (final entry in eventTrace) {
    if (entry.startsWith(prefix)) {
      final parsed = double.tryParse(entry.substring(prefix.length));
      if (parsed != null && parsed > value) {
        return true;
      }
    }
  }
  return false;
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
