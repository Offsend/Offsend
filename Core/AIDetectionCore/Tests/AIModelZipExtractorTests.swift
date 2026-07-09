import XCTest
import DetectionCore
@testable import AIDetectionCore

final class AIModelZipExtractorTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testExtractRejectsTraversalEntriesBeforeWriting() throws {
        let archiveURL = tempRoot.appendingPathComponent("slip.zip")
        try createZip(
            at: archiveURL,
            entries: [
                ("../../escape.txt", Data("pwned".utf8)),
                ("model.onnx", Data("ok".utf8)),
            ]
        )

        let destination = tempRoot.appendingPathComponent("Models/poc", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        XCTAssertThrowsError(try AIModelZipExtractor.extract(from: archiveURL, into: destination)) { error in
            guard let catalogError = error as? AIModelCatalogError,
                  case .importFailed(let message) = catalogError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("escapes the model directory"), message)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("escape.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("model.onnx").path))
    }

    func testExtractAllowsSafeNestedEntries() throws {
        let archiveURL = tempRoot.appendingPathComponent("safe.zip")
        try createZip(
            at: archiveURL,
            entries: [
                ("onnx/model.onnx", Data("weights".utf8)),
                ("tokenizer.json", Data("{}".utf8)),
            ]
        )

        let destination = tempRoot.appendingPathComponent("Models/safe", isDirectory: true)
        try AIModelZipExtractor.extract(from: archiveURL, into: destination)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: destination.appendingPathComponent("onnx/model.onnx").path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: destination.appendingPathComponent("tokenizer.json").path)
        )
    }

    private func createZip(at url: URL, entries: [(String, Data)]) throws {
        // Minimal ZIP writer (stored / no compression) so tests do not need third-party deps.
        var centralDirectory = Data()
        var localFiles = Data()
        var offset: UInt32 = 0

        for (name, payload) in entries {
            let nameData = Data(name.utf8)
            let crc = crc32(payload)
            let size = UInt32(payload.count)

            var local = Data()
            local.append(contentsOf: [0x50, 0x4b, 0x03, 0x04]) // local file header
            local.appendUInt16(20) // version needed
            local.appendUInt16(0) // flags
            local.appendUInt16(0) // compression: store
            local.appendUInt16(0) // mod time
            local.appendUInt16(0) // mod date
            local.appendUInt32(crc)
            local.appendUInt32(size)
            local.appendUInt32(size)
            local.appendUInt16(UInt16(nameData.count))
            local.appendUInt16(0) // extra length
            local.append(nameData)
            local.append(payload)

            var central = Data()
            central.append(contentsOf: [0x50, 0x4b, 0x01, 0x02]) // central directory header
            central.appendUInt16(20) // version made by
            central.appendUInt16(20) // version needed
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(nameData.count))
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(offset)
            central.append(nameData)

            localFiles.append(local)
            centralDirectory.append(central)
            offset += UInt32(local.count)
        }

        var end = Data()
        end.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])
        end.appendUInt16(0)
        end.appendUInt16(0)
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt32(UInt32(centralDirectory.count))
        end.appendUInt32(UInt32(localFiles.count))
        end.appendUInt16(0)

        try (localFiles + centralDirectory + end).write(to: url)
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = UInt32(bitPattern: -Int32(crc & 1))
                crc = (crc >> 1) ^ (0xedb8_8320 & mask)
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
