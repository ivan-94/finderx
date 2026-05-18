import AppKit
import Darwin
import FinderXLinking
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
        let actionURLs = Self.selectedItemURLsForAction()
        let imageURLs = actionURLs.filter(Self.isSupportedImage)
        let linkURL = actionURLs.count == 1 && Self.isOrdinaryFile(actionURLs[0]) ? actionURLs[0] : nil
        logger.notice(
            "menu requested kind=\(menuKind.rawValue, privacy: .public) selected=\(selectedURLs.map(\.path).joined(separator: "|"), privacy: .public) targeted=\(targetedURL?.path ?? "nil", privacy: .public) imageCount=\(imageURLs.count, privacy: .public)"
        )

        guard menuKind == .contextualMenuForItems else {
            logger.notice("menu ignored: non-item contextual menu")
            return nil
        }

        guard !imageURLs.isEmpty || linkURL != nil else {
            logger.notice("menu ignored: no eligible FinderX action")
            return nil
        }

        let menu = NSMenu(title: "FinderX")
        if !imageURLs.isEmpty {
            let item = NSMenuItem(
                title: "Compress with FinderX",
                action: #selector(compressSelectedImages),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }
        if linkURL != nil {
            let item = NSMenuItem(
                title: "Copy FinderX Link",
                action: #selector(copyFinderXLink),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }
        logger.notice("menu returned itemCount=\(menu.items.count, privacy: .public)")
        return menu
    }

    @objc private func compressSelectedImages() {
        let urls = Self.selectedImageURLs()
        logger.notice("compress action selected image count=\(urls.count, privacy: .public)")
        guard !urls.isEmpty else { return }

        guard let url = FinderXLink.makeCompressURL(for: urls) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyFinderXLink() {
        let urls = Self.selectedItemURLsForAction()
        guard urls.count == 1, Self.isOrdinaryFile(urls[0]) else {
            logger.notice("copy link ignored: selection is not one ordinary file")
            return
        }

        guard let url = FinderXLink.makeOpenURL(for: urls[0]) else {
            logger.error("copy link failed: could not build URL for \(urls[0].path, privacy: .public)")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        pasteboard.setString(url.absoluteString, forType: .URL)
        logger.notice("copy link succeeded for \(urls[0].path, privacy: .public)")
    }

    private static func selectedImageURLs() -> [URL] {
        selectedItemURLsForAction().filter(Self.isSupportedImage)
    }

    private static func selectedItemURLsForAction() -> [URL] {
        let controller = FIFinderSyncController.default()
        var urls = controller.selectedItemURLs() ?? []
        if urls.isEmpty, let targetedURL = controller.targetedURL() {
            urls = [targetedURL]
        }
        return urls
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

    private static func isOrdinaryFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isDirectory != true && values.isPackage != true
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
