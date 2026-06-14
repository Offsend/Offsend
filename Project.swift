import ProjectDescription

let appMarketingVersion = "0.0.5" // Local default; release workflow overrides via MARKETING_VERSION input
let appBuildNumber = "3" // Local default; release workflow overrides via github.run_number

let appName = "Offsend"
let bundlePrefix = "io.offsend"
let macOSDeploymentTarget: DeploymentTargets = .macOS("13.0")

/// Developer ID + Hardened Runtime for Release (required for notarization). Do not pass CODE_SIGN_IDENTITY
/// via `xcodebuild` — it applies to SwiftPM targets and conflicts with their automatic Apple Development signing.
let developerIDReleaseSigning: Settings = .settings(
    configurations: [
        .debug(name: .debug),
        .release(
            name: .release,
            settings: [
                "CODE_SIGN_IDENTITY": "Developer ID Application",
                "ENABLE_HARDENED_RUNTIME": "YES"
            ]
        )
    ],
    defaultSettings: .recommended
)

let externalPackages: [Package] = [
    .remote(url: "https://github.com/apple/swift-argument-parser", requirement: .upToNextMajor(from: "1.3.0")),
    .remote(url: "https://github.com/jpsim/Yams", requirement: .upToNextMajor(from: "5.1.0")),
    .remote(url: "https://github.com/sindresorhus/KeyboardShortcuts", requirement: .upToNextMajor(from: "2.3.0")),
    .remote(url: "https://github.com/stephencelis/SQLite.swift", requirement: .upToNextMajor(from: "0.15.0")),
    .remote(url: "https://github.com/sparkle-project/Sparkle", requirement: .exact("2.7.1")),
    .remote(url: "https://github.com/TelemetryDeck/SwiftSDK", requirement: .upToNextMajor(from: "2.0.0")),
    .remote(
        url: "https://github.com/microsoft/onnxruntime-swift-package-manager",
        requirement: .upToNextMajor(from: "1.24.2")
    ),
]

let coreTargets: [Target] = [
    .target(
        name: "LicenseCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).licensecore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/LicenseCore/Sources/**"],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "DetectionCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).detectioncore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/DetectionCore/Sources/**"],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "AIDetectionCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).aidetectioncore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/AIDetectionCore/Sources/**"],
        dependencies: [
            .target(name: "DetectionCore"),
            .package(product: "onnxruntime"),
            .sdk(name: "CoreML", type: .framework, status: .required),
        ],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "MaskingCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).maskingcore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/MaskingCore/Sources/**"],
        resources: ["Core/MaskingCore/Resources/**"],
        dependencies: [.target(name: "DetectionCore")],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "RiskScoringCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).riskscoringcore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/RiskScoringCore/Sources/**"],
        dependencies: [.target(name: "DetectionCore")],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "WorkspacePolicyCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).workspacepolicycore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/WorkspacePolicyCore/Sources/**"],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "StorageCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).storagecore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/StorageCore/Sources/**"],
        resources: ["Core/StorageCore/Resources/**"],
        dependencies: [
            .target(name: "DetectionCore"),
            .target(name: "MaskingCore"),
            .package(product: "SQLite")
        ],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "OffsendRuntime",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).offsendruntime",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/OffsendRuntime/Sources/**"],
        dependencies: [
            .target(name: "DetectionCore"),
            .target(name: "DocumentCore"),
            .target(name: "WorkspacePolicyCore"),
            .target(name: "RiskScoringCore"),
            .target(name: "StorageCore"),
            .target(name: "LicenseCore"),
            .package(product: "Yams")
        ],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "DocumentCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).documentcore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/DocumentCore/Sources/**"],
        dependencies: [
            .target(name: "DetectionCore"),
            .target(name: "MaskingCore"),
            .target(name: "RiskScoringCore"),
            .sdk(name: "PDFKit", type: .framework, status: .required)
        ],
        settings: developerIDReleaseSigning
    )
]

let serviceTargets: [Target] = [
    .target(
        name: "ClipboardService",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).clipboardservice",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/ClipboardService/Sources/**"],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "PasteService",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).pasteservice",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/PasteService/Sources/**"],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "HotkeyService",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).hotkeyservice",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/HotkeyService/Sources/**"],
        dependencies: [.package(product: "KeyboardShortcuts")],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "PermissionsService",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).permissionsservice",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/PermissionsService/Sources/**"],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "WorkspaceWatchService",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).workspacewatchservice",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/WorkspaceWatchService/Sources/**"],
        dependencies: [.target(name: "WorkspacePolicyCore")],
        settings: developerIDReleaseSigning
    ),
    .target(
        name: "AnalyticsCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).analyticscore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/AnalyticsCore/Sources/**"],
        dependencies: [
            .target(name: "DetectionCore"),
            .target(name: "StorageCore"),
            .package(product: "TelemetryDeck")
        ],
        settings: developerIDReleaseSigning
    )
]

let cliTargets: [Target] = [
    .target(
        name: "OffsendCLI",
        destinations: .macOS,
        product: .commandLineTool,
        bundleId: "\(bundlePrefix).cli",
        deploymentTargets: macOSDeploymentTarget,
        infoPlist: .file(path: "CLI/Resources/Info.plist"),
        sources: ["CLI/Sources/**"],
        dependencies: [
            .target(name: "OffsendRuntime"),
            .package(product: "ArgumentParser")
        ],
        settings: .settings(
            base: [
                "PRODUCT_NAME": "offsend",
                "MARKETING_VERSION": "\(appMarketingVersion)",
                "CURRENT_PROJECT_VERSION": "\(appBuildNumber)",
                "CREATE_INFOPLIST_SECTION_IN_BINARY": "YES",
                "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path @loader_path @executable_path/../Frameworks @executable_path/Frameworks"
            ],
            configurations: [
                .debug(name: .debug),
                .release(
                    name: .release,
                    settings: [
                        "CODE_SIGN_IDENTITY": "Developer ID Application",
                        "ENABLE_HARDENED_RUNTIME": "YES"
                    ]
                )
            ],
            defaultSettings: .recommended
        )
    )
]

let uiTargets: [Target] = [
    .target(
        name: "AppUIKit",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).appuikit",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["AppUIKit/Sources/**"],
        resources: ["AppUIKit/Resources/**"],
        dependencies: [
            .sdk(name: "PDFKit", type: .framework, status: .required)
        ],
        settings: developerIDReleaseSigning
    )
]

let appTarget = Target.target(
    name: appName,
    destinations: .macOS,
    product: .app,
    bundleId: bundlePrefix,
    deploymentTargets: macOSDeploymentTarget,
    infoPlist: .file(path: "App/Resources/Info.plist"),
    sources: ["App/Sources/**"],
    resources: [
        .glob(
            pattern: "App/Resources/**",
            excluding: ["App/Resources/Info.plist", "App/Resources/Offsend.entitlements"]
        )
    ],
    entitlements: "App/Resources/Offsend.entitlements",
    scripts: [
        .post(
            script: """
            set -euo pipefail
            if [ "${ACTION:-}" = "install" ]; then
              echo "Skipping Offsend CLI embedding during archive; release workflow embeds it after archive creation."
              exit 0
            fi
            CLI_BUILT_PRODUCT="${BUILT_PRODUCTS_DIR}/offsend"
            CLI_INSTALLED_PRODUCT="${DSTROOT}/usr/local/bin/offsend"
            if [ -f "$CLI_INSTALLED_PRODUCT" ]; then
              CLI_SRC="$CLI_INSTALLED_PRODUCT"
            else
              CLI_SRC="$CLI_BUILT_PRODUCT"
            fi
            APP_HELPERS="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Helpers"
            CLI_DEST="${APP_HELPERS}/offsend"
            if [ ! -f "$CLI_SRC" ]; then
              echo "error: OffsendCLI product not found at $CLI_SRC" >&2
              exit 1
            fi
            mkdir -p "$APP_HELPERS"
            cp -f "$CLI_SRC" "$CLI_DEST"
            chmod +x "$CLI_DEST"
            if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
              /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --options runtime --timestamp "$CLI_DEST"
            fi
            echo "Embedded offsend CLI at $CLI_DEST"
            """,
            name: "Embed Offsend CLI",
            inputPaths: [
                "$(BUILT_PRODUCTS_DIR)/offsend",
                "$(DSTROOT)/usr/local/bin/offsend"
            ],
            outputPaths: ["$(BUILT_PRODUCTS_DIR)/$(WRAPPER_NAME)/Contents/Helpers/offsend"],
            basedOnDependencyAnalysis: false
        )
    ],
    dependencies: [
        .target(name: "LicenseCore"),
        .target(name: "DetectionCore"),
        .target(name: "AIDetectionCore"),
        .target(name: "DocumentCore"),
        .target(name: "MaskingCore"),
        .target(name: "RiskScoringCore"),
        .target(name: "WorkspacePolicyCore"),
        .target(name: "StorageCore"),
        .target(name: "ClipboardService"),
        .target(name: "WorkspaceWatchService"),
        .target(name: "PasteService"),
        .target(name: "HotkeyService"),
        .target(name: "PermissionsService"),
        .target(name: "AnalyticsCore"),
        .target(name: "AppUIKit"),
        .target(name: "OffsendRuntime"),
        .target(name: "OffsendCLI"),
        .package(product: "Sparkle")
    ],
    settings: .settings(
        base: [
            "PRODUCT_NAME": "\(appName)",
            "MARKETING_VERSION": "\(appMarketingVersion)",
            "CURRENT_PROJECT_VERSION": "\(appBuildNumber)",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "TELEMETRYDECK_APP_ID": ""
        ],
        configurations: [
            .debug(name: .debug),
            .release(
                name: .release,
                settings: [
                    "CODE_SIGN_IDENTITY": "Developer ID Application",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                    "SWIFT_OPTIMIZATION_LEVEL": "-Osize",
                    "SWIFT_WHOLE_MODULE_OPTIMIZATION": "YES",
                ]
            )
        ],
        defaultSettings: .recommended
    )
)

let testTargets: [Target] = [
    .target(
        name: "DetectionCoreTests",
        destinations: .macOS,
        product: .unitTests,
        bundleId: "\(bundlePrefix).detectioncore.tests",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/DetectionCore/Tests/**"],
        dependencies: [.target(name: "DetectionCore")]
    ),
    .target(
        name: "AIDetectionCoreTests",
        destinations: .macOS,
        product: .unitTests,
        bundleId: "\(bundlePrefix).aidetectioncore.tests",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/AIDetectionCore/Tests/**"],
        dependencies: [
            .target(name: "AIDetectionCore"),
            .target(name: "DetectionCore")
        ]
    ),
    .target(
        name: "MaskingCoreTests",
        destinations: .macOS,
        product: .unitTests,
        bundleId: "\(bundlePrefix).maskingcore.tests",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/MaskingCore/Tests/**"],
        dependencies: [
            .target(name: "DetectionCore"),
            .target(name: "MaskingCore")
        ]
    ),
    .target(
        name: "RiskScoringCoreTests",
        destinations: .macOS,
        product: .unitTests,
        bundleId: "\(bundlePrefix).riskscoringcore.tests",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/RiskScoringCore/Tests/**"],
        dependencies: [
            .target(name: "DetectionCore"),
            .target(name: "RiskScoringCore")
        ]
    ),
    .target(
        name: "LicenseCoreTests",
        destinations: .macOS,
        product: .unitTests,
        bundleId: "\(bundlePrefix).licensecore.tests",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/LicenseCore/Tests/**"],
        dependencies: [.target(name: "LicenseCore")]
    ),
    .target(
        name: "WorkspacePolicyCoreTests",
        destinations: .macOS,
        product: .unitTests,
        bundleId: "\(bundlePrefix).workspacepolicycore.tests",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/WorkspacePolicyCore/Tests/**"],
        dependencies: [.target(name: "WorkspacePolicyCore")]
    ),
    .target(
        name: "AnalyticsCoreTests",
        destinations: .macOS,
        product: .unitTests,
        bundleId: "\(bundlePrefix).analyticscore.tests",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/AnalyticsCore/Tests/**"],
        dependencies: [
            .target(name: "AnalyticsCore"),
            .target(name: "MaskingCore")
        ]
    ),
    .target(
        name: "StorageCoreTests",
        destinations: .macOS,
        product: .unitTests,
        bundleId: "\(bundlePrefix).storagecore.tests",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/StorageCore/Tests/**"],
        dependencies: [.target(name: "StorageCore")]
    ),
    .target(
        name: "WorkspaceWatchServiceTests",
        destinations: .macOS,
        product: .unitTests,
        bundleId: "\(bundlePrefix).workspacewatchservice.tests",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/WorkspaceWatchService/Tests/**"],
        dependencies: [.target(name: "WorkspaceWatchService")]
    ),
    .target(
        name: "OffsendRuntimeTests",
        destinations: .macOS,
        product: .unitTests,
        bundleId: "\(bundlePrefix).offsendruntime.tests",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/OffsendRuntime/Tests/**"],
        dependencies: [.target(name: "OffsendRuntime")]
    ),
    .target(
        name: "DocumentCoreTests",
        destinations: .macOS,
        product: .unitTests,
        bundleId: "\(bundlePrefix).documentcore.tests",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/DocumentCore/Tests/**"],
        dependencies: [
            .target(name: "DocumentCore"),
            .target(name: "DetectionCore"),
            .target(name: "MaskingCore"),
            .target(name: "RiskScoringCore")
        ]
    )
]

let project = Project(
    name: appName,
    organizationName: "Offsend",
    options: .options(automaticSchemesOptions: .enabled()),
    packages: externalPackages,
    targets: [appTarget] + coreTargets + cliTargets + serviceTargets + uiTargets + testTargets,
    resourceSynthesizers: [
        .strings(parserOptions: ["separator": "/"]),
        .assets(),
        .plists(),
        .fonts()
    ]
)
