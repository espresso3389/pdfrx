#!/usr/bin/env bash
set -euo pipefail

# Run from any directory. Flutter's real platform framework is linked so the
# production bridge, codec values and PDFKit calls are compiled and executed.
package_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(cd "$package_dir/../.." && pwd)"
flutter_root="${FLUTTER_ROOT:-$(cd "$(dirname "$(command -v flutter)")/.." && pwd)}"
build_dir="${PDFRX_NATIVE_BUILD_DIR:-$package_dir/build/native-tests}"
mkdir -p "$build_dir"
apple_platform="${PDFRX_APPLE_PLATFORM:-macos}"
apple_sdk=macosx
framework_name=FlutterMacOS
platform_flags=(-target "$(uname -m)-apple-macos12.0")
if [[ "$apple_platform" == ios-simulator ]]; then
  apple_sdk=iphonesimulator
  framework_name=Flutter
  framework_dir="$(find "$flutter_root/bin/cache/artifacts/engine" -path '*/ios-arm64_x86_64-simulator/Flutter.framework' -type d -print -quit)"
  platform_flags=(-sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target "$(uname -m)-apple-ios15.0-simulator")
else
  framework_dir="$(find "$flutter_root/bin/cache/artifacts/engine" -path '*/FlutterMacOS.framework' -type d -print -quit)"
fi
if [[ -z "$framework_dir" ]]; then
  echo 'Run flutter precache --macos (or --ios for the simulator) first.' >&2
  exit 1
fi
framework_parent="$(dirname "$framework_dir")"
source_dir="$package_dir/darwin/pdfrx_coregraphics/Sources"
sources=("$source_dir/CoreGraphicsWorkQueue.swift" "$source_dir/PdfrxCoregraphicsPlugin.swift")
swift_flags=(-D PDFRX_CANDIDATE)
if [[ -n "${PDFRX_BASELINE_REF:-}" ]]; then
  git -C "$repo_dir" show "$PDFRX_BASELINE_REF:packages/pdfrx_coregraphics/darwin/pdfrx_coregraphics/Sources/PdfrxCoregraphicsPlugin.swift" > "$build_dir/BaselinePlugin.swift"
  # Older source used optional binding for Apple's nonfailable empty initializers.
  # Make just those bindings compile; this does not change the execution path.
  python3 - "$build_dir/BaselinePlugin.swift" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
source = path.read_text()
source = source.replace('= PDFDocument() else {', '= (PDFDocument() as PDFDocument?) else {')
source = source.replace('= PDFPage() else {', '= (PDFPage() as PDFPage?) else {')
path.write_text(source)
PY
  sources=("$build_dir/BaselinePlugin.swift")
  swift_flags=(-D PDFRX_BASELINE)
fi
xcrun --sdk "$apple_sdk" swiftc -O -swift-version 5 "${swift_flags[@]}" "${platform_flags[@]}" -F "$framework_parent" \
  -framework "$framework_name" -framework PDFKit -framework CoreText \
  -Xlinker -rpath -Xlinker "$framework_parent" \
  "${sources[@]}" "$package_dir/tool/native/main.swift" -o "$build_dir/coregraphics-tests"
run_native() {
  if [[ "$apple_platform" == ios-simulator ]]; then
    SIMCTL_CHILD_DYLD_FRAMEWORK_PATH="$framework_parent" xcrun simctl spawn "${PDFRX_SIMULATOR_UDID:-booted}" "$build_dir/coregraphics-tests" "$@"
  else
    "$build_dir/coregraphics-tests" "$@"
  fi
}
if [[ "$apple_platform" == ios-simulator ]]; then
  codesign --force --sign - "$build_dir/coregraphics-tests"
fi
run_native "$repo_dir/packages/pdfrx_engine/test/assets/encrypted.pdf"
if [[ "${PDFRX_RUN_BENCHMARK:-0}" == 1 ]]; then
  run_native --make-benchmark-fixture "$build_dir/benchmark.pdf"
  run_native --benchmark "$build_dir/benchmark.pdf"
fi
