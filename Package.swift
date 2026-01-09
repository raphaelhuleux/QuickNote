// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuickNote",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "QuickNote",
            dependencies: ["HotKey"],
            path: "QuickNote",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "QuickNoteTests",
            dependencies: [],
            path: "Tests/QuickNoteTests"
        )
    ]
)
