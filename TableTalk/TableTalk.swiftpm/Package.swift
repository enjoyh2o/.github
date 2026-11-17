// swift-tools-version: 6.0

// TableTalk — an app playground.
// Open this folder (TableTalk.swiftpm) in Xcode or Swift Playground.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "TableTalk",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .iOSApplication(
            name: "TableTalk",
            targets: ["AppModule"],
            bundleIdentifier: "com.example.tabletalk",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .gamepad),
            accentColor: .presetColor(.indigo),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .microphone(purposeString: "TableTalk listens for your moves and questions. Your voice is turned into text on this device and never leaves it."),
                .speechRecognition(purposeString: "Speech is recognised on this device so you can play by talking.")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ],
    swiftLanguageModes: [.v5]
)
