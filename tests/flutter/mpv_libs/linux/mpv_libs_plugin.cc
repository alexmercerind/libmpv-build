#include "include/mpv_libs/mpv_libs_plugin.h"

#include <locale.h>

FLUTTER_PLUGIN_EXPORT void mpv_libs_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  setlocale(LC_NUMERIC, "C");
}
