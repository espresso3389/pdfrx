cmake_minimum_required(VERSION 3.18.1)

set(PDFIUM_BINARY_RELEASE chromium%2F6150)
set(PDFIUM_DIR ${CMAKE_CURRENT_BINARY_DIR}/pdfium)
set(PDFIUM_RELEASE_DIR ${PDFIUM_DIR}/${PDFIUM_BINARY_RELEASE})

file(MAKE_DIRECTORY ${PDFIUM_RELEASE_DIR})

set(PDFIUM_PLATFORM "android")
set(PDFIUM_LIB_FILENAME "libpdfium.so")
set(PDFIUM_LIB_DIR "lib")

set(PDFIUM_ABI2SUF_arm64-v8a "android-arm64")
set(PDFIUM_ABI2SUF_armeabi-v7a "android-arm")
set(PDFIUM_ABI2SUF_x86 "android-x86")
set(PDFIUM_ABI2SUF_x86_64 "android-x64")


set(PDFIUM_ARCHIVE_NAME pdfium-${PDFIUM_ABI2SUF_${ANDROID_ABI}})
set(PDFIUM_SRC_LIB_FILENAME ${PDFIUM_RELEASE_DIR}/${PDFIUM_LIB_DIR}/${PDFIUM_LIB_FILENAME})

set(PDFIUM_LIBS_DIR  ${CMAKE_CURRENT_SOURCE_DIR}/.lib)
set(PDFIUM_LIBS_ARCH_DIR ${PDFIUM_LIBS_DIR}/${ANDROID_ABI})
set(PDFIUM_DEST_LIB_FILENAME ${PDFIUM_LIBS_ARCH_DIR}/${PDFIUM_LIB_FILENAME})

if(NOT EXISTS ${PDFIUM_SRC_LIB_FILENAME})
    file(DOWNLOAD https://github.com/bblanchon/pdfium-binaries/releases/download/${PDFIUM_BINARY_RELEASE}/${PDFIUM_ARCHIVE_NAME}.tgz ${PDFIUM_RELEASE_DIR}/${PDFIUM_ARCHIVE_NAME}.tgz)
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E tar zxf ${PDFIUM_RELEASE_DIR}/${PDFIUM_ARCHIVE_NAME}.tgz
        WORKING_DIRECTORY ${PDFIUM_RELEASE_DIR}
        ERROR_QUIET
    )
    if(STATUS AND NOT STATUS EQUAL 0)
        message(FATAL_ERROR "Could not obtain pdfium binary for ${ANDROID_ABI}")
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

find_library(libc++ libc++_static.a)

file(GLOB_RECURSE PDFINTEROP_SOURCES "../darwin/Classes/*.cpp")
add_library(pdfinterop SHARED ${PDFINTEROP_SOURCES})
target_include_directories(pdfinterop PRIVATE ${PDFIUM_RELEASE_DIR}/include)
target_link_libraries(pdfinterop PRIVATE ${PDFIUM_DEST_LIB_FILENAME} ${libc++})
