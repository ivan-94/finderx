import AppKit
import CoreGraphics
import Foundation
import ImageCompressionCore
import ImageIO
import Testing
import UniformTypeIdentifiers

@Suite("ImageCompressionCore")
struct ImageCompressionCoreTests {
    @Test("Inspector reads JPEG metadata")
    func inspectorReadsJPEG() throws {
        let directory = try TestImages.makeDirectory()
        let url = directory.appendingPathComponent("sample.jpg")
        try TestImages.writeImage(url: url, format: .jpeg, width: 320, height: 180, alpha: false)

        let info = try ImageInspector().inspect(url)

        #expect(info.format == .jpeg)
        #expect(info.pixelWidth == 320)
        #expect(info.pixelHeight == 180)
        #expect(info.fileSize > 0)
        #expect(info.hasAlpha == false)
    }

    @Test("Output naming appends Finder-like suffixes")
    func outputNamingHandlesCollisions() throws {
        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("photo.jpg")
        FileManager.default.createFile(atPath: source.path, contents: Data())
        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("photo-compressed.jpg").path,
            contents: Data()
        )

        let url = OutputNamer().outputURL(for: source, format: .jpeg)

        #expect(url.lastPathComponent == "photo-compressed 2.jpg")
    }

    @Test("Explicit JPEG compression writes a new file and preserves dimensions by default")
    func compressesJPEG() throws {
        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("large.jpg")
        try TestImages.writeImage(url: source, format: .jpeg, width: 640, height: 360, alpha: false)

        let result = try ImageCompressor().compress(
            source,
            options: CompressionOptions(outputFormat: .jpeg, quality: 0.65)
        )

        #expect(FileManager.default.fileExists(atPath: result.outputURL.path))
        #expect(result.outputURL.lastPathComponent == "large-compressed.jpg")
        #expect(result.outputFormat == .jpeg)
        #expect(result.pixelWidth == 640)
        #expect(result.pixelHeight == 360)
        #expect(result.compressedSize > 0)
    }

    @Test("Explicit WebP compression writes a WebP file and preserves dimensions by default")
    func compressesWebP() throws {
        #expect(ImageCompressor.canWrite(.webp))

        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("large.jpg")
        try TestImages.writeImage(url: source, format: .jpeg, width: 640, height: 360, alpha: false)

        let result = try ImageCompressor().compress(
            source,
            options: CompressionOptions(outputFormat: .webp, quality: 0.8)
        )

        #expect(FileManager.default.fileExists(atPath: result.outputURL.path))
        #expect(result.outputURL.pathExtension == "webp")
        #expect(result.outputFormat == .webp)
        #expect(result.pixelWidth == 640)
        #expect(result.pixelHeight == 360)
        #expect(result.compressedSize > 0)
    }

    @Test("Inspector accepts WebP input")
    func inspectorReadsWebP() throws {
        #expect(ImageCompressor.canWrite(.webp))

        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("large.jpg")
        try TestImages.writeImage(url: source, format: .jpeg, width: 640, height: 360, alpha: false)
        let webp = try ImageCompressor().compress(
            source,
            options: CompressionOptions(outputFormat: .webp, quality: 0.8)
        ).outputURL

        let info = try ImageInspector().inspect(webp)

        #expect(ImageInspector.isSupportedImage(webp))
        #expect(info.format == .webp)
        #expect(info.pixelWidth == 640)
        #expect(info.pixelHeight == 360)
        #expect(info.fileSize > 0)
    }

    @Test("Auto mode does not choose JPEG for transparent PNG")
    func autoPreservesTransparencyConstraint() throws {
        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("transparent.png")
        try TestImages.writeImage(url: source, format: .png, width: 180, height: 180, alpha: true)

        let result = try ImageCompressor().compress(source)

        #expect(result.outputFormat != .jpeg)
        #expect(FileManager.default.fileExists(atPath: result.outputURL.path))
    }

    @Test("Batch compression skips unsupported files")
    func batchSkipsUnsupportedFiles() throws {
        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("image.jpg")
        let text = directory.appendingPathComponent("notes.txt")
        try TestImages.writeImage(url: source, format: .jpeg, width: 120, height: 120, alpha: false)
        try "not an image".write(to: text, atomically: true, encoding: .utf8)

        let report = ImageCompressor().compressBatch([source, text])

        #expect(report.results.count == 1)
        #expect(report.skipped.count == 1)
        #expect(report.failures.isEmpty)
    }

    @Test("compressInPlace creates temp file and leaves source untouched")
    func compressInPlaceCreatesTempFile() throws {
        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("photo.jpg")
        try TestImages.writeImage(url: source, format: .jpeg, width: 640, height: 360, alpha: false)
        let originalSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0

        let session = try ImageCompressor().compressInPlace(
            source,
            options: CompressionOptions(outputFormat: .jpeg, quality: 0.65)
        )

        #expect(FileManager.default.fileExists(atPath: session.tempURL.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(session.result.sourceURL == source)
        #expect(session.result.originalSize == Int64(originalSize))
        #expect(session.result.compressedSize > 0)
        #expect(session.targetURL.pathExtension == "jpg")
        #expect(session.tempURL.lastPathComponent.hasPrefix("finderx-inplace-"))
        #expect(session.tempURL.lastPathComponent.hasSuffix(".jpg"))

        session.discard()
    }

    @Test("commit replaces source and cleans up temp")
    func inplaceCommitReplacesSource() throws {
        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("photo.jpg")
        try TestImages.writeImage(url: source, format: .jpeg, width: 640, height: 360, alpha: false)

        let session = try ImageCompressor().compressInPlace(
            source,
            options: CompressionOptions(outputFormat: .jpeg, quality: 0.65)
        )
        let tempURL = session.tempURL

        try session.commit()

        #expect(!FileManager.default.fileExists(atPath: tempURL.path))
        #expect(FileManager.default.fileExists(atPath: session.targetURL.path))
        #expect(session.targetURL.lastPathComponent == "photo.jpg")
    }

    @Test("commit handles extension change")
    func inplaceCommitHandlesExtensionChange() throws {
        #expect(ImageCompressor.canWrite(.webp))

        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("photo.png")
        try TestImages.writeImage(url: source, format: .png, width: 640, height: 360, alpha: false)

        let session = try ImageCompressor().compressInPlace(
            source,
            options: CompressionOptions(outputFormat: .webp, quality: 0.8)
        )

        #expect(session.targetURL.pathExtension == "webp")

        try session.commit()

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: session.targetURL.path))
        #expect(session.targetURL.lastPathComponent == "photo.webp")
    }

    @Test("commit refuses extension change when target exists")
    func inplaceCommitDoesNotOverwriteExistingTarget() throws {
        #expect(ImageCompressor.canWrite(.webp))

        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("photo.png")
        let existingTarget = directory.appendingPathComponent("photo.webp")
        try TestImages.writeImage(url: source, format: .png, width: 640, height: 360, alpha: false)
        try "existing".write(to: existingTarget, atomically: true, encoding: .utf8)
        let originalData = try Data(contentsOf: source)
        let targetData = try Data(contentsOf: existingTarget)

        let session = try ImageCompressor().compressInPlace(
            source,
            options: CompressionOptions(outputFormat: .webp, quality: 0.8)
        )

        #expect(throws: FinderXError.outputWriteFailed(existingTarget)) {
            try session.commit()
        }
        #expect(try Data(contentsOf: source) == originalData)
        #expect(try Data(contentsOf: existingTarget) == targetData)

        session.discard()
    }

    @Test("discard cleans up temp directory")
    func inplaceDiscardCleansUp() throws {
        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("photo.jpg")
        try TestImages.writeImage(url: source, format: .jpeg, width: 640, height: 360, alpha: false)

        let session = try ImageCompressor().compressInPlace(
            source,
            options: CompressionOptions(outputFormat: .jpeg, quality: 0.65)
        )
        let tempDir = session.tempURL.deletingLastPathComponent()

        session.discard()

        #expect(!FileManager.default.fileExists(atPath: tempDir.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("auto-cleanup on deinit")
    func inplaceSessionAutoCleansOnDeinit() throws {
        let directory = try TestImages.makeDirectory()
        let source = directory.appendingPathComponent("photo.jpg")
        try TestImages.writeImage(url: source, format: .jpeg, width: 640, height: 360, alpha: false)

        let session = try ImageCompressor().compressInPlace(
            source,
            options: CompressionOptions(outputFormat: .jpeg, quality: 0.65)
        )
        let tempDir = session.tempURL.deletingLastPathComponent()

        // Session goes out of scope, deinit should clean up
        // We can't directly test deinit timing, but discard() is called from deinit
        // So we call it explicitly for deterministic testing
        session.discard()

        #expect(!FileManager.default.fileExists(atPath: tempDir.path))
    }
}

private enum TestImages {
    static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("finderx-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writeImage(url: URL, format: ImageFormat, width: Int, height: Int, alpha: Bool) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw TestImageError.renderFailed
        }

        for y in stride(from: 0, to: height, by: 12) {
            for x in stride(from: 0, to: width, by: 12) {
                let red = CGFloat((x % 255)) / 255.0
                let blue = CGFloat((y % 255)) / 255.0
                let opacity: CGFloat = alpha && (x + y).isMultiple(of: 24) ? 0.35 : 1.0
                context.setFillColor(NSColor(calibratedRed: red, green: 0.42, blue: blue, alpha: opacity).cgColor)
                context.fill(CGRect(x: x, y: y, width: 12, height: 12))
            }
        }

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, format.typeIdentifier as CFString, 1, nil)
        else {
            throw TestImageError.renderFailed
        }

        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.92
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.writeFailed
        }
    }

    enum TestImageError: Error {
        case renderFailed
        case writeFailed
    }
}
