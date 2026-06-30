import Foundation

struct AppConfiguration: Sendable {
    let host: String
    let port: Int
    let gitPath: String
    let cloneTimeout: Duration
    let scanWorkDirectory: URL
    let reportStorageDirectory: URL
    let reportTTL: Duration
    let jobWorkers: Int
    let valkeyHost: String?
    let valkeyPort: Int
    let valkeyQueueName: String
    let r2: R2Configuration?
    let toolVersion: String

    struct R2Configuration: Sendable {
        let accountID: String
        let accessKeyID: String
        let secretAccessKey: String
        let bucket: String
        let publicBaseURL: URL?
    }

    static func fromEnvironment() -> AppConfiguration {
        let env = ProcessInfo.processInfo.environment
        let port = Int(env["PORT"] ?? "8080") ?? 8080
        let workRoot = URL(fileURLWithPath: env["SCAN_WORK_DIR"] ?? NSTemporaryDirectory())
            .appendingPathComponent("offsend-scan", isDirectory: true)
        let reportRoot = URL(fileURLWithPath: env["REPORT_STORAGE_DIR"] ?? workRoot.path)
            .appendingPathComponent("reports", isDirectory: true)

        let r2: R2Configuration?
        if let bucket = env["R2_BUCKET"],
           let accountID = env["R2_ACCOUNT_ID"],
           let accessKeyID = env["R2_ACCESS_KEY_ID"],
           let secretAccessKey = env["R2_SECRET_ACCESS_KEY"] {
            let publicBaseURL = env["R2_PUBLIC_BASE_URL"].flatMap { URL(string: $0) }
            r2 = R2Configuration(
                accountID: accountID,
                accessKeyID: accessKeyID,
                secretAccessKey: secretAccessKey,
                bucket: bucket,
                publicBaseURL: publicBaseURL
            )
        } else {
            r2 = nil
        }

        return AppConfiguration(
            host: env["HOST"] ?? "0.0.0.0",
            port: port,
            gitPath: env["GIT_PATH"] ?? "/usr/bin/git",
            cloneTimeout: .seconds(Int64(env["CLONE_TIMEOUT_SECONDS"] ?? "120") ?? 120),
            scanWorkDirectory: workRoot,
            reportStorageDirectory: reportRoot,
            reportTTL: .seconds(Int64(env["REPORT_TTL_SECONDS"] ?? "172800") ?? 172_800),
            jobWorkers: Int(env["JOB_WORKERS"] ?? "2") ?? 2,
            valkeyHost: env["VALKEY_HOST"],
            valkeyPort: Int(env["VALKEY_PORT"] ?? "6379") ?? 6379,
            valkeyQueueName: env["VALKEY_QUEUE_NAME"] ?? "offsend-scan",
            r2: r2,
            toolVersion: env["TOOL_VERSION"] ?? "0.0.0-dev"
        )
    }
}
