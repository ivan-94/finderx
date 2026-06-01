import Foundation
import OSLog
import QuickLookUI
import UniformTypeIdentifiers
import XMindPreviewCore

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private let logger = Logger(subsystem: "dev.finderx.FinderX", category: "XMindPreview")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        logger.info("Providing XMind preview for \(request.fileURL.path, privacy: .public)")
        guard let thumbnail = XMindThumbnailExtractor.extractThumbnail(from: request.fileURL),
              let contentType = UTType(thumbnail.contentTypeIdentifier)
        else {
            logger.info("No embedded XMind preview for \(request.fileURL.path, privacy: .public)")
            throw CocoaError(.fileReadCorruptFile)
        }

        let reply = QLPreviewReply(
            dataOfContentType: contentType,
            contentSize: thumbnail.pixelSize,
            createDataUsing: { reply in
                reply.title = request.fileURL.deletingPathExtension().lastPathComponent
                return thumbnail.data
            }
        )
        logger.info("Provided XMind preview from \(thumbnail.sourcePath, privacy: .public)")
        return reply
    }
}
