// swift-tools-version: 5.9
//
// Development-only package. It is NOT part of the Swift Student Challenge
// submission — that is `TableTalk.swiftpm`, which you open in Xcode or
// Swift Playground.
//
// This manifest compiles the pure-Swift game logic in
// `TableTalk.swiftpm/Core` as a library so it can be unit-tested from the
// command line on macOS or Linux:
//
//     swift test
//
import PackageDescription

let package = Package(
    name: "TableTalkCore",
    targets: [
        .target(
            name: "TableTalkCore",
            path: "TableTalk.swiftpm/Core"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["TableTalkCore"],
            path: "Tests/CoreTests"
        ),
    ]
)
