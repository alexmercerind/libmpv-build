import 'package:mpv_libs/mpv_libs.dart';

// Exercises the exact Dart load path (DynamicLibrary.open -> dlopen).
// Run with MIMALLOC_VERBOSE=1 MIMALLOC_SHOW_STATS=1 in CI: the init logs
// and final stats table prove mimalloc served the mpv/ffmpeg allocations.
void main() {
  final lib = mpvOpen();
  mpvInit(lib);
  final handle = mpvCreate();
  if (handle.address == 0) {
    throw StateError('mpv_create failed');
  }
  mpvDestroy(handle);
  print('dart mimalloc check ok');
}
