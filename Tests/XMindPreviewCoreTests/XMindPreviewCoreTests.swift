import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import XMindPreviewCore

@Suite("XMindPreviewCore")
struct XMindPreviewCoreTests {
    @Test
    func extractsPNGThumbnail() throws {
        let url = try makeXMindArchive(entries: [
            "Thumbnails/thumbnail.png": tinyPNG()
        ])

        let thumbnail = try #require(XMindThumbnailExtractor.extractThumbnail(from: url))

        #expect(thumbnail.contentTypeIdentifier == "public.png")
        #expect(thumbnail.pixelSize.width == 1)
        #expect(thumbnail.pixelSize.height == 1)
        #expect(thumbnail.sourcePath == "Thumbnails/thumbnail.png")
    }

    @Test
    func extractsJPEGThumbnailCandidate() throws {
        let url = try makeXMindArchive(entries: [
            "Thumbnails/thumbnail.jpg": try tinyJPEG()
        ])

        let thumbnail = try #require(XMindThumbnailExtractor.extractThumbnail(from: url))

        #expect(thumbnail.contentTypeIdentifier == "public.jpeg")
        #expect(thumbnail.pixelSize.width == 1)
        #expect(thumbnail.pixelSize.height == 1)
        #expect(thumbnail.sourcePath == "Thumbnails/thumbnail.jpg")
    }

    @Test
    func returnsNilWhenThumbnailIsMissing() throws {
        let url = try makeXMindArchive(entries: [
            "content.json": Data("{}".utf8)
        ])

        #expect(XMindThumbnailExtractor.extractThumbnail(from: url) == nil)
    }

    @Test
    func returnsNilForDamagedZip() throws {
        let url = temporaryURL(extension: "xmind")
        try Data("not a zip".utf8).write(to: url)

        #expect(XMindThumbnailExtractor.extractThumbnail(from: url) == nil)
    }

    @Test
    func ignoresNonXMindExtension() throws {
        let url = try makeXMindArchive(
            extension: "zip",
            entries: ["Thumbnails/thumbnail.png": tinyPNG()]
        )

        #expect(XMindThumbnailExtractor.extractThumbnail(from: url) == nil)
    }

    private func makeXMindArchive(
        extension pathExtension: String = "xmind",
        entries: [String: Data]
    ) throws -> URL {
        let sourceDirectory = temporaryURL(extension: "dir")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        for (path, data) in entries {
            let fileURL = sourceDirectory.appending(path: path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL)
        }

        let archiveURL = temporaryURL(extension: pathExtension)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = sourceDirectory
        process.arguments = ["-q", "-r", archiveURL.path, "."]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        return archiveURL
    }

    private func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "FinderX-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    private func tinyPNG() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
    }

    private func tinyJPEG() throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let pixel = Data([0xFF, 0xFF, 0xFF, 0xFF])
        let provider = CGDataProvider(data: pixel as CFData)!
        let image = CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
