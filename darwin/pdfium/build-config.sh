#!/bin/zsh -e

if [ "$2" = "" ]; then
  echo "Usage: $0 linux|android|macos|ios|iossim x86|x64|arm|arm64"
  exit 1
fi

# https://pdfium.googlesource.com/pdfium/+/refs/heads/chromium/6150
LAST_KNOWN_GOOD_COMMIT=1e9d89db3c00fd1eab2959bd063832bebe6b868d

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

# linux, android, macos, ios
TARGET_OS_ORIG=$1
# x64, x86, arm64, ...
TARGET_ARCH=$2
# static or dll
STATIC_OR_DLL=static
# release or debug
REL_OR_DBG=release


if [[ "$TARGET_OS_ORIG" == "iossim" ]]; then
  TARGET_OS=ios
  TARGET_ENVIRONMENT=simulator
elif [[ "$TARGET_OS_ORIG" == "macos" ]]; then
  TARGET_OS=mac
else
  TARGET_OS=$TARGET_OS_ORIG
  # only for ios; simulator or device
  TARGET_ENVIRONMENT=device
fi


WORK_ROOT_DIR=$SCRIPT_DIR/.tmp
DIST_DIR=$WORK_ROOT_DIR/out

DEPOT_DIR=$WORK_ROOT_DIR/depot_tools
WORK_DIR=$WORK_ROOT_DIR/work

mkdir -p $WORK_ROOT_DIR $WORK_DIR $DIST_DIR

if [[ ! -d $DEPOT_DIR ]]; then
  pushd $WORK_ROOT_DIR
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
  popd
fi

export PATH=$DEPOT_DIR:$PATH

IS_SHAREDLIB=false

if [[ "$REL_OR_DBG" = "release" ]]; then
  IS_DEBUG=false
  DEBUG_DIR_SUFFIX=
else
  IS_DEBUG=true
  DEBUG_DIR_SUFFIX=/debug
fi

if [[ "$TARGET_OS" == "macos" || "$TARGET_OS" == "ios" || "$TARGET_OS" == "android" ]]; then
  IS_CLANG=true
else
  IS_CLANG=false
fi

cd $WORK_DIR
if [[ ! -e pdfium/.git/index ]]; then
  fetch pdfium
fi

PDFIUM_SRCDIR=$WORK_DIR/pdfium
BUILDDIR=$PDFIUM_SRCDIR/out/$TARGET_OS_ORIG-$TARGET_ARCH-$REL_OR_DBG
mkdir -p $BUILDDIR

if [[ "$LAST_KNOWN_GOOD_COMMIT" != "" ]]; then
  pushd $PDFIUM_SRCDIR
  git reset --hard
  git checkout $LAST_KNOWN_GOOD_COMMIT
  cd $PDFIUM_SRCDIR/build
  git reset --hard
  cd $PDFIUM_SRCDIR/third_party/libjpeg_turbo
  git reset --hard
  popd
fi

INCLUDE_DIR=$DIST_DIR/include
if [[ ! -d $INCLUDE_DIR ]]; then
  mkdir -p $INCLUDE_DIR
  cp -r $PDFIUM_SRCDIR/public/* $INCLUDE_DIR
fi

if [[ "$TARGET_OS" == "ios" ]]; then
  # (cd $PDFIUM_SRCDIR && git diff > ../../../patches/ios/pdfium.patch)
  pushd $PDFIUM_SRCDIR
  git apply $SCRIPT_DIR/patches/ios/pdfium.patch
  popd
  # (cd $PDFIUM_SRCDIR/third_party/libjpeg_turbo && git diff > ../../../../../patches/ios/libjpeg_turbo.patch)
  pushd $PDFIUM_SRCDIR/third_party/libjpeg_turbo/
  git apply $SCRIPT_DIR/patches/ios/libjpeg_turbo.patch
  popd
fi

if [[ "$TARGET_OS" == "mac" ]]; then
  # (cd $PDFIUM_SRCDIR && git diff > ../../../patches/macos/pdfium.patch)
  pushd $PDFIUM_SRCDIR
  git apply $SCRIPT_DIR/patches/macos/pdfium.patch
  popd
  # (cd $PDFIUM_SRCDIR/build && git diff > ../../../../patches/macos/build-config.patch)
  pushd $PDFIUM_SRCDIR/build
  git apply $SCRIPT_DIR/patches/macos/build-config.patch
  popd
fi

cat <<EOF > $BUILDDIR/args.gn
is_clang = $IS_CLANG
target_os = "$TARGET_OS"
target_cpu = "$TARGET_ARCH"
pdf_is_complete_lib = true
pdf_is_standalone = true
is_component_build = $IS_SHAREDLIB
is_debug = $IS_DEBUG
enable_iterator_debugging = $IS_DEBUG
pdf_enable_xfa = false
pdf_enable_v8 = false
EOF

if [[ "$TARGET_OS" == "ios" ]]; then
  # See ios/pdfium/.tmp/work/pdfium/build/config/ios/rules.gni
  cat <<EOF >> $BUILDDIR/args.gn
ios_enable_code_signing = false
ios_deployment_target = "12.0"
use_custom_libcxx = false
pdf_use_partition_alloc = false
target_environment = "$TARGET_ENVIRONMENT"
EOF
fi

if [[ "$TARGET_OS" == "mac" ]]; then
  cat <<EOF >> $BUILDDIR/args.gn
use_custom_libcxx = false
pdf_use_partition_alloc = false
EOF
fi

pushd $BUILDDIR
gn gen .
popd

ninja -C $BUILDDIR pdfium

LIB_DIR=$DIST_DIR/lib/$TARGET_OS_ORIG-$TARGET_ARCH-$REL_OR_DBG
rm -rf $LIB_DIR
mkdir -p $LIB_DIR
cp $BUILDDIR/obj/libpdfium.a $LIB_DIR

cd $SCRIPT_DIR
