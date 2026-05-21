import ProjectDescription

let appName = "Offsend"
let appMarketingVersion = "0.0.4"
let appBuildNumber = "2"
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
    .remote(url: "https://github.com/sindresorhus/KeyboardShortcuts", requirement: .upToNextMajor(from: "2.3.0")),
    .remote(url: "https://github.com/stephencelis/SQLite.swift", requirement: .upToNextMajor(from: "0.15.0")),
    .remote(url: "https://github.com/sparkle-project/Sparkle", requirement: .upToNextMajor(from: "2.6.0"))
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
        name: "AnalyticsCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).analyticscore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/AnalyticsCore/Sources/**"],
        dependencies: [
            .target(name: "DetectionCore"),
            .target(name: "StorageCore")
        ],
        settings: developerIDReleaseSigning
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
    dependencies: [
        .target(name: "LicenseCore"),
        .target(name: "DetectionCore"),
        .target(name: "MaskingCore"),
        .target(name: "RiskScoringCore"),
        .target(name: "WorkspacePolicyCore"),
        .target(name: "StorageCore"),
        .target(name: "ClipboardService"),
        .target(name: "PasteService"),
        .target(name: "HotkeyService"),
        .target(name: "PermissionsService"),
        .target(name: "AnalyticsCore"),
        .target(name: "AppUIKit"),
        .package(product: "Sparkle")
    ],
    settings: .settings(
        base: [
            "PRODUCT_NAME": "\(appName)",
            "MARKETING_VERSION": "\(appMarketingVersion)",
            "CURRENT_PROJECT_VERSION": "\(appBuildNumber)",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "SWIFT_STRICT_CONCURRENCY": "complete"
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
    )
]

let project = Project(
    name: appName,
    organizationName: "Offsend",
    options: .options(automaticSchemesOptions: .enabled()),
    packages: externalPackages,
    targets: [appTarget] + coreTargets + serviceTargets + uiTargets + testTargets,
    resourceSynthesizers: [
        .strings(parserOptions: ["separator": "/"]),
        .assets(),
        .plists(),
        .fonts()
    ]
)
