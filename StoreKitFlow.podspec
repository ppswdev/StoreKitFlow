Pod::Spec.new do |spec|
  spec.name = "StoreKitFlow"
  spec.version = "2.0.0"
  spec.summary = "Swift 6 StoreKit 2 purchase, delivery and entitlement flows for SwiftUI."
  spec.description = "A Swift 6 client with verified entitlement resolution, durable consumable delivery, subscription state observation, and optional backend hooks."
  spec.homepage = "https://github.com/ppswdev/StoreKitFlow"
  spec.license = { :type => "MIT", :file => "LICENSE" }
  spec.author = { "ppswdev" => "xiaopin166@gmail.com" }
  spec.source = { :git => "https://github.com/ppswdev/StoreKitFlow.git", :tag => spec.version.to_s }
  spec.platforms = { :ios => "17.0", :osx => "14.0" }
  spec.swift_version = "6.0"
  spec.source_files = "Sources/StoreKitFlow/**/*.swift"
  spec.frameworks = "Foundation", "StoreKit"
  spec.ios.frameworks = "UIKit"
  spec.module_name = "StoreKitFlow"
  spec.pod_target_xcconfig = { "SWIFT_STRICT_CONCURRENCY" => "complete" }
end
