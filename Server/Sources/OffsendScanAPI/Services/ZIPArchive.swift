import Foundation

/// Minimal store-only (uncompressed) ZIP writer. Enough to bundle a handful of
/// small text files for download; no compression, encryption, or ZIP64 support.
enum ZIPArchive {
    struct Entry {
        let path: String
        let data: Data

        init(path: String, contents: String) {
            self.path = path
            self.data = Data(contents.utf8)
        }
    }

    static func archive(entries: [Entry]) -> Data {
        var localSection = Data()
        var centralSection = Data()

        for entry in entries {
            let nameBytes = Array(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let localOffset = UInt32(localSection.count)

            var local = Data()
            local.append(le32: 0x0403_4b50) // local file header signature
            local.append(le16: 20)          // version needed to extract
            local.append(le16: 0)           // general purpose flags
            local.append(le16: 0)           // compression method: store
            local.append(le16: 0)           // last mod time
            local.append(le16: 0)           // last mod date
            local.append(le32: crc)
            local.append(le32: size)        // compressed size
            local.append(le32: size)        // uncompressed size
            local.append(le16: UInt16(nameBytes.count))
            local.append(le16: 0)           // extra field length
            local.append(contentsOf: nameBytes)
            local.append(entry.data)
            localSection.append(local)

            var central = Data()
            central.append(le32: 0x0201_4b50) // central directory header signature
            central.append(le16: 20)          // version made by
            central.append(le16: 20)          // version needed to extract
            central.append(le16: 0)           // general purpose flags
            central.append(le16: 0)           // compression method
            central.append(le16: 0)           // last mod time
            central.append(le16: 0)           // last mod date
            central.append(le32: crc)
            central.append(le32: size)        // compressed size
            central.append(le32: size)        // uncompressed size
            central.append(le16: UInt16(nameBytes.count))
            central.append(le16: 0)           // extra field length
            central.append(le16: 0)           // file comment length
            central.append(le16: 0)           // disk number start
            central.append(le16: 0)           // internal file attributes
            central.append(le32: 0)           // external file attributes
            central.append(le32: localOffset)
            central.append(contentsOf: nameBytes)
            centralSection.append(central)
        }

        var result = Data()
        result.append(localSection)
        let centralOffset = UInt32(result.count)
        result.append(centralSection)

        var eocd = Data()
        eocd.append(le32: 0x0605_4b50)              // end of central directory signature
        eocd.append(le16: 0)                        // number of this disk
        eocd.append(le16: 0)                        // disk with start of central directory
        eocd.append(le16: UInt16(entries.count))    // entries on this disk
        eocd.append(le16: UInt16(entries.count))    // total entries
        eocd.append(le32: UInt32(centralSection.count))
        eocd.append(le32: centralOffset)
        eocd.append(le16: 0)                        // comment length
        result.append(eocd)

        return result
    }

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func append(le32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
