import Foundation

/// Availability of the statically linked `offsend_ffi` library.
public enum OffsendRustBridge {
    /// Always `true` when this framework is linked (static `liboffsend_ffi.a`).
    public static var isAvailable: Bool { true }
}

enum RustFFIError: Error, LocalizedError, Equatable {
    case nullResult(String)
    case invalidUTF8
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .nullResult(let message):
            return message.isEmpty ? "Offsend FFI returned null" : message
        case .invalidUTF8:
            return "Offsend FFI returned non-UTF-8 data"
        case .decodingFailed(let message):
            return "Offsend FFI JSON decode failed: \(message)"
        }
    }
}

enum RustFFI {
    static func call(
        _ body: (_ errOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> UnsafeMutablePointer<CChar>?
    ) throws -> String {
        var errPtr: UnsafeMutablePointer<CChar>?
        let resultPtr = body(&errPtr)
        defer {
            if let errPtr {
                offsend_string_free(errPtr)
            }
            if let resultPtr {
                offsend_string_free(resultPtr)
            }
        }

        if let resultPtr {
            guard let json = String(validatingUTF8: resultPtr) else {
                throw RustFFIError.invalidUTF8
            }
            return json
        }

        let message: String
        if let errPtr, let err = String(validatingUTF8: errPtr) {
            message = err
        } else {
            message = "unknown FFI error"
        }
        throw RustFFIError.nullResult(message)
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            throw RustFFIError.decodingFailed(String(describing: error))
        }
    }
}

// C ABI from liboffsend_ffi.a — declared here so we don't depend on a clang
// module map (Tuist framework + SWIFT_INCLUDE_PATHS was brittle / duplicated).
@_silgen_name("offsend_detect_scan")
func offsend_detect_scan(
    _ text: UnsafePointer<CChar>?,
    _ optionsJSONOrNull: UnsafePointer<CChar>?,
    _ errOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("offsend_privacy_audit")
func offsend_privacy_audit(
    _ directoryPath: UnsafePointer<CChar>?,
    _ optionsJSONOrNull: UnsafePointer<CChar>?,
    _ errOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("offsend_privacy_fix")
func offsend_privacy_fix(
    _ directoryPath: UnsafePointer<CChar>?,
    _ selectionJSONOrNull: UnsafePointer<CChar>?,
    _ optionsJSONOrNull: UnsafePointer<CChar>?,
    _ errOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("offsend_seal_spans")
func offsend_seal_spans(
    _ key: UnsafePointer<UInt8>?,
    _ keyLen: Int,
    _ text: UnsafePointer<CChar>?,
    _ spansJSON: UnsafePointer<CChar>?,
    _ maxPlaintextBytes: Int,
    _ errOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("offsend_unseal_text")
func offsend_unseal_text(
    _ key: UnsafePointer<UInt8>?,
    _ keyLen: Int,
    _ text: UnsafePointer<CChar>?,
    _ errOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("offsend_mask_text")
func offsend_mask_text(
    _ text: UnsafePointer<CChar>?,
    _ entitiesJSON: UnsafePointer<CChar>?,
    _ errOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("offsend_restore_text")
func offsend_restore_text(
    _ text: UnsafePointer<CChar>?,
    _ mappingJSON: UnsafePointer<CChar>?,
    _ errOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("offsend_risk_assess")
func offsend_risk_assess(
    _ entityTypesJSON: UnsafePointer<CChar>?,
    _ contextOrNull: UnsafePointer<CChar>?,
    _ errOut: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("offsend_string_free")
func offsend_string_free(_ ptr: UnsafeMutablePointer<CChar>?)
