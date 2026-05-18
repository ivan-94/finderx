import AppKit
import Darwin
import FinderSync
import OSLog
import UniformTypeIdentifiers

final class FinderSync: FIFinderSync {
    private let logger = Logger(subsystem: "dev.finderx.FinderX.FinderExtension", category: "FinderSync")

    override init() {
        super.init()
        let directories = Set(MonitoredFolders.defaults)
        FIFinderSyncController.default().directoryURLs = directories
        logger.notice("FinderX extension initialized. directories=\(directories.map(\.path).joined(separator: "|"), privacy: .public)")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        let targetedURL = FIFinderSyncController.default().targetedURL()
        let imageURLs = Self.selectedImageURLs()
        logger.notice(
            "menu requested kind=\(menuKind.rawValue, privacy: .public) selected=\(selectedURLs.map(\.path).joined(separator: "|"), privacy: .public) targeted=\(targetedURL?.path ?? "nil", privacy: .public) imageCount=\(imageURLs.count, privacy: .public)"
        )

        guard menuKind == .contextualMenuForItems else {
            logger.notice("menu ignored: non-item contextual menu")
            return nil
        }

        guard !imageURLs.isEmpty else {
            logger.notice("menu ignored: no supported images")
            return nil
        }

        let menu = NSMenu(title: "FinderX")
        let item = NSMenuItem(
            title: "Compress with FinderX",
            action: #selector(compressSelectedImages),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        logger.notice("menu returned: Compress with FinderX")
        return menu
    }

    @objc private func compressSelectedImages() {
        let urls = Self.selectedImageURLs()
        logger.notice("compress action selected image count=\(urls.count, privacy: .public)")
        guard !urls.isEmpty else { return }

        var components = URLComponents()
        components.scheme = "finderx"
        components.host = "compress"
        components.queryItems = urls.map { URLQueryItem(name: "file", value: $0.path) }

        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private static func selectedImageURLs() -> [URL] {
        let controller = FIFinderSyncController.default()
        var urls = controller.selectedItemURLs() ?? []
        if urls.isEmpty, let targetedURL = controller.targetedURL() {
            urls = [targetedURL]
        }
        return urls.filter(Self.isSupportedImage)
    }

    private static func isSupportedImage(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]) {
            if values.contentType?.conforms(to: .jpeg) == true { return true }
            if values.contentType?.conforms(to: .png) == true { return true }
            if values.contentType?.conforms(to: .webP) == true { return true }
        }

        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "webp": return true
        default: return false
        }
    }
}

private enum MonitoredFolders {
    static let defaults: [URL] = {
        let home = realHomeDirectory()
        var urls = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Pictures")
        ]
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: iCloud.path) {
            urls.append(iCloud)
        }
        return urls
    }()

    private static func realHomeDirectory() -> URL {
        if let passwd = getpwuid(getuid()),
           let homePath = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}
