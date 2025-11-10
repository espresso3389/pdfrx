# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "pdfium_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

set(PDFIUM_RELEASE chromium%2F7506)
set(PDFIUM_DIR ${CMAKE_BINARY_DIR}/pdfium)
set(PDFIUM_RELEASE_DIR ${PDFIUM_DIR}/${PDFIUM_RELEASE})

file(MAKE_DIRECTORY ${PDFIUM_RELEASE_DIR})

# Determine target processor name for Windows
IF(CMAKE_SYSTEM_PROCESSOR STREQUAL "AMD64")
    SET(CPU_NAME "x64")
ELSEIF(CMAKE_SYSTEM_PROCESSOR STREQUAL "ARM64")
    SET(CPU_NAME "arm64")
ELSE()
    MESSAGE(FATAL_ERROR "Unsupported Windows architecture \"${CMAKE_SYSTEM_PROCESSOR}\". Only AMD64 and ARM64 are supported.")
ENDIF()
message( STATUS "Target Windows CPU Name: ${CPU_NAME}" )

set(PDFIUM_PLATFORM "win")
set(PDFIUM_LIB_FILENAME "pdfium.dll")
set(PDFIUM_LIB_DIR "bin")
set(PDFIUM_WIN_ABI ${CPU_NAME})

set(PDFIUM_ARCHIVE_NAME pdfium-${PDFIUM_PLATFORM}-${PDFIUM_WIN_ABI})
set(PDFIUM_SRC_LIB_FILENAME ${PDFIUM_RELEASE_DIR}/${PDFIUM_LIB_DIR}/${PDFIUM_LIB_FILENAME})

set(PDFIUM_LIBS_DIR ${CMAKE_BINARY_DIR}/.lib/${PDFIUM_RELEASE})
set(PDFIUM_LIBS_ARCH_DIR ${PDFIUM_LIBS_DIR}/${PDFIUM_WIN_ABI})
set(PDFIUM_DEST_LIB_FILENAME ${PDFIUM_LIBS_ARCH_DIR}/${PDFIUM_LIB_FILENAME})

set(PDFIUM_LATEST_DIR ${CMAKE_BINARY_DIR}/.lib/latest)
set(PDFIUM_LATEST_LIBS_ARCH_DIR ${PDFIUM_LATEST_DIR}/${PDFIUM_WIN_ABI})
set(PDFIUM_LATEST_LIB_FILENAME ${PDFIUM_LATEST_LIBS_ARCH_DIR}/${PDFIUM_LIB_FILENAME})

if(NOT EXISTS ${PDFIUM_SRC_LIB_FILENAME})
    message(STATUS "Download precompiled PDFium...")
    file(DOWNLOAD https://github.com/bblanchon/pdfium-binaries/releases/download/${PDFIUM_RELEASE}/${PDFIUM_ARCHIVE_NAME}.tgz ${PDFIUM_RELEASE_DIR}/${PDFIUM_ARCHIVE_NAME}.tgz)
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E tar zxf ${PDFIUM_RELEASE_DIR}/${PDFIUM_ARCHIVE_NAME}.tgz
        WORKING_DIRECTORY ${PDFIUM_RELEASE_DIR}
        RESULT_VARIABLE STATUS
        ERROR_QUIET
    )
    if(STATUS AND NOT STATUS EQUAL 0)
        message(FATAL_ERROR "Could not obtain PDFium binary for ${PDFIUM_WIN_ABI}: ${STATUS}")
    endif()
else()
    message(STATUS "Use existing precompiled PDFium." )
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

# Check if we can create symbolic links (requires Developer Mode on Windows)
execute_process(
    COMMAND ${CMAKE_COMMAND} -E create_symlink ${PDFIUM_LIBS_DIR} ${PDFIUM_LATEST_DIR}_test
    RESULT_VARIABLE SYMLINK_RESULT
    ERROR_QUIET
    OUTPUT_QUIET
)

if(EXISTS ${PDFIUM_LATEST_DIR}_test)
    file(REMOVE ${PDFIUM_LATEST_DIR}_test)
endif()

if(SYMLINK_RESULT EQUAL 0)
    # Developer Mode is enabled, use symbolic link
    file(CREATE_LINK ${PDFIUM_LIBS_DIR} ${PDFIUM_LATEST_DIR} SYMBOLIC)
else()
    # Developer Mode is not enabled, fail the build
    message(FATAL_ERROR "\n"
        "========================================================================\n"
        "  ERROR: Windows Developer Mode is not enabled!\n"
        "------------------------------------------------------------------------\n"
        "  The pdfium_flutter build process requires Developer Mode to create symbolic\n"
        "  links. The build cannot continue without Developer Mode enabled.\n"
        "\n"
        "  Please enable Developer Mode by following the instructions at:\n"
        "  https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development#activate-developer-mode\n"
        "\n"
        "  After enabling Developer Mode, restart your computer and run the\n"
        "  build again.\n"
        "========================================================================\n"
    )
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(pdfium_flutter_bundled_libraries
  ${PDFIUM_LATEST_LIB_FILENAME}
  PARENT_SCOPE
)
