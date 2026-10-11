// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "StayCore", targets: ["StayCore"]),
        .executable(name: "Stay", targets: ["Stay"]),
        .executable(name: "stay-probe", targets: ["StayProbe"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "StayCore",
            dependencies: [],
            path: "Sources/StayCore"
        ),
        .executableTarget(
            name: "Stay",
            dependencies: ["StayCore"],
            path: "Sources/Stay"
        ),
        .executableTarget(
            name: "StayProbe",
            dependencies: [],
            path: "Sources/StayProbe"
        ),
        .testTarget(
            name: "StayTests",
            dependencies: ["StayCore"],
            path: "Tests/StayTests",
            swiftSettings: [
                .unsafeFlags([
                    "-load-plugin-library",
                    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
                ])
            ]
        )
    ]
)
