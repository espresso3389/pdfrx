# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "pdfrx")
project(${PROJECT_NAME} LANGUAGES CXX)

# Invoke the build for native code shared with the other target platforms.
# This can be changed to accommodate different builds.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

set(PDFIUM_RELEASE chromium%2F6555)
set(PDFIUM_DIR ${CMAKE_BINARY_DIR}/pdfium)
set(PDFIUM_RELEASE_DIR ${PDFIUM_DIR}/${PDFIUM_RELEASE})

file(MAKE_DIRECTORY ${PDFIUM_RELEASE_DIR})

set(PDFIUM_PLATFORM "win")
set(PDFIUM_LIB_FILENAME "pdfium.dll")
set(PDFIUM_LIB_DIR "bin")
set(PDFIUM_WIN_ABI "x64")

set(PDFIUM_ARCHIVE_NAME pdfium-${PDFIUM_PLATFORM}-${PDFIUM_WIN_ABI})
set(PDFIUM_SRC_LIB_FILENAME ${PDFIUM_RELEASE_DIR}/${PDFIUM_LIB_DIR}/${PDFIUM_LIB_FILENAME})

set(PDFIUM_LIBS_DIR ${CMAKE_BINARY_DIR}/.lib/${PDFIUM_RELEASE})
set(PDFIUM_LIBS_ARCH_DIR ${PDFIUM_LIBS_DIR}/${PDFIUM_WIN_ABI})
set(PDFIUM_DEST_LIB_FILENAME ${PDFIUM_LIBS_ARCH_DIR}/${PDFIUM_LIB_FILENAME})

set(PDFIUM_LATEST_DIR ${CMAKE_BINARY_DIR}/.lib/latest)
set(PDFIUM_LATEST_LIBS_ARCH_DIR ${PDFIUM_LATEST_DIR}/${PDFIUM_WIN_ABI})
set(PDFIUM_LATEST_LIB_FILENAME ${PDFIUM_LATEST_LIBS_ARCH_DIR}/${PDFIUM_LIB_FILENAME})

if(NOT EXISTS ${PDFIUM_SRC_LIB_FILENAME})
    message(STATUS "Download precompiled pdfium...")
    file(DOWNLOAD https://github.com/bblanchon/pdfium-binaries/releases/download/${PDFIUM_RELEASE}/${PDFIUM_ARCHIVE_NAME}.tgz ${PDFIUM_RELEASE_DIR}/${PDFIUM_ARCHIVE_NAME}.tgz)
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E tar zxf ${PDFIUM_RELEASE_DIR}/${PDFIUM_ARCHIVE_NAME}.tgz
        WORKING_DIRECTORY ${PDFIUM_RELEASE_DIR}
        ERROR_QUIET
    )
    if(STATUS AND NOT STATUS EQUAL 0)
        message(FATAL_ERROR "Could not obtain pdfium binary for ${PDFIUM_WIN_ABI}")
    endif()
else()
    message(STATUS "Use existing precompiled pdfium." )
endif()

if (NOT EXISTS ${PDFIUM_DEST_LIB_FILENAME})
    file(MAKE_DIRECTORY ${PDFIUM_LIBS_ARCH_DIR})
    file(COPY ${PDFIUM_SRC_LIB_FILENAME} DESTINATION ${PDFIUM_LIBS_ARCH_DIR})
endif()

# also copy header files for dev use
if (NOT EXISTS ${PDFIUM_LIBS_DIR}/include)
    file(COPY ${PDFIUM_RELEASE_DIR}/include DESTINATION ${PDFIUM_LIBS_DIR})
endif()

file(REMOVE ${PDFIUM_LATEST_DIR})
file(CREATE_LINK ${PDFIUM_LIBS_DIR} ${PDFIUM_LATEST_DIR} SYMBOLIC)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(pdfrx_bundled_libraries
  # Defined in ../src/CMakeLists.txt.
  # This can be changed to accommodate different builds.
  $<TARGET_FILE:pdfrx>
  ${PDFIUM_LATEST_LIB_FILENAME}
  PARENT_SCOPE
)

target_include_directories(pdfrx PRIVATE ${PDFIUM_LATEST_DIR}/include)
