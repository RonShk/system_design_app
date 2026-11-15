// swift-tools-version: 5.9
import PackageDescription

// Pure domain logic for the System Design Trainer app: content models, answer checking,
// progress, spaced-review scheduling, session composition, persistence and backup.
// No UIKit/SwiftUI dependencies, so it is tested on macOS with `swift test`.
let package = Package(
    name: "TrainerCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TrainerCore", targets: ["TrainerCore"])],
    targets: [
        .target(name: "TrainerCore"),
        .testTarget(name: "TrainerCoreTests", dependencies: ["TrainerCore"]),
    ]
)
