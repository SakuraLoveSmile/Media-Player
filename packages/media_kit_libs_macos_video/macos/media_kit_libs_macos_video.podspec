#
# To learn more about Podspec attributes see https://guides.cocoapods.org/syntax/podspec.html
# To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|
  # `make` downloads the "video-full" libmpv build and unpacks it into
  # Frameworks/ before CocoaPods reads `vendored_frameworks` below.
  system("make")

  s.name             = 'media_kit_libs_macos_video'
  s.version          = '1.1.4'
  s.summary          = 'macOS dependency package for package:media_kit (video-full libmpv)'
  s.description      = <<-DESC
  macOS dependency package for package:media_kit, built from the libmpv
  "video-full" variant so decoders missing from the default variant (TrueHD,
  MLP) are present.
                       DESC
  s.homepage         = 'https://github.com/media-kit/media-kit.git'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hitesh Kumar Saini' => 'saini123hitesh@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.vendored_frameworks = 'Frameworks/*.xcframework'

  s.platform = :osx, '10.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
