import Foundation

/// Thin in-process bridge to `liboffsend_ffi` Check report API.
enum OffsendCheckBridge {
    enum BridgeError: Error, LocalizedError, Equatable {
        case nullResult(String?)
        case invalidUTF8

        var errorDescription: String? {
            switch self {
            case .nullResult(let message):
                message ?? "offsend_check_report returned null"
            case .invalidUTF8:
                "offsend_check_report returned non-UTF8 JSON"
            }
        }
    }

    /// Runs a privacy audit via Rust and returns Check schema JSON (schemaVersion 1).
    static func checkReportJSON(directory: URL, toolVersion: String) throws -> String {
        let path = directory.standardizedFileURL.path
        return try path.withCString { cPath in
            try toolVersion.withCString { cVersion in
                var errPtr: UnsafeMutablePointer<CChar>?
                let raw = offsend_check_report(cPath, cVersion, &errPtr)
                defer {
                    if let errPtr {
                        offsend_string_free(errPtr)
                    }
                }
                guard let raw else {
                    let message = errPtr.flatMap { String(validatingCString: $0) }
                    throw BridgeError.nullResult(message)
                }
                defer { offsend_string_free(raw) }
                guard let json = String(validatingCString: raw) else {
                    throw BridgeError.invalidUTF8
                }
                return json
            }
        }
    }
}

@_silgen_name("offsend_check_report")
func offsend_check_report(
    _ directoryPath: UnsafePointer<CChar>?,
    _ toolVersionOrNull: UnsafePointer<CChar>?,
    _ errOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("offsend_string_free")
func offsend_string_free(_ ptr: UnsafeMutablePointer<CChar>?)
