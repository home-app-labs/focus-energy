// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FocusPlus",
    platforms: [.macOS(.v14)],
    targets: [
        // Widget snapshot model and views, shared by the app (which writes the snapshot) and the widget.
        .target(name: "WidgetUI", path: "Sources/WidgetUI"),
        .executableTarget(name: "FocusPlus", dependencies: ["WidgetUI"], path: "Sources/FocusPlus"),
        // The WidgetKit extension. Linked like an Xcode app extension target.
        .executableTarget(
            name: "FocusPlusWidget", dependencies: ["WidgetUI"], path: "Sources/FocusPlusWidget",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .testTarget(name: "FocusPlusTests", dependencies: ["FocusPlus"], path: "Tests/FocusPlusTests"),
    ]
)
