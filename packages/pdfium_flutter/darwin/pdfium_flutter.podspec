# PDFium xcframework configuration
# https://github.com/espresso3389/pdfium-xcframework/releases
PDFIUM_URL = "https://github.com/espresso3389/pdfium-xcframework/releases/download/v144.0.7520.0-20251111-190355/PDFium-chromium-7520-20251111-190355.xcframework.zip"
PDFIUM_HASH = "bd2a9542f13c78b06698c7907936091ceee2713285234cbda2e16bc03c64810b"

Pod::Spec.new do |s|
  s.name             = 'pdfium_flutter'
  s.version          = '0.1.5'
  s.summary          = 'Flutter FFI plugin for loading PDFium native libraries.'
  s.description      = <<-DESC
  Flutter FFI plugin for loading PDFium native libraries. Bundles PDFium binaries for iOS and macOS.
                       DESC
  s.homepage         = 'https://github.com/espresso3389/pdfrx'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Takashi Kawasaki' => 'espresso3389@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'pdfium_flutter/Sources/**/*.swift'
  s.preserve_paths = 'PDFium.xcframework/**/*'

  s.ios.deployment_target = '12.0'
  s.ios.dependency 'Flutter'
  s.ios.vendored_frameworks = 'PDFium.xcframework'
  # Flutter.framework does not contain a i386 slice.
  s.ios.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }

  s.osx.deployment_target = '10.13'
  s.osx.dependency 'FlutterMacOS'
  s.osx.vendored_frameworks = 'PDFium.xcframework'
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.swift_version = '5.0'

  s.prepare_command = <<-CMD
    HASH_FILE=".pdfium_hash"
    EXPECTED_HASH="#{PDFIUM_HASH}"

    # Check if we need to download/update
    NEEDS_DOWNLOAD=false
    if [ ! -d "PDFium.xcframework" ]; then
      echo "PDFium xcframework not found"
      NEEDS_DOWNLOAD=true
    elif [ ! -f "$HASH_FILE" ]; then
      echo "Hash file not found, will re-download"
      NEEDS_DOWNLOAD=true
    elif [ "$(cat $HASH_FILE)" != "$EXPECTED_HASH" ]; then
      echo "PDFium version mismatch, will update"
      NEEDS_DOWNLOAD=true
    fi

    if [ "$NEEDS_DOWNLOAD" = true ]; then
      # Clean up old version if exists
      rm -rf PDFium.xcframework
      rm -f "$HASH_FILE"

      echo "Downloading PDFium xcframework..."
      curl -L -o pdfium.zip "#{PDFIUM_URL}"

      echo "Verifying ZIP file hash..."
      ACTUAL_HASH=$(shasum -a 256 pdfium.zip | awk '{print $1}')

      if [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
        echo "Error: Hash mismatch!"
        echo "Expected: $EXPECTED_HASH"
        echo "Actual:   $ACTUAL_HASH"
        rm pdfium.zip
        exit 1
      fi
      echo "Hash verification successful"

      unzip -q pdfium.zip
      rm pdfium.zip

      # Store hash for future version checks
      echo "$EXPECTED_HASH" > "$HASH_FILE"

      echo "PDFium xcframework downloaded successfully"
    else
      echo "PDFium xcframework is up to date"
    fi
  CMD
end
