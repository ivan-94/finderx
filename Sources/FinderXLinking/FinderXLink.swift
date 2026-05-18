import Darwin
import Foundation
import OSLog

public enum FinderXLink {
    private static let logger = Logger(subsystem: "dev.finderx.FinderXLinking", category: "FinderXLink")

    public static func makeOpenURL(for fileURL: URL, iCloudRoot: URL? = defaultICloudDriveRoot()) -> URL? {
        var components = URLComponents()
        components.scheme = "finderx"
        components.host = "open"
        var queryItems: [URLQueryItem] = []
        if let iCloudRoot, let relativePath = relativePath(for: fileURL, under: iCloudRoot) {
            queryItems.append(URLQueryItem(name: "icloud", value: relativePath))
        }
        queryItems.append(URLQueryItem(name: "file", value: fileURL.path))
        components.queryItems = queryItems
        return components.url
    }

    public static func makeCompressURL(for fileURLs: [URL]) -> URL? {
        guard !fileURLs.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "finderx"
        components.host = "compress"
        components.queryItems = fileURLs.map { URLQueryItem(name: "file", value: $0.path) }
        return components.url
    }

    public static func resolveOpenURL(_ url: URL, iCloudRoot: URL? = defaultICloudDriveRoot()) -> URL? {
        guard url.scheme == "finderx", url.host == "open" else { return nil }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let iCloudValue = queryItems.first { $0.name == "icloud" }?.value
        let fileValue = queryItems.first { $0.name == "file" }?.value
        if queryItems.filter({ $0.name == "icloud" }).count > 1 {
            logger.notice("open link has duplicate icloud parameters; using first")
        }
        if queryItems.filter({ $0.name == "file" }).count > 1 {
            logger.notice("open link has duplicate file parameters; using first")
        }

        if let iCloudRoot, let iCloudValue, let candidate = iCloudFileURL(relativePath: iCloudValue, root: iCloudRoot),
           isOpenableRegularFile(candidate) {
            return candidate
        }

        if let fileValue, fileValue.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: fileValue)
            if isOpenableRegularFile(candidate) {
                return candidate
            }
        }

        return nil
    }

    public static func defaultICloudDriveRoot() -> URL? {
        let root = realHomeDirectory()
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: root.path) ? root : nil
    }

    private static func relativePath(for fileURL: URL, under root: URL) -> String? {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return nil }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func iCloudFileURL(relativePath: String, root: URL) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        guard !relativePath.split(separator: "/").contains("..") else { return nil }
        return root.appendingPathComponent(relativePath)
    }

    private static func isOpenableRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isDirectory != true && values.isPackage != true
    }

    private static func realHomeDirectory() -> URL {
        if let passwd = getpwuid(getuid()),
           let homePath = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
