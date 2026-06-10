import XCTest
@testable import DetectionCore

final class AIModelRegistryTests: XCTestCase {
    func testDetectThrowsWhenModelIsNotLoaded() async {
        let registry = AIModelRegistry()

        do {
            _ = try await registry.detect(text: "hello", options: .default)
            XCTFail("Expected modelNotLoaded error")
        } catch {
            XCTAssertEqual(error as? AIModelRuntimeError, .modelNotLoaded)
        }
    }

    func testDetectRejectsMismatchedSelectedModelID() async throws {
        let registry = AIModelRegistry(makeRunner: { _ in StubRunner() })
        try await registry.load(
            model: Self.makeModel(id: "model-a"),
            directory: URL(fileURLWithPath: "/tmp")
        )

        var options = DetectionOptions()
        options.selectedAIModelID = "model-b"
        do {
            _ = try await registry.detect(text: "hello", options: options)
            XCTFail("Expected modelNotLoaded for a stale runner")
        } catch {
            XCTAssertEqual(error as? AIModelRuntimeError, .modelNotLoaded)
        }

        options.selectedAIModelID = "model-a"
        let entities = try await registry.detect(text: "hello", options: options)
        XCTAssertTrue(entities.isEmpty)
    }

    func testConcurrentLoadsAreSerialized() async throws {
        let probe = LoadProbe()
        let registry = AIModelRegistry(makeRunner: { _ in StubRunner(probe: probe) })
        let directory = URL(fileURLWithPath: "/tmp")

        async let first: Void = registry.load(model: Self.makeModel(id: "model-a"), directory: directory)
        async let second: Void = registry.load(model: Self.makeModel(id: "model-b"), directory: directory)
        _ = try await (first, second)

        let maxConcurrent = await probe.maxConcurrent
        XCTAssertEqual(maxConcurrent, 1, "Two parallel loads must never run their side effects concurrently")
    }

    private static func makeModel(id: String) -> InstalledAIModel {
        InstalledAIModel(
            id: id,
            displayName: id,
            source: .ollama(endpoint: URL(string: "http://127.0.0.1:11434")!, modelName: id),
            format: .ollamaAPI,
            localDirectoryName: id
        )
    }
}

private actor LoadProbe {
    private var active = 0
    private(set) var maxConcurrent = 0

    func begin() {
        active += 1
        maxConcurrent = max(maxConcurrent, active)
    }

    func end() {
        active -= 1
    }
}

private final class StubRunner: AIModelRunning, @unchecked Sendable {
    let format: AIModelFormat = .ollamaAPI
    private let probe: LoadProbe?

    init(probe: LoadProbe? = nil) {
        self.probe = probe
    }

    func load(bundle: AIModelBundle) async throws {
        guard let probe else { return }
        await probe.begin()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await probe.end()
    }

    func detect(text: String, options: DetectionOptions) async throws -> [SensitiveEntity] {
        []
    }

    func unload() {}
}
