// swift-tools-version:5.10
// l99probe — hardware smoke-test tool for the AULA L99 (PRD step 3).
// Local-only. No network access.
import PackageDescription

let package = Package(
    name: "l99probe",
    platforms: [.macOS(.v14)],
    products: [
        // Used by the L99 Control Center app as its protocol layer.
        .library(name: "L99Core", targets: ["L99Core"]),
        .library(name: "L99Link", targets: ["L99Link"]),
        .library(name: "L99Skins", targets: ["L99Skins"]),
    ],
    targets: [
        // Pure packet building and checksums. No device access, fully unit-tested.
        // Always optimised: dithering and palette building over a whole animation are
        // ~60× slower at -Onone, which would make the app's Debug build unusable.
        .target(name: "L99Core", swiftSettings: [.unsafeFlags(["-O"])]),
        // Direct USB bulk access to the screen in bootloader mode, bypassing macOS's CDC
        // serial driver (research/ISP_PROTOCOL.md). C, because IOUSBLib is COM-style.
        .target(name: "L99USB", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        // Device access: the screen's serial port, the wired keyboard and the dongle (IOKit).
        .target(name: "L99Link", dependencies: ["L99Core", "L99USB"]),
        // The skin maker: six styles' artwork (drawn with the bundled open-licence fonts) and the
        // builder that turns a style choice per section into one interface file. Optimised for the
        // same reason as L99Core (whole-page rendering and compression).
        .target(name: "L99Skins", dependencies: ["L99Core"], resources: [.copy("Fonts")], swiftSettings: [.unsafeFlags(["-O"])]),
        // Command-line tool for hardware tests, on top of L99Link.
        .executableTarget(name: "l99probe", dependencies: ["L99Core", "L99Link", "L99Skins"]),
        .testTarget(name: "L99CoreTests", dependencies: ["L99Core"]),
    ]
)
