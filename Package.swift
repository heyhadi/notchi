// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NotchBuddy",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (state, event parsing, risk classifier) so it is unit-testable.
        .target(name: "NotchBuddyCore"),
        .executableTarget(name: "NotchBuddy", dependencies: ["NotchBuddyCore"], resources: [.process("Resources")]),
        // Tiny hook binary Claude Code runs; forwards stdin JSON to the app's Unix socket.
        .executableTarget(name: "notchbuddy-hook"),
        .testTarget(name: "NotchBuddyCoreTests", dependencies: ["NotchBuddyCore"]),
    ]
)
