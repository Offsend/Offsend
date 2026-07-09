// swift-tools-version: 6.0
//
// Shared SPM package for Offsend core modules and the cross-platform CLI.
//
// Build CLI:
//   swift build --product offsend
//   .build/debug/offsend check --help
//
// Test:
//   swift test
import PackageDescription

let package = Package(
    name: "OffsendCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "DetectionCore", targets: ["DetectionCore"]),
        .library(name: "MaskingCore", targets: ["MaskingCore"]),
        .library(name: "RiskScoringCore", targets: ["RiskScoringCore"]),
        .library(name: "WorkspacePolicyCore", targets: ["WorkspacePolicyCore"]),
        .library(name: "StorageCore", targets: ["StorageCore"]),
        .library(name: "DocumentCore", targets: ["DocumentCore"]),
        .library(name: "OffsendRuntime", targets: ["OffsendRuntime"]),
        .executable(name: "offsend", targets: ["OffsendCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "DetectionCore",
            path: "Core/DetectionCore/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .target(
            name: "MaskingCore",
            dependencies: [
                "DetectionCore",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Core/MaskingCore",
            exclude: ["Tests"],
            sources: ["Sources", "SPM"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .target(
            name: "RiskScoringCore",
            dependencies: ["DetectionCore"],
            path: "Core/RiskScoringCore/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .target(
            name: "WorkspacePolicyCore",
            path: "Core/WorkspacePolicyCore/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .target(
            name: "StorageCore",
            dependencies: ["DetectionCore", "MaskingCore"],
            path: "Core/StorageCore",
            exclude: ["Tests"],
            sources: ["Sources", "SPM"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .target(
            name: "DocumentCore",
            dependencies: [
                "DetectionCore",
                "MaskingCore",
                "RiskScoringCore",
            ],
            path: "Core/DocumentCore/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("PDFKit", .when(platforms: [.macOS, .iOS])),
            ]
        ),

        .target(
            name: "OffsendRuntime",
            dependencies: [
                "DetectionCore",
                "DocumentCore",
                "MaskingCore",
                "WorkspacePolicyCore",
                "RiskScoringCore",
                "StorageCore",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Core/OffsendRuntime/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .executableTarget(
            name: "OffsendCLI",
            dependencies: [
                "OffsendRuntime",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "CLI/Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .testTarget(
            name: "DetectionCoreTests",
            dependencies: ["DetectionCore"],
            path: "Core/DetectionCore/Tests"
        ),

        .testTarget(
            name: "MaskingCoreTests",
            dependencies: ["MaskingCore"],
            path: "Core/MaskingCore/Tests"
        ),

        .testTarget(
            name: "RiskScoringCoreTests",
            dependencies: ["RiskScoringCore"],
            path: "Core/RiskScoringCore/Tests"
        ),

        .testTarget(
            name: "WorkspacePolicyCoreTests",
            dependencies: ["WorkspacePolicyCore"],
            path: "Core/WorkspacePolicyCore/Tests"
        ),

        .testTarget(
            name: "StorageCoreTests",
            dependencies: ["StorageCore", "MaskingCore"],
            path: "Core/StorageCore/Tests"
        ),

        .testTarget(
            name: "DocumentCoreTests",
            dependencies: ["DocumentCore"],
            path: "Core/DocumentCore/Tests",
            exclude: [
                "WordTestFixtures.swift",
                "WordDocumentToPDFConverterTests.swift",
                "WordDocumentExtractorTests.swift",
                "PDFDocumentExtractorTests.swift",
                "RTFDocumentExtractorTests.swift",
                "DocumentProcessingPipelineTests.swift",
                "Redaction/PDFRedactionRegionResolverTests.swift",
                "Redaction/PDFRedactionEngineTests.swift",
                "Redaction/PDFRedactionExporterTests.swift",
                "Redaction/PDFRedactionPlanBuilderTests.swift",
            ],
            resources: [
                .copy("Fixtures")
            ]
        ),

        .testTarget(
            name: "OffsendRuntimeTests",
            dependencies: ["OffsendRuntime"],
            path: "Core/OffsendRuntime/Tests",
            exclude: [
                "CLIPathInstallerTests.swift",
            ]
        ),
    ]
)
