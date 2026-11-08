// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StoreKitFlow",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "StoreKitFlow", targets: ["StoreKitFlow"])],
    targets: [.target(name: "StoreKitFlow")],
    swiftLanguageModes: [.v6]
)
