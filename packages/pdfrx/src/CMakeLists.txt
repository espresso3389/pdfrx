# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(pdfrx_library VERSION 0.0.1 LANGUAGES CXX)

add_library(pdfrx SHARED
  "pdfium_interop.cpp"
)

set_target_properties(pdfrx PROPERTIES
  OUTPUT_NAME "pdfrx"
)

target_compile_definitions(pdfrx PUBLIC DART_SHARED_LIB)
