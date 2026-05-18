import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum FinderXError: Error, LocalizedError, Equatable {
    case unreadableFile(URL)
    case unsupportedInput(URL)
    case imageDecodeFailed(URL)
    case encoderUnavailable(ImageFormat)
    case outputWriteFailed(URL)
    case noViableOutput(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let url):
            "Cannot read \(url.lastPathComponent)."
        case .unsupportedInput(let url):
            "\(url.lastPathComponent) is not a supported JPEG or PNG image."
        case .imageDecodeFailed(let url):
            "Cannot decode \(url.lastPathComponent)."
        case .encoderUnavailable(let format):
            "\(format.displayName) output is not available on this Mac."
        case .outputWriteFailed(let url):
            "Cannot write \(url.lastPathComponent)."
        case .noViableOutput(let url):
            "No valid compressed output could be produced for \(url.lastPathComponent)."
        }
    }
}

public enum ImageFormat: String, CaseIterable, Sendable {
    case jpeg
    case png
    case webp

    public var displayName: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .webp: "WebP"
        }
    }

    public var pathExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .webp: "webp"
        }
    }

    public var typeIdentifier: String {
        switch self {
        case .jpeg: UTType.jpeg.identifier
        case .png: UTType.png.identifier
        case .webp: UTType.webP.identifier
        }
    }
}

public enum OutputFormat: String, CaseIterable, Sendable {
    case automatic
    case jpeg
    case png
    case webp

    public var displayName: String {
        switch self {
        case .automatic: "Auto"
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .webp: "WebP"
        }
    }

    public var concreteFormat: ImageFormat? {
        switch self {
        case .automatic: nil
        case .jpeg: .jpeg
        case .png: .png
        case .webp: .webp
        }
    }
}

public enum CompressionMode: String, CaseIterable, Sendable {
    case balanced
    case lossless

    public var displayName: String {
        switch self {
        case .balanced: "Balanced"
        case .lossless: "Lossless"
        }
    }
}

public struct CompressionOptions: Equatable, Sendable {
    public var outputFormat: OutputFormat
    public var mode: CompressionMode
    public var quality: Double
    public var resizeLongEdge: Int?
    public var keepMetadata: Bool

    public init(
        outputFormat: OutputFormat = .automatic,
        mode: CompressionMode = .balanced,
        quality: Double = 0.8,
        resizeLongEdge: Int? = nil,
        keepMetadata: Bool = false
    ) {
        self.outputFormat = outputFormat
        self.mode = mode
        self.quality = min(max(quality, 0.0), 1.0)
        self.resizeLongEdge = resizeLongEdge
        self.keepMetadata = keepMetadata
    }
}

public struct ImageInfo: Equatable, Sendable, Identifiable {
    public var id: URL { url }

    public let url: URL
    public let format: ImageFormat
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let fileSize: Int64
    public let hasAlpha: Bool
    public let hasMetadata: Bool
    public let colorSpaceName: String?

    public init(
        url: URL,
        format: ImageFormat,
        pixelWidth: Int,
        pixelHeight: Int,
        fileSize: Int64,
        hasAlpha: Bool,
        hasMetadata: Bool,
        colorSpaceName: String?
    ) {
        self.url = url
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
        self.hasAlpha = hasAlpha
        self.hasMetadata = hasMetadata
        self.colorSpaceName = colorSpaceName
    }
}

public struct CompressionResult: Equatable, Sendable, Identifiable {
    public var id: URL { sourceURL }

    public let sourceURL: URL
    public let outputURL: URL
    public let inputFormat: ImageFormat
    public let outputFormat: ImageFormat
    public let originalSize: Int64
    public let compressedSize: Int64
    public let pixelWidth: Int
    public let pixelHeight: Int

    public var savedBytes: Int64 {
        originalSize - compressedSize
    }

    public var savedFraction: Double {
        guard originalSize > 0 else { return 0 }
        return Double(savedBytes) / Double(originalSize)
    }
}

public struct BatchCompressionReport: Sendable {
    public let results: [CompressionResult]
    public let skipped: [(URL, String)]
    public let failures: [(URL, String)]

    public var originalSize: Int64 {
        results.reduce(0) { $0 + $1.originalSize }
    }

    public var compressedSize: Int64 {
        results.reduce(0) { $0 + $1.compressedSize }
    }

    public var savedBytes: Int64 {
        originalSize - compressedSize
    }
}

public enum ByteCount {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public final class ImageInspector {
    public init() {}

    public func inspect(_ url: URL) throws -> ImageInfo {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw FinderXError.unreadableFile(url)
        }

        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        guard let format = Self.format(for: values?.contentType, url: url) else {
            throw FinderXError.unsupportedInput(url)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw FinderXError.imageDecodeFailed(url)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard
            let width = properties?[kCGImagePropertyPixelWidth] as? Int,
            let height = properties?[kCGImagePropertyPixelHeight] as? Int
        else {
            throw FinderXError.imageDecodeFailed(url)
        }

        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        let alphaInfo = image?.alphaInfo
        let metadataKeys = properties?.keys.filter {
            $0 != kCGImagePropertyPixelWidth && $0 != kCGImagePropertyPixelHeight
        } ?? []

        return ImageInfo(
            url: url,
            format: format,
            pixelWidth: width,
            pixelHeight: height,
            fileSize: Int64(values?.fileSize ?? Self.fileSize(url) ?? 0),
            hasAlpha: alphaInfo?.finderxHasAlpha == true,
            hasMetadata: !metadataKeys.isEmpty,
            colorSpaceName: image?.colorSpace?.name as String?
        )
    }

    public static func isSupportedImage(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        return format(for: values?.contentType, url: url) != nil
    }

    public static func format(for contentType: UTType?, url: URL) -> ImageFormat? {
        if contentType?.conforms(to: .jpeg) == true { return .jpeg }
        if contentType?.conforms(to: .png) == true { return .png }
        if contentType?.conforms(to: .webP) == true { return .webp }

        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "webp": return .webp
        default: return nil
        }
    }

    private static func fileSize(_ url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int
    }
}

public final class OutputNamer {
    private let fileManager: FileManager
    private let baseDirectory: URL?

    public init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    public func outputURL(for sourceURL: URL, format: ImageFormat) -> URL {
        let directory = baseDirectory ?? sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent + "-compressed"
        var candidate = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(format.pathExtension)

        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName) \(index)")
                .appendingPathExtension(format.pathExtension)
            index += 1
        }

        return candidate
    }
}

public final class ImageCompressor {
    private let inspector: ImageInspector
    private let namer: OutputNamer
    private let fileManager: FileManager

    public init(
        inspector: ImageInspector = ImageInspector(),
        namer: OutputNamer = OutputNamer(),
        fileManager: FileManager = .default
    ) {
        self.inspector = inspector
        self.namer = namer
        self.fileManager = fileManager
    }

    public static func canWrite(_ format: ImageFormat) -> Bool {
        if format == .webp, WebPCommandEncoder.isAvailable {
            return true
        }
        let writableTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return writableTypes.contains(format.typeIdentifier)
    }

    public func compress(_ sourceURL: URL, options: CompressionOptions = CompressionOptions()) throws -> CompressionResult {
        try compress(sourceURL, options: options) { [namer] sourceURL, format in
            namer.outputURL(for: sourceURL, format: format)
        }
    }

    private func compress(
        _ sourceURL: URL,
        options: CompressionOptions,
        outputURL: (URL, ImageFormat) -> URL
    ) throws -> CompressionResult {
        let info = try inspector.inspect(sourceURL)
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw FinderXError.imageDecodeFailed(sourceURL)
        }

        let renderImage = try resizedIfNeeded(image, maxLongEdge: options.resizeLongEdge)
        let metadata = options.keepMetadata
            ? CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            : nil

        let candidates = candidateFormats(for: info, options: options)
        var encodedCandidates: [(format: ImageFormat, data: Data)] = []

        for format in candidates where Self.canWrite(format) {
            guard let data = try encode(renderImage, format: format, options: options, metadata: metadata) else {
                continue
            }
            encodedCandidates.append((format, data))
        }

        guard let best = encodedCandidates.min(by: { $0.data.count < $1.data.count }) else {
            throw FinderXError.noViableOutput(sourceURL)
        }

        let outputURL = outputURL(sourceURL, best.format)
        do {
            try best.data.write(to: outputURL, options: .atomic)
        } catch {
            throw FinderXError.outputWriteFailed(outputURL)
        }

        let outputValues = try outputURL.resourceValues(forKeys: [.fileSizeKey])
        return CompressionResult(
            sourceURL: sourceURL,
            outputURL: outputURL,
            inputFormat: info.format,
            outputFormat: best.format,
            originalSize: info.fileSize,
            compressedSize: Int64(outputValues.fileSize ?? best.data.count),
            pixelWidth: renderImage.width,
            pixelHeight: renderImage.height
        )
    }

    public func compressBatch(_ sourceURLs: [URL], options: CompressionOptions = CompressionOptions()) -> BatchCompressionReport {
        var results: [CompressionResult] = []
        var skipped: [(URL, String)] = []
        var failures: [(URL, String)] = []

        for url in sourceURLs {
            guard ImageInspector.isSupportedImage(url) else {
                skipped.append((url, "Unsupported file type"))
                continue
            }

            do {
                results.append(try compress(url, options: options))
            } catch {
                failures.append((url, error.localizedDescription))
            }
        }

        return BatchCompressionReport(results: results, skipped: skipped, failures: failures)
    }

    public func compressInPlace(_ sourceURL: URL, options: CompressionOptions = CompressionOptions()) throws -> InplaceCompressionSession {
        let tempID = UUID().uuidString
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("finderx-inplace-\(tempID)", isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let result: CompressionResult
        do {
            result = try compress(sourceURL, options: options) { _, format in
                tempDir
                    .appendingPathComponent("finderx-inplace-\(tempID)")
                    .appendingPathExtension(format.pathExtension)
            }
        } catch {
            try? fileManager.removeItem(at: tempDir)
            throw error
        }

        return InplaceCompressionSession(
            sourceURL: sourceURL,
            tempURL: result.outputURL,
            result: result,
            tempDirectory: tempDir,
            fileManager: fileManager
        )
    }

    private func candidateFormats(for info: ImageInfo, options: CompressionOptions) -> [ImageFormat] {
        if let explicit = options.outputFormat.concreteFormat {
            return [explicit]
        }

        if options.mode == .lossless {
            if info.hasAlpha {
                return [.png, .webp]
            }
            return [info.format, .webp]
        }

        if info.hasAlpha {
            return [.webp, .png]
        }

        return [.webp, .jpeg, info.format].uniqued()
    }

    private func encode(
        _ image: CGImage,
        format: ImageFormat,
        options: CompressionOptions,
        metadata: [CFString: Any]?
    ) throws -> Data? {
        if format == .webp, WebPCommandEncoder.isAvailable {
            return try WebPCommandEncoder().encode(image, options: options)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.typeIdentifier as CFString, 1, nil) else {
            return nil
        }

        var properties = metadata ?? [:]
        if format == .jpeg || format == .webp {
            properties[kCGImageDestinationLossyCompressionQuality] = options.quality
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }

    private func resizedIfNeeded(_ image: CGImage, maxLongEdge: Int?) throws -> CGImage {
        guard let maxLongEdge, max(image.width, image.height) > maxLongEdge else {
            return image
        }

        let scale = Double(maxLongEdge) / Double(max(image.width, image.height))
        let newWidth = max(1, Int(Double(image.width) * scale))
        let newHeight = max(1, Int(Double(image.height) * scale))
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo
        ) else {
            throw FinderXError.imageDecodeFailed(URL(fileURLWithPath: ""))
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        guard let resized = context.makeImage() else {
            throw FinderXError.imageDecodeFailed(URL(fileURLWithPath: ""))
        }
        return resized
    }
}

public final class InplaceCompressionSession: @unchecked Sendable {
    public let sourceURL: URL
    public let tempURL: URL
    public let result: CompressionResult
    public let targetURL: URL

    private let tempDirectory: URL
    private let fileManager: FileManager
    private var committed = false

    public init(
        sourceURL: URL,
        tempURL: URL,
        result: CompressionResult,
        tempDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.sourceURL = sourceURL
        self.tempURL = tempURL
        self.result = result
        self.tempDirectory = tempDirectory
        self.fileManager = fileManager
        self.targetURL = sourceURL.deletingPathExtension()
            .appendingPathExtension(tempURL.pathExtension)
    }

    public func commit() throws {
        guard !committed else { return }

        if targetURL != sourceURL, fileManager.fileExists(atPath: targetURL.path) {
            throw FinderXError.outputWriteFailed(targetURL)
        }

        if targetURL == sourceURL {
            _ = try fileManager.replaceItem(at: sourceURL, withItemAt: tempURL, backupItemName: nil, options: [], resultingItemURL: nil)
            try? fileManager.removeItem(at: tempDirectory)
            committed = true
            return
        }

        let backupName = "\(sourceURL.lastPathComponent).finderx-backup"
        let backupURL = sourceURL.deletingLastPathComponent().appendingPathComponent(backupName)
        var replacedURL: NSURL?
        _ = try fileManager.replaceItem(
            at: sourceURL,
            withItemAt: tempURL,
            backupItemName: backupName,
            options: [],
            resultingItemURL: &replacedURL
        )

        let currentURL = (replacedURL as URL?) ?? sourceURL
        do {
            try fileManager.moveItem(at: currentURL, to: targetURL)
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.removeItem(at: tempDirectory)
        } catch {
            if fileManager.fileExists(atPath: currentURL.path) {
                try? fileManager.removeItem(at: currentURL)
            }
            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: sourceURL)
            }
            throw error
        }
        committed = true
    }

    public func discard() {
        guard !committed else { return }
        try? fileManager.removeItem(at: tempDirectory)
        committed = true
    }

    deinit {
        discard()
    }
}

private struct WebPCommandEncoder {
    static var isAvailable: Bool {
        executableURL != nil
    }

    private static var executableURL: URL? {
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("cwebp/bin/cwebp"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let candidates = [
            "/opt/homebrew/bin/cwebp",
            "/usr/local/bin/cwebp",
            "/opt/local/bin/cwebp"
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func encode(_ image: CGImage, options: CompressionOptions) throws -> Data? {
        guard let executableURL = Self.executableURL else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("finderx-webp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("input.png")
        let outputURL = directory.appendingPathComponent("output.webp")
        guard writePNG(image, to: inputURL) else {
            return nil
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments(inputURL: inputURL, outputURL: outputURL, options: options)
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: outputURL.path)
        else {
            return nil
        }

        return try Data(contentsOf: outputURL)
    }

    private func arguments(inputURL: URL, outputURL: URL, options: CompressionOptions) -> [String] {
        var arguments: [String] = []
        if options.mode == .lossless {
            arguments.append("-lossless")
        } else {
            arguments.append(contentsOf: ["-q", "\(Int(options.quality * 100))"])
        }
        arguments.append(contentsOf: [
            "-metadata", options.keepMetadata ? "all" : "none",
            inputURL.path,
            "-o", outputURL.path
        ])
        return arguments
    }

    private func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            ImageFormat.png.typeIdentifier as CFString,
            1,
            nil
        ) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}

private extension CGImageAlphaInfo {
    var finderxHasAlpha: Bool {
        switch self {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            true
        default:
            false
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
