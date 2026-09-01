// swift-tools-version:6.0
import PackageDescription

// swu-labels — Star Wars Unlimited Avery 5167 card-label generator.
//
// Layering, from platform-free outward:
//
//   SWULabelsCore    pure logic. Foundation only. No AppKit, no UIKit, no
//                    SwiftUI, no CoreGraphics. Decides WHAT goes in every
//                    label cell and emits a SheetPlan.
//   SWULabelsRender  SheetPlan -> PDF via CoreGraphics/CoreText. Both of
//                    those ship on macOS, iOS, iPadOS, tvOS and visionOS,
//                    so this target carries no platform fork.
//   SWULabelsDocx    SheetPlan -> DOCX. Secondary export, isolated so the
//                    OOXML dependency never leaks into the print path.
//   SWULabelsUI      SwiftUI views. The whole interface lives HERE, in a
//                    library, not in an app executable — an iPad or iPhone
//                    app is then a new ~30-line executable target wrapping
//                    the same RootView, not a fork of the interface.
//
// The two executables are deliberately thin and macOS-only:
//
//   swu-labels       CLI. Ships INSIDE the .app bundle at
//                    Contents/MacOS/swu-labels so one signature and one
//                    notarization ticket cover both binaries.
//   SWULabelsApp     GUI shell. Builds Contents/MacOS/SWULabels.
//
// Every library product is declared explicitly so a future iOS target (in
// this package or an Xcode project alongside it) can depend on them without
// any restructuring here.
let package = Package(
    name: "SWULabels",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SWULabelsCore", targets: ["SWULabelsCore"]),
        .library(name: "SWULabelsRender", targets: ["SWULabelsRender"]),
        .library(name: "SWULabelsDocx", targets: ["SWULabelsDocx"]),
        .library(name: "SWULabelsUI", targets: ["SWULabelsUI"]),
        .executable(name: "swu-labels", targets: ["swu-labels"]),
        .executable(name: "SWULabelsApp", targets: ["SWULabelsApp"]),
    ],
    dependencies: [
        // Argument parsing is a recurring concern with a standard answer on this
        // platform, so the CLI wires Apple's parser rather than re-deriving
        // flag handling, `--help` output and validation by hand.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "SWULabelsCore",
            path: "Sources/SWULabelsCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SWULabelsRender",
            dependencies: ["SWULabelsCore"],
            path: "Sources/SWULabelsRender",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SWULabelsDocx",
            dependencies: ["SWULabelsCore"],
            path: "Sources/SWULabelsDocx",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SWULabelsUI",
            dependencies: ["SWULabelsCore", "SWULabelsRender"],
            path: "Sources/SWULabelsUI",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "swu-labels",
            dependencies: [
                "SWULabelsCore",
                "SWULabelsRender",
                "SWULabelsDocx",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/swu-labels",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SWULabelsApp",
            dependencies: ["SWULabelsUI"],
            path: "Sources/SWULabelsApp",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SWULabelsCoreTests",
            dependencies: ["SWULabelsCore", "SWULabelsRender"],
            path: "Tests/SWULabelsCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
