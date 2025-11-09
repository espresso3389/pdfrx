Pod::Spec.new do |s|
  s.name             = 'pdfrx'
  s.version          = '0.1.3'
  s.summary          = 'Yet another PDF renderer for Flutter using PDFium.'
  s.description      = <<-DESC
  Yet another PDF renderer for Flutter using PDFium.
                       DESC
  s.homepage         = 'https://github.com/espresso3389/pdfrx'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Takashi Kawasaki' => 'espresso3389@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Sources/**/*.swift'
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
  s.osx.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-framework PDFium'
  }

  s.swift_version = '5.0'

  s.prepare_command = <<-CMD
    if [ ! -d "PDFium.xcframework" ]; then
      echo "Downloading PDFium xcframework..."
      curl -L -o pdfium.zip "https://github.com/espresso3389/pdfium-xcframework/releases/download/v144.0.7506.0/PDFium-chromium-7506-20251109-174316.xcframework.zip"
      unzip -q pdfium.zip
      rm pdfium.zip
      echo "PDFium xcframework downloaded successfully"
    else
      echo "PDFium xcframework already exists, skipping download"
    fi
  CMD
end
