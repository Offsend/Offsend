// swift-tools-version: 6.0
import PackageDescription

let ffiVendor = "\(Context.packageDirectory)/Vendor/OffsendFFI"

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
            name: "COffsendFFI",
            path: "Vendor/OffsendFFI",
            exclude: [
                "README.md",
                "module.modulemap",
                "OffsendFFI.h",
                "offsend_ffi.h",
                "liboffsend_ffi.a",
            ],
            publicHeadersPath: ".",
            linkerSettings: [
                .unsafeFlags(["-L\(ffiVendor)"]),
                .linkedLibrary("offsend_ffi"),
                .linkedFramework("CoreFoundation", .when(platforms: [.macOS])),
                .linkedFramework("Security", .when(platforms: [.macOS])),
                .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
                .linkedLibrary("m", .when(platforms: [.linux])),
                .linkedLibrary("dl", .when(platforms: [.linux])),
                .linkedLibrary("pthread", .when(platforms: [.linux])),
            ]
        ),
        .executableTarget(
            name: "OffsendScanAPI",
            dependencies: [
                "COffsendFFI",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Jobs", package: "swift-jobs"),
                .product(name: "JobsValkey", package: "swift-jobs-valkey"),
                .product(name: "SotoS3", package: "soto"),
                .product(name: "Mustache", package: "swift-mustache"),
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
