/// Overwritten by `Scripts/build_linux_cli.sh` during Linux release builds.
/// Default `nil` keeps local and macOS builds on the Info.plist / fallback path.
enum CLIVersionRelease {
    static let marketing: String? = nil
}
