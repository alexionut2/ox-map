// swift-tools-version:5.9
import PackageDescription

// OxydeCore holds every piece of Oxyde Map that does not depend on UIKit, MapKit,
// CoreLocation or CarPlay: geometry, route progress, guidance scheduling, the theme
// registry and style compiler, report rules, settings and profiles. It builds and its
// tests run on macOS, iOS and Linux, so the navigation logic can be verified without
// a device.
let package = Package(
    name: "OxydeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OxydeCore", targets: ["OxydeCore"])
    ],
    targets: [
        .target(name: "OxydeCore"),
        .testTarget(name: "OxydeCoreTests", dependencies: ["OxydeCore"])
    ]
)
