#include "include/pdfrx/pdfrx_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "pdfrx_plugin.h"

void PdfrxPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  pdfrx::PdfrxPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
