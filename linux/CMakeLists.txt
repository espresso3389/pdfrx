# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "pdfrx")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PDFIUM_BINARY_RELEASE chromium%2F6124)
set(PDFIUM_DIR ${CMAKE_CURRENT_BINARY_DIR}/pdfium)
set(PDFIUM_RELEASE_DIR ${PDFIUM_DIR}/${PDFIUM_BINARY_RELEASE})

file(MAKE_DIRECTORY ${PDFIUM_RELEASE_DIR})

set(PDFIUM_PLATFORM "linux")
set(PDFIUM_LIB_FILENAME "libpdfium.so")
set(PDFIUM_LIB_DIR "lib")
set(PDFIUM_LINUX_ABI "x64")

set(PDFIUM_ARCHIVE_NAME pdfium-${PDFIUM_PLATFORM}-${PDFIUM_LINUX_ABI})
set(PDFIUM_SRC_LIB_FILENAME ${PDFIUM_RELEASE_DIR}/${PDFIUM_LIB_DIR}/${PDFIUM_LIB_FILENAME})
set(PDFIUM_SRC_IMPLIB_FILENAME ${PDFIUM_RELEASE_DIR}/lib/${PDFIUM_LIB_FILENAME}.lib)

set(PDFIUM_LIBS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/.lib)
set(PDFIUM_LIBS_ARCH_DIR ${PDFIUM_LIBS_DIR}/${PDFIUM_LINUX_ABI})
set(PDFIUM_DEST_LIB_FILENAME ${PDFIUM_LIBS_ARCH_DIR}/${PDFIUM_LIB_FILENAME})

if(NOT EXISTS ${PDFIUM_SRC_LIB_FILENAME})
    file(DOWNLOAD https://github.com/bblanchon/pdfium-binaries/releases/download/${PDFIUM_BINARY_RELEASE}/${PDFIUM_ARCHIVE_NAME}.tgz ${PDFIUM_RELEASE_DIR}/${PDFIUM_ARCHIVE_NAME}.tgz)
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E tar zxf ${PDFIUM_RELEASE_DIR}/${PDFIUM_ARCHIVE_NAME}.tgz
        WORKING_DIRECTORY ${PDFIUM_RELEASE_DIR}
        ERROR_QUIET
    )
    if(STATUS AND NOT STATUS EQUAL 0)
        message(FATAL_ERROR "Could not obtain pdfium binary for ${PDFIUM_LINUX_ABI}")
    endif()
endif()

if (NOT EXISTS ${PDFIUM_DEST_LIB_FILENAME})
    file(MAKE_DIRECTORY ${PDFIUM_LIBS_ARCH_DIR})
    file(COPY ${PDFIUM_SRC_LIB_FILENAME} DESTINATION ${PDFIUM_LIBS_ARCH_DIR})
endif()

# also copy header files for dev use
if (NOT EXISTS ${PDFIUM_LIBS_DIR}/include)
    file(COPY ${PDFIUM_RELEASE_DIR}/include DESTINATION ${PDFIUM_LIBS_DIR})
endif()

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "pdfrx_plugin")

file(GLOB_RECURSE PDFINTEROP_SOURCES "../darwin/Classes/*.cpp")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "pdfrx_plugin.cc"
  ${PDFINTEROP_SOURCES}
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include" PRIVATE ${PDFIUM_LIBS_DIR}/include)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE ${PDFIUM_DEST_LIB_FILENAME})

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(pdfrx_bundled_libraries
  ${PDFIUM_DEST_LIB_FILENAME}
  PARENT_SCOPE
)
