import 'package:mpv_libs/mpv_libs.dart';

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
