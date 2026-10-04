// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "stay-probe",
            targets: ["StayProbe"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "StayProbe",
            dependencies: [],
            path: "Sources/StayProbe"
        )
    ]
)
