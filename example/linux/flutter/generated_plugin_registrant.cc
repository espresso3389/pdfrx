//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <pdfrx/pdfrx_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) pdfrx_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "PdfrxPlugin");
  pdfrx_plugin_register_with_registrar(pdfrx_registrar);
}
