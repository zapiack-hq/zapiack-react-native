require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "zapiack-react-native"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://zapiack.com"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author       = { "Zapiack" => "support@zapiack.com" }
  s.platforms    = { :ios => "13.0" }
  s.source       = { :git => "https://github.com/zapiack-hq/zapiack-react-native.git", :tag => "v#{s.version}" }
  s.source_files = "ios/**/*.{h,m,swift}"
  s.swift_version = "5.9"
  s.dependency "React-Core"
end
