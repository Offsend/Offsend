public protocol AIModelDetecting: Sendable {
    func detect(text: String, options: DetectionOptions) async throws -> [SensitiveEntity]
}
