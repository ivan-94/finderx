import Foundation
import ImageCompressionCore

let arguments = Array(CommandLine.arguments.dropFirst())

guard !arguments.isEmpty else {
    FileHandle.standardError.write(Data("Usage: finderx-compress <image> [<image> ...]\n".utf8))
    exit(64)
}

let urls = arguments.map { URL(fileURLWithPath: $0) }
let compressor = ImageCompressor()
let report = compressor.compressBatch(urls, options: CompressionOptions())

for result in report.results {
    print("\(result.sourceURL.path) -> \(result.outputURL.path)")
    print("  \(result.inputFormat.displayName) \(ByteCount.string(result.originalSize)) -> \(result.outputFormat.displayName) \(ByteCount.string(result.compressedSize))")
}

for (url, reason) in report.skipped {
    print("SKIP \(url.path): \(reason)")
}

for (url, reason) in report.failures {
    print("FAIL \(url.path): \(reason)")
}

if report.results.isEmpty {
    exit(1)
}
