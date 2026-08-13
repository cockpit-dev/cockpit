Pod::Spec.new do |s|
  s.name             = 'flutter_cockpit'
  s.version          = '4.0.15'
  s.summary          = 'Native screenshot and recording support for flutter_cockpit.'
  s.description      = <<-DESC
Native screenshot and recording support for flutter_cockpit development workflows.
                       DESC
  s.homepage         = 'https://github.com/cockpit-dev/cockpit'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'cockpit-dev' => 'dev@cockpit.dev' }
  s.source           = {
    :git => 'https://github.com/cockpit-dev/cockpit.git',
    :tag => "v#{s.version}",
  }
  s.source_files = 'flutter_cockpit/Sources/flutter_cockpit/**/*.swift'
  s.resource_bundles = {
    'flutter_cockpit_privacy' => ['flutter_cockpit/Sources/flutter_cockpit/PrivacyInfo.xcprivacy']
  }
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
