// swift-tools-version:5.10
import PackageDescription

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
    ],
    targets: [
        .target(name: "CPTY"),
        // No AppKit, UIKit or SwiftUI here: the core stays portable.
        .target(name: "EntermCore"),
        .executableTarget(name: "entermd", dependencies: ["EntermCore", "CPTY"]),
        .executableTarget(name: "enterm", dependencies: ["EntermCore"]),
        .executableTarget(name: "EntermApp", dependencies: [
            "EntermCore",
            .product(name: "SwiftTerm", package: "SwiftTerm"),
        ]),
        .testTarget(name: "EntermCoreTests", dependencies: ["EntermCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
