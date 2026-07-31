import Foundation

/// Finds large opaque base64 / hex blobs that may hide secret-shaped plaintext
/// (agent shell stdout → terminal Read exfil). Decode is best-effort; binary
/// payloads and short blobs are ignored.
public enum OpaqueEncodedBlobExtractor {
    /// Minimum base64 alphabet run length before a decode probe.
    public static let minBase64Length = 24
    /// Minimum hex run length before a decode probe.
    public static let minHexLength = 32
    /// CPU bounds. Crossing either bound is an enforcement event, not an allow:
    /// callers deny/withhold instead of letting decoys push a secret out.
    public static let maxBlobsPerText = 128
    public static let maxTotalDecodedBytes = 512_000
    /// Cap decoded byte size per blob.
    public static let maxDecodedBytes = 64_000

    public struct Blob: Equatable, Sendable {
        /// Range in the source text covering the encoded run.
        public let range: Range<String.Index>
        /// UTF-8 payload after decode (only when the bytes are valid UTF-8 text).
        public let decodedUTF8: String
    }

    public struct Extraction: Equatable, Sendable {
        public let blobs: [Blob]
        public let exceededSafetyBudget: Bool
    }

    /// Returns decodeable UTF-8 payloads. If the bounded probe budget is
    /// exceeded, `exceededSafetyBudget` is true and callers must fail closed.
    public static func extract(in text: String) -> Extraction {
        var blobs: [Blob] = []
        blobs.append(contentsOf: base64Candidates(in: text))
        blobs.append(contentsOf: wrappedBase64Candidates(in: text))
        blobs.append(contentsOf: hexCandidates(in: text))

        // Prefer a complete wrapped payload over overlapping line fragments.
        blobs.sort {
            text.distance(from: $0.range.lowerBound, to: $0.range.upperBound)
                > text.distance(from: $1.range.lowerBound, to: $1.range.upperBound)
        }
        var nonOverlapping: [Blob] = []
        for blob in blobs where !nonOverlapping.contains(where: { $0.range.overlaps(blob.range) }) {
            nonOverlapping.append(blob)
        }
        nonOverlapping.sort { $0.range.lowerBound < $1.range.lowerBound }

        var accepted: [Blob] = []
        var decodedBytes = 0
        for blob in nonOverlapping {
            let bytes = blob.decodedUTF8.utf8.count
            if accepted.count >= maxBlobsPerText
                || decodedBytes > maxTotalDecodedBytes - min(bytes, maxTotalDecodedBytes) {
                return Extraction(blobs: accepted, exceededSafetyBudget: true)
            }
            accepted.append(blob)
            decodedBytes += bytes
        }
        return Extraction(blobs: accepted, exceededSafetyBudget: false)
    }

    /// Compatibility convenience for focused extractor callers/tests.
    public static func candidates(in text: String) -> [Blob] {
        extract(in: text).blobs
    }

    private static func base64Candidates(in text: String) -> [Blob] {
        // Lookarounds keep us from clipping mid-token; allow URL-safe alphabet.
        let pattern = #"(?<![A-Za-z0-9+/=_-])[A-Za-z0-9+/_-]{\#(minBase64Length),}={0,2}(?![A-Za-z0-9+/=_-])"#
        return decodeMatches(in: text, pattern: pattern) { raw in
            decodeBase64(raw)
        }
    }

    /// Common `base64` output wraps at fixed columns. Rejoin lines/chunks with
    /// at least 16 alphabet characters; decode validation filters prose/noise.
    private static func wrappedBase64Candidates(in text: String) -> [Blob] {
        let pattern = #"(?<![A-Za-z0-9+/=_-])(?:[A-Za-z0-9+/_-]{16,}[ \t\r\n]+){1,}[A-Za-z0-9+/_-]{4,}={0,2}(?![A-Za-z0-9+/=_-])"#
        return decodeMatches(in: text, pattern: pattern) { raw in
            decodeBase64(raw.filter { !$0.isWhitespace })
        }
    }

    private static func hexCandidates(in text: String) -> [Blob] {
        let pattern = #"(?<![0-9A-Fa-f])(?:[0-9A-Fa-f]{2}){\#(minHexLength / 2),}(?![0-9A-Fa-f])"#
        return decodeMatches(in: text, pattern: pattern) { raw in
            decodeHex(raw)
        }
    }

    private static func decodeMatches(
        in text: String,
        pattern: String,
        decode: (String) -> Data?
    ) -> [Blob] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var blobs: [Blob] = []
        for match in regex.matches(in: text, range: nsRange) {
            guard let range = Range(match.range, in: text) else { continue }
            let raw = String(text[range])
            guard let data = decode(raw),
                  data.count <= maxDecodedBytes,
                  !data.isEmpty,
                  let decoded = String(data: data, encoding: .utf8),
                  isMostlyPrintableText(decoded) else {
                continue
            }
            blobs.append(Blob(range: range, decodedUTF8: decoded))
        }
        return blobs
    }

    /// Reject binary-looking UTF-8 (NUL / heavy controls) so package of random
    /// bytes does not become a decode probe.
    private static func isMostlyPrintableText(_ string: String) -> Bool {
        let scalars = Array(string.unicodeScalars)
        guard !scalars.isEmpty else { return false }
        var printable = 0
        for scalar in scalars {
            if scalar == "\n" || scalar == "\r" || scalar == "\t" {
                printable += 1
                continue
            }
            if CharacterSet.controlCharacters.contains(scalar) {
                continue
            }
            printable += 1
        }
        return printable * 4 >= scalars.count * 3
            && string.contains(where: { !$0.isWhitespace })
    }

    private static func decodeBase64(_ raw: String) -> Data? {
        var normalized = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = normalized.count % 4
        if padding > 0 {
            normalized += String(repeating: "=", count: 4 - padding)
        }
        return Data(base64Encoded: normalized)
    }

    private static func decodeHex(_ raw: String) -> Data? {
        let hex = raw.lowercased()
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        data.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
