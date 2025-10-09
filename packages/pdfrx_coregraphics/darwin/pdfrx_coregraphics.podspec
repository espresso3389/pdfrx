#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pdfrx_coregraphics.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pdfrx_coregraphics'
  s.version          = '0.0.1'
  s.summary          = 'CoreGraphics-backed renderer for pdfrx on Apple platforms.'
  s.description      = <<-DESC
Provides a PdfrxEntryFunctions implementation that uses PDFKit/CoreGraphics instead of PDFium.
                       DESC
  s.homepage         = 'https://github.com/espresso3389/pdfrx'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Takashi Kawasaki' => 'espresso3389@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = [ 'Classes/PdfrxCoregraphicsPlugin.swift' ]

  s.ios.deployment_target = '13.0'
  s.ios.dependency 'Flutter'
  # Flutter.framework does not contain a i386 slice.
  s.ios.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }

  s.osx.deployment_target = '10.13'
  s.osx.dependency 'FlutterMacOS'
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'pdfrx_coregraphics_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
