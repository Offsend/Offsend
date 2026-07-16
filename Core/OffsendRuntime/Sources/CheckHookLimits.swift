import Foundation

public enum CheckHookLimits {
    /// Max UTF-8 bytes accepted on stdin for `--stdin` / `--adapter` (DoS guard).
    public static let maxStdinBytes = 2 * 1024 * 1024

    /// Recommended hook timeout (seconds) for editor configs.
    /// Cold-start of the CLI can exceed 10s; Claude/Cursor fail-open on timeout.
    public static let recommendedTimeoutSeconds = 30
}
