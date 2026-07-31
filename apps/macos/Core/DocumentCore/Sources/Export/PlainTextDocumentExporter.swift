import Foundation

public protocol PlainTextDocumentExporting: Sendable {
    func export(_ sanitization: DocumentSanitizationResult, to destinationURL: URL) throws
}

public struct PlainTextDocumentExporter: PlainTextDocumentExporting {
    public init() {}

    public func export(_ sanitization: DocumentSanitizationResult, to destinationURL: URL) throws {
        try sanitization.masking.maskedText.write(to: destinationURL, atomically: true, encoding: .utf8)
    }
}
