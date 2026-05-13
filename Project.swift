import ProjectDescription

let appName = "Offsend"
let appMarketingVersion = "0.0.2"
let appBuildNumber = "1"
let bundlePrefix = "io.offsend"
let macOSDeploymentTarget: DeploymentTargets = .macOS("13.0")

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
        sources: ["Core/LicenseCore/Sources/**"]
    ),
    .target(
        name: "DetectionCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).detectioncore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/DetectionCore/Sources/**"]
    ),
    .target(
        name: "MaskingCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).maskingcore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/MaskingCore/Sources/**"],
        resources: ["Core/MaskingCore/Resources/**"],
        dependencies: [.target(name: "DetectionCore")]
    ),
    .target(
        name: "RiskScoringCore",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).riskscoringcore",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Core/RiskScoringCore/Sources/**"],
        dependencies: [.target(name: "DetectionCore")]
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
        ]
    )
]

let serviceTargets: [Target] = [
    .target(
        name: "ClipboardService",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).clipboardservice",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/ClipboardService/Sources/**"]
    ),
    .target(
        name: "PasteService",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).pasteservice",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/PasteService/Sources/**"]
    ),
    .target(
        name: "HotkeyService",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).hotkeyservice",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/HotkeyService/Sources/**"],
        dependencies: [.package(product: "KeyboardShortcuts")]
    ),
    .target(
        name: "PermissionsService",
        destinations: .macOS,
        product: .framework,
        bundleId: "\(bundlePrefix).permissionsservice",
        deploymentTargets: macOSDeploymentTarget,
        sources: ["Services/PermissionsService/Sources/**"]
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
        ]
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
        resources: ["AppUIKit/Resources/**"]
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
        .target(name: "StorageCore"),
        .target(name: "ClipboardService"),
        .target(name: "PasteService"),
        .target(name: "HotkeyService"),
        .target(name: "PermissionsService"),
        .target(name: "AnalyticsCore"),
        .target(name: "AppUIKit"),
        .package(product: "Sparkle")
    ],
    settings: .settings(base: [
        "PRODUCT_NAME": "\(appName)",
        "MARKETING_VERSION": "\(appMarketingVersion)",
        "CURRENT_PROJECT_VERSION": "\(appBuildNumber)",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "SWIFT_STRICT_CONCURRENCY": "complete"
    ])
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
