import AppKit
import Foundation
import OSLog
import QuickLookThumbnailing
import XMindPreviewCore

final class ThumbnailProvider: QLThumbnailProvider {
    private let logger = Logger(subsystem: "dev.finderx.FinderX", category: "XMindThumbnail")

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        logger.info("Providing XMind thumbnail for \(request.fileURL.path, privacy: .public)")
        guard let thumbnail = XMindThumbnailExtractor.extractThumbnail(from: request.fileURL),
              let image = NSImage(data: thumbnail.data)
        else {
            logger.info("No embedded XMind thumbnail for \(request.fileURL.path, privacy: .public)")
            handler(nil, nil)
            return
        }

        let contextSize = fittedSize(
            imageSize: thumbnail.pixelSize,
            maximumSize: request.maximumSize,
            minimumSize: request.minimumSize
        )

        let reply = QLThumbnailReply(contextSize: contextSize, currentContextDrawing: {
            let drawingRect = CGRect(origin: .zero, size: contextSize)
            image.draw(in: drawingRect, from: .zero, operation: .copy, fraction: 1)
            return true
        })
        reply.extensionBadge = "xmind"
        logger.info("Provided XMind thumbnail from \(thumbnail.sourcePath, privacy: .public)")
        handler(reply, nil)
    }

    private func fittedSize(imageSize: CGSize, maximumSize: CGSize, minimumSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return maximumSize
        }

        let maxWidth = max(maximumSize.width, minimumSize.width, 1)
        let maxHeight = max(maximumSize.height, minimumSize.height, 1)
        let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height)
        let width = max(imageSize.width * scale, minimumSize.width, 1)
        let height = max(imageSize.height * scale, minimumSize.height, 1)
        return CGSize(width: width, height: height)
    }
}
