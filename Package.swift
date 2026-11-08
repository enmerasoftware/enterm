// swift-tools-version:5.10
import Foundation
import PackageDescription

// The test driver exists only in debug builds, or when a measurement build asks for it explicitly.
let driverSettings: [SwiftSetting] = ProcessInfo.processInfo.environment["ENTERM_DRIVER_RELEASE"] != nil
    ? [.define("ENTERM_TEST_DRIVER")]
    : [.define("ENTERM_TEST_DRIVER", .when(configuration: .debug))]

let package = Package(
    name: "Enterm",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "EntermCore", targets: ["EntermCore"]),
        .executable(name: "entermd", targets: ["entermd"]),
        .executable(name: "enterm", targets: ["enterm"]),
        .executable(name: "EntermApp", targets: ["EntermApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "CPTY"),
        // No AppKit, UIKit or SwiftUI here: the core stays portable.
        .target(name: "EntermCore"),
        .executableTarget(name: "entermd", dependencies: ["EntermCore", "CPTY"], swiftSettings: driverSettings),
        .executableTarget(name: "enterm", dependencies: ["EntermCore"]),
        .executableTarget(name: "EntermApp", dependencies: [
            "EntermCore",
            .product(name: "SwiftTerm", package: "SwiftTerm"),
            .product(name: "Sparkle", package: "Sparkle"),
        ], swiftSettings: driverSettings),
        .testTarget(name: "EntermCoreTests", dependencies: ["EntermCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
