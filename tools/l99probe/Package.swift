// swift-tools-version:5.10
// l99probe — hardware smoke-test tool for the AULA L99 (PRD step 3).
// Private, local-only. No network access.
import PackageDescription

let package = Package(
    name: "l99probe",
    platforms: [.macOS(.v14)],
    products: [
        // Used by the L99 Control Center app as its protocol layer.
        .library(name: "L99Core", targets: ["L99Core"]),
        .library(name: "L99Link", targets: ["L99Link"]),
    ],
    targets: [
        // Pure packet building and checksums. No device access, fully unit-tested.
        // Always optimised: dithering and palette building over a whole animation are
        // ~60× slower at -Onone, which would make the app's Debug build unusable.
        .target(name: "L99Core", swiftSettings: [.unsafeFlags(["-O"])]),
        // Device access: the screen's serial port, the wired keyboard and the dongle (IOKit).
        .target(name: "L99Link", dependencies: ["L99Core"]),
        // Command-line tool for hardware tests, on top of L99Link.
        .executableTarget(name: "l99probe", dependencies: ["L99Core", "L99Link"]),
        .testTarget(name: "L99CoreTests", dependencies: ["L99Core"]),
    ]
)
