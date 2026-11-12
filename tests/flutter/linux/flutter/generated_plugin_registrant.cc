//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <mpv_libs/mpv_libs_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) mpv_libs_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MpvLibsPlugin");
  mpv_libs_plugin_register_with_registrar(mpv_libs_registrar);
}
