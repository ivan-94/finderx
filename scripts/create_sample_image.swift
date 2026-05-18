import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: create_sample_image.swift <output.jpg>\n".utf8))
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let width = 1200
let height = 800
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

for y in stride(from: 0, to: height, by: 16) {
    for x in stride(from: 0, to: width, by: 16) {
        let red = CGFloat((x * 13 + y * 3) % 255) / 255.0
        let green = CGFloat((x * 5 + y * 11) % 255) / 255.0
        let blue = CGFloat((x * 7 + y * 17) % 255) / 255.0
        context.setFillColor(NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1).cgColor)
        context.fill(CGRect(x: x, y: y, width: 16, height: 16))
    }
}

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.jpeg.identifier as CFString,
    1,
    nil
)!
CGImageDestinationAddImage(destination, image, [
    kCGImageDestinationLossyCompressionQuality: 0.95
] as CFDictionary)

guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("Failed to write sample image\n".utf8))
    exit(1)
}

print(outputURL.path)
