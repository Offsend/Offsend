import Foundation

/// Marketing version baked into the binary's Info.plist section
/// (`CREATE_INFOPLIST_SECTION_IN_BINARY`), readable regardless of how the
/// executable was invoked (argv[0] may be a bare name from PATH lookup).
enum CLIVersion {
    static let marketing: String = {
        if let version = CLIVersionRelease.marketing, !version.isEmpty {
            return version
        }
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }
        return "0.0.0"
    }()
}
