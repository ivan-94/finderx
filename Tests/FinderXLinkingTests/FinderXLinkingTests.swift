import FinderXLinking
import Foundation
import Testing

@Suite("FinderXLinking")
struct FinderXLinkingTests {
    @Test("Non-iCloud files generate a FinderX open link with an absolute fallback path")
    func nonICloudOpenLink() throws {
        let file = URL(fileURLWithPath: "/Users/ivan/Downloads/a file.pdf")

        let url = try #require(FinderXLink.makeOpenURL(for: file, iCloudRoot: nil))

        #expect(url.scheme == "finderx")
        #expect(url.host == "open")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let fileValue = components.queryItems?.first { $0.name == "file" }?.value
        let iCloudValue = components.queryItems?.first { $0.name == "icloud" }?.value

        #expect(fileValue == "/Users/ivan/Downloads/a file.pdf")
        #expect(iCloudValue == nil)
    }

    @Test("iCloud files generate a migratable relative path and an absolute fallback path")
    func iCloudOpenLink() throws {
        let root = URL(fileURLWithPath: "/Users/ivan/Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let file = root.appendingPathComponent("Documents/报价 a.pdf")

        let url = try #require(FinderXLink.makeOpenURL(for: file, iCloudRoot: root))

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []

        #expect(components.scheme == "finderx")
        #expect(components.host == "open")
        #expect(queryItems.first { $0.name == "icloud" }?.value == "Documents/报价 a.pdf")
        #expect(queryItems.first { $0.name == "file" }?.value == file.path)
    }

    @Test("Open links resolve the iCloud path before the fallback path")
    func openLinkResolvesICloudBeforeFallback() throws {
        let directory = try makeDirectory()
        let iCloudRoot = directory.appendingPathComponent("iCloud", isDirectory: true)
        let fallbackRoot = directory.appendingPathComponent("fallback", isDirectory: true)
        try FileManager.default.createDirectory(at: iCloudRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fallbackRoot, withIntermediateDirectories: true)

        let iCloudFile = iCloudRoot.appendingPathComponent("Documents/report.pdf")
        let fallbackFile = fallbackRoot.appendingPathComponent("report.pdf")
        try FileManager.default.createDirectory(at: iCloudFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: iCloudFile.path, contents: Data("icloud".utf8))
        FileManager.default.createFile(atPath: fallbackFile.path, contents: Data("fallback".utf8))

        var components = URLComponents()
        components.scheme = "finderx"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "icloud", value: "Documents/report.pdf"),
            URLQueryItem(name: "file", value: fallbackFile.path)
        ]

        let resolved = FinderXLink.resolveOpenURL(try #require(components.url), iCloudRoot: iCloudRoot)

        #expect(resolved == iCloudFile)
    }

    @Test("Open links fall back to absolute files and reject unsafe or non-file inputs")
    func openLinkFallbackAndRejections() throws {
        let directory = try makeDirectory()
        let fallbackFile = directory.appendingPathComponent("fallback.txt")
        let folder = directory.appendingPathComponent("Folder", isDirectory: true)
        FileManager.default.createFile(atPath: fallbackFile.path, contents: Data("fallback".utf8))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let staleICloudURL = openURL([
            URLQueryItem(name: "icloud", value: "Missing/report.pdf"),
            URLQueryItem(name: "file", value: fallbackFile.path)
        ])
        let relativeFallbackURL = openURL([
            URLQueryItem(name: "file", value: "relative.txt")
        ])
        let directoryURL = openURL([
            URLQueryItem(name: "file", value: folder.path)
        ])
        let unknownHostURL = URL(string: "finderx://compress?file=\(fallbackFile.path)")!
        let emptyURL = openURL([])

        #expect(FinderXLink.resolveOpenURL(staleICloudURL, iCloudRoot: directory) == fallbackFile)
        #expect(FinderXLink.resolveOpenURL(relativeFallbackURL, iCloudRoot: directory) == nil)
        #expect(FinderXLink.resolveOpenURL(directoryURL, iCloudRoot: directory) == nil)
        #expect(FinderXLink.resolveOpenURL(unknownHostURL, iCloudRoot: directory) == nil)
        #expect(FinderXLink.resolveOpenURL(emptyURL, iCloudRoot: directory) == nil)
    }

    @Test("Compress links preserve selected file order")
    func compressLink() throws {
        let first = URL(fileURLWithPath: "/Users/ivan/Library/Mobile Documents/com~apple~CloudDocs/a.jpg")
        let second = URL(fileURLWithPath: "/Users/ivan/Downloads/b.png")

        let url = try #require(FinderXLink.makeCompressURL(for: [first, second]))

        #expect(url.scheme == "finderx")
        #expect(url.host == "compress")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let files = components.queryItems?.filter { $0.name == "file" }.compactMap(\.value)
        #expect(files == [first.path, second.path])
    }

    @Test("Compress links reject empty selections")
    func compressLinkRejectsEmptySelections() {
        #expect(FinderXLink.makeCompressURL(for: []) == nil)
    }

    @Test("Copy action links preserve selected file paths")
    func copyActionLinks() throws {
        let first = URL(fileURLWithPath: "/Users/ivan/Downloads/a file.pdf")
        let second = URL(fileURLWithPath: "/Users/ivan/Library/Mobile Documents/com~apple~CloudDocs/b.jpg")

        let copyLinkURL = try #require(FinderXLink.makeCopyFinderXLinkURL(for: first))
        let copyPathURL = try #require(FinderXLink.makeCopyAbsolutePathURL(for: [first, second]))

        #expect(copyLinkURL.scheme == "finderx")
        #expect(copyLinkURL.host == "copy-link")
        #expect(URLComponents(url: copyLinkURL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == first.path)

        #expect(copyPathURL.scheme == "finderx")
        #expect(copyPathURL.host == "copy-path")
        let files = URLComponents(url: copyPathURL, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "file" }.compactMap(\.value)
        #expect(files == [first.path, second.path])
        #expect(FinderXLink.makeCopyAbsolutePathURL(for: []) == nil)
    }

    @Test("Absolute path text preserves order and uses one path per line")
    func absolutePathText() {
        let first = URL(fileURLWithPath: "/Users/ivan/Library/Mobile Documents/com~apple~CloudDocs/a file.jpg")
        let second = URL(fileURLWithPath: "/Users/ivan/Downloads/folder", isDirectory: true)

        let text = FinderXPathFormatter.absolutePathsText(for: [first, second])

        #expect(text == "/Users/ivan/Library/Mobile Documents/com~apple~CloudDocs/a file.jpg\n/Users/ivan/Downloads/folder")
    }

    @Test("Absolute path text ignores non-file URLs and de-duplicates standardized paths")
    func absolutePathTextRejectsUnsupportedInputs() {
        let folder = URL(fileURLWithPath: "/Users/ivan/Downloads/folder", isDirectory: true)
        let duplicate = URL(fileURLWithPath: "/Users/ivan/Downloads/./folder", isDirectory: true)
        let webURL = URL(string: "https://example.com/file.jpg")!

        let text = FinderXPathFormatter.absolutePathsText(for: [webURL, folder, duplicate])

        #expect(text == "/Users/ivan/Downloads/folder")
        #expect(FinderXPathFormatter.absolutePathsText(for: [webURL]) == nil)
        #expect(FinderXPathFormatter.absolutePathsText(for: []) == nil)
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("finderx-linking-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func openURL(_ queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = "finderx"
        components.host = "open"
        components.queryItems = queryItems
        return components.url!
    }
}
