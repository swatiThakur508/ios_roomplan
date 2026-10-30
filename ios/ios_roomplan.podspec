#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ios_roomplan.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ios_roomplan'
  s.version          = '0.2.1'
  s.summary          = 'Single- and multi-room RoomPlan scanning with 2D PDF and 3D USDZ output for Flutter.'
  s.description      = <<-DESC
Scan single or connected rooms on supported iOS devices and export 2D floor plans, structured data, and 3D USDZ models.
                       DESC
  s.homepage         = 'https://github.com/swatiThakur508/ios_roomplan'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Swati Thakur'
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'ios_roomplan_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
  s.frameworks = 'RoomPlan', 'ARKit', 'AVFoundation', 'PDFKit', 'QuickLook'

end
