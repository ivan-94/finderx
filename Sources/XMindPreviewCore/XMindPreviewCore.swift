import Compression
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct XMindThumbnail: Equatable {
    public let data: Data
    public let contentTypeIdentifier: String
    public let pixelSize: CGSize
    public let sourcePath: String
}

public enum XMindThumbnailExtractor {
    public static let supportedExtension = "xmind"

    private static let candidatePaths = [
        "thumbnails/thumbnail.png",
        "thumbnails/thumbnail.jpg",
        "thumbnails/thumbnail.jpeg",
        "thumbnails/preview.png",
        "thumbnails/preview.jpg",
        "thumbnails/preview.jpeg"
    ]

    public static func extractThumbnail(from fileURL: URL) -> XMindThumbnail? {
        guard fileURL.pathExtension.lowercased() == supportedExtension else { return nil }
        guard let archive = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else { return nil }
        return extractThumbnail(fromArchiveData: archive)
    }

    public static func extractThumbnail(fromArchiveData archive: Data) -> XMindThumbnail? {
        guard let reader = ZIPReader(data: archive) else { return nil }

        for candidate in candidatePaths {
            guard let entry = reader.entry(namedCaseInsensitively: candidate),
                  let data = reader.data(for: entry),
                  let contentType = contentType(for: entry.name),
                  let size = imageSize(for: data)
            else {
                continue
            }
            return XMindThumbnail(
                data: data,
                contentTypeIdentifier: contentType.identifier,
                pixelSize: size,
                sourcePath: entry.name
            )
        }

        return nil
    }

    private static func contentType(for path: String) -> UTType? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png":
            return .png
        case "jpg", "jpeg":
            return .jpeg
        default:
            return nil
        }
    }

    private static func imageSize(for data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0,
              height > 0
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}

private struct ZIPEntry {
    let name: String
    let compressionMethod: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}

private struct ZIPReader {
    private let data: Data
    private let entries: [ZIPEntry]

    init?(data: Data) {
        self.data = data
        guard let entries = ZIPReader.readCentralDirectory(from: data) else { return nil }
        self.entries = entries
    }

    func entry(namedCaseInsensitively name: String) -> ZIPEntry? {
        let normalizedName = name.lowercased()
        return entries.first { $0.name.lowercased() == normalizedName }
    }

    func data(for entry: ZIPEntry) -> Data? {
        guard entry.localHeaderOffset >= 0,
              entry.localHeaderOffset + 30 <= data.count,
              data.uint32LE(at: entry.localHeaderOffset) == 0x0403_4B50
        else {
            return nil
        }

        let nameLength = Int(data.uint16LE(at: entry.localHeaderOffset + 26))
        let extraLength = Int(data.uint16LE(at: entry.localHeaderOffset + 28))
        let start = entry.localHeaderOffset + 30 + nameLength + extraLength
        let end = start + entry.compressedSize

        guard start >= 0, end <= data.count, start <= end else { return nil }
        let compressedData = data[start..<end]

        switch entry.compressionMethod {
        case 0:
            return Data(compressedData)
        case 8:
            return inflate(compressedData, expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    private func inflate(_ compressedData: Data.SubSequence, expectedSize: Int) -> Data? {
        guard expectedSize >= 0 else { return nil }
        if expectedSize == 0 { return Data() }

        var output = Data(count: expectedSize)
        let decodedCount = output.withUnsafeMutableBytes { outputBuffer in
            compressedData.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    outputBuffer.count,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    compressedData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard decodedCount == expectedSize else { return nil }
        return output
    }

    private static func readCentralDirectory(from data: Data) -> [ZIPEntry]? {
        guard let eocdOffset = findEndOfCentralDirectory(in: data),
              eocdOffset + 22 <= data.count,
              data.uint16LE(at: eocdOffset + 8) == data.uint16LE(at: eocdOffset + 10)
        else {
            return nil
        }

        let entryCount = Int(data.uint16LE(at: eocdOffset + 10))
        let centralDirectorySize = Int(data.uint32LE(at: eocdOffset + 12))
        let centralDirectoryOffset = Int(data.uint32LE(at: eocdOffset + 16))
        guard centralDirectoryOffset >= 0,
              centralDirectorySize >= 0,
              centralDirectoryOffset + centralDirectorySize <= data.count
        else {
            return nil
        }

        var entries: [ZIPEntry] = []
        var offset = centralDirectoryOffset

        for _ in 0..<entryCount {
            guard offset + 46 <= data.count,
                  data.uint32LE(at: offset) == 0x0201_4B50
            else {
                return nil
            }

            let compressionMethod = data.uint16LE(at: offset + 10)
            let compressedSize = Int(data.uint32LE(at: offset + 20))
            let uncompressedSize = Int(data.uint32LE(at: offset + 24))
            let nameLength = Int(data.uint16LE(at: offset + 28))
            let extraLength = Int(data.uint16LE(at: offset + 30))
            let commentLength = Int(data.uint16LE(at: offset + 32))
            let localHeaderOffset = Int(data.uint32LE(at: offset + 42))
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength

            guard nameEnd <= data.count,
                  let name = String(data: data[nameStart..<nameEnd], encoding: .utf8)
            else {
                return nil
            }

            entries.append(
                ZIPEntry(
                    name: name,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )

            offset = nameEnd + extraLength + commentLength
        }

        return entries
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }

        let minimumOffset = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= minimumOffset {
            if data.uint32LE(at: offset) == 0x0605_4B50 {
                let commentLength = Int(data.uint16LE(at: offset + 20))
                if offset + 22 + commentLength == data.count {
                    return offset
                }
            }
            offset -= 1
        }
        return nil
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
