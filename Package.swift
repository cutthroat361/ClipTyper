// swift-tools-version:5.9
//
// Swift package description. It is used for the unit tests (`swift test`) and for opening
// the project in Xcode. The app itself is built and packaged by ./build.sh.

import PackageDescription

let package = Package(
    name: "ClipTyper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClipTyper",
            path: "Sources/ClipTyper"
        ),
        .testTarget(
            name: "ClipTyperTests",
            dependencies: ["ClipTyper"],
            path: "Tests/ClipTyperTests"
        ),
    ]
)
