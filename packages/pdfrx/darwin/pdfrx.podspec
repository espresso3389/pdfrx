#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pdfrx.podspec` to validate before publishing.
#
lib_tag = 'pdfium-apple-v11'

Pod::Spec.new do |s|
  s.name             = 'pdfrx'
  s.version          = '0.0.7'
  s.summary          = 'Yet another PDF renderer for Flutter using PDFium.'
  s.description      = <<-DESC
  Yet another PDF renderer for Flutter using PDFium.
                       DESC
  s.homepage         = 'https://github.com/espresso3389/pdfrx'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Takashi Kawasaki' => 'espresso3389@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'pdfrx/Sources/pdfrx/**/*'

  s.ios.deployment_target = '12.0'
  s.ios.dependency 'Flutter'
  s.ios.private_header_files = "pdfium/.lib/#{lib_tag}/ios/pdfium.xcframework/ios-arm64/Headers/*.h"
  s.ios.vendored_frameworks = "pdfium/.lib/#{lib_tag}/ios/pdfium.xcframework"
  # Flutter.framework does not contain a i386 slice.
  s.ios.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }

  s.osx.deployment_target = '10.13'
  s.osx.dependency 'FlutterMacOS'
  s.osx.private_header_files = "pdfium/.lib/#{lib_tag}/macos/pdfium.xcframework/macos-arm64_x86_64/Headers/*.h"
  s.osx.vendored_frameworks = "pdfium/.lib/#{lib_tag}/macos/pdfium.xcframework"
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.prepare_command = <<-CMD
    mkdir -p pdfium/.lib/#{lib_tag}
    cd pdfium/.lib/#{lib_tag}
    rm -rf ios.zip macos.zip ios/ macos/
    curl -Lo ios.zip https://github.com/espresso3389/pdfrx/releases/download/#{lib_tag}/pdfium-ios.zip
    unzip -o ios.zip
    curl -Lo macos.zip https://github.com/espresso3389/pdfrx/releases/download/#{lib_tag}/pdfium-macos.zip
    unzip -o macos.zip
  CMD

  s.swift_version = '5.0'
end
