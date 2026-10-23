#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ios_roomplan.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ios_roomplan'
  s.version          = '0.1.0'
  s.summary          = 'RoomPlan scanning and editable floor plans for iOS.'
  s.description      = <<-DESC
RoomPlan scanning and editable floor plans for iOS.
                       DESC
  s.homepage         = 'https://pub.dev/packages/ios_roomplan'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'GEITPL'
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'ios_roomplan_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
  s.frameworks = 'RoomPlan', 'ARKit', 'AVFoundation', 'PDFKit', 'QuickLook'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'ios_roomplan_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
