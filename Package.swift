// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "DelegateBridge",
    platforms: [.macOS(.v14), .iOS(.v15), .tvOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "DelegateBridge", targets: ["DelegateBridge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"604.0.0"),
    ],
    targets: [
        // The macro implementation library (testable)
        .target(
            name: "DelegateBridgeMacrosImpl",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        // The macro as a compiler plugin
        .macro(
            name: "DelegateBridgeMacros",
            dependencies: [
                "DelegateBridgeMacrosImpl",
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        // The public API library
        .target(
            name: "DelegateBridge",
            dependencies: ["DelegateBridgeMacros"]
        ),
        // Tests
        .testTarget(
            name: "DelegateBridgeTests",
            dependencies: [
                "DelegateBridgeMacrosImpl",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
