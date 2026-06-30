// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OffsendScanAPI",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "OffsendScanAPI", targets: ["OffsendScanAPI"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.19.0"),
        .package(url: "https://github.com/hummingbird-project/swift-jobs.git", from: "1.3.0"),
        .package(url: "https://github.com/hummingbird-project/swift-jobs-valkey.git", from: "1.0.0"),
        .package(url: "https://github.com/soto-project/soto.git", from: "7.8.0"),
        .package(url: "https://github.com/hummingbird-project/swift-mustache.git", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "WorkspacePolicyCore",
            path: "Vendor/WorkspacePolicyCore/Sources"
        ),
        .target(
            name: "OffsendReportCore",
            dependencies: ["WorkspacePolicyCore"],
            path: "Vendor/OffsendReportCore"
        ),
        .executableTarget(
            name: "OffsendScanAPI",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Jobs", package: "swift-jobs"),
                .product(name: "JobsValkey", package: "swift-jobs-valkey"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "Mustache", package: "swift-mustache"),
                "OffsendReportCore",
                "WorkspacePolicyCore",
            ],
            path: "Sources/OffsendScanAPI",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OffsendScanAPITests",
            dependencies: [
                "OffsendScanAPI",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/OffsendScanAPITests"
        ),
    ]
)
