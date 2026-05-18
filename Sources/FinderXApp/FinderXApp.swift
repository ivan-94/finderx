import AppKit
import Darwin
import FinderXLinking
import ImageCompressionCore
import OSLog
import SwiftUI

@main
struct FinderXApp: App {
    @NSApplicationDelegateAdaptor(FinderXAppDelegate.self) private var appDelegate
    @StateObject private var router = CompressionRouter()

    var body: some Scene {
        Window("FinderX", id: "main") {
            CompressionRootView()
                .environmentObject(router)
                .frame(minWidth: 840, minHeight: 560)
                .onOpenURL { url in
                    router.open(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .finderXCompressURLsRequested)) { notification in
                    guard let urls = notification.object as? [URL] else { return }
                    router.openCompression(urls)
                }
                .onAppear {
                    guard let urls = FinderXServiceRequests.takePendingCompressionURLs() else { return }
                    router.openCompression(urls)
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Images...") {
                    router.pickImages()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .frame(width: 560, height: 360)
        }
    }
}

final class FinderXAppDelegate: NSObject, NSApplicationDelegate {
    private var hideWorkItem: DispatchWorkItem?
    private let servicesProvider = FinderXServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
    }

    func applicationDidResignActive(_ notification: Notification) {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard !NSApp.isActive else { return }
            guard !NSApp.windows.contains(where: { $0.attachedSheet != nil }) else { return }
            guard NSApp.keyWindow == nil else { return }
            NSApp.hide(nil)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        hideWorkItem?.cancel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppPresentation.show()
        return true
    }
}

final class FinderXServicesProvider: NSObject {
    private let logger = Logger(subsystem: "dev.finderx.FinderX", category: "Services")

    @objc(compressWithFinderXService:userData:error:)
    func compressWithFinderXService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        let imageURLs = fileURLs(from: pasteboard).filter(ImageInspector.isSupportedImage)
        guard !imageURLs.isEmpty else {
            error?.pointee = "Select one supported image." as NSString
            logger.notice("compress service ignored: no supported images")
            return
        }

        let scopedURLs = imageURLs.filter { $0.startAccessingSecurityScopedResource() }
        Task { @MainActor in
            FinderXServiceRequests.requestCompression(imageURLs, scopedURLs: scopedURLs)
        }
        logger.notice("compress service opened image count=\(imageURLs.count, privacy: .public)")
    }

    @objc(copyFinderXLinkService:userData:error:)
    func copyFinderXLinkService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        let urls = fileURLs(from: pasteboard)
        guard urls.count == 1 else {
            error?.pointee = "Select one file." as NSString
            logger.notice("service ignored: expected one file, got \(urls.count, privacy: .public)")
            return
        }

        guard isOrdinaryFile(urls[0]) else {
            error?.pointee = "Selected item is not a file." as NSString
            logger.notice("service ignored: selected item is not an ordinary file")
            return
        }

        guard let link = FinderXLink.makeOpenURL(for: urls[0]) else {
            error?.pointee = "Could not create FinderX link." as NSString
            logger.error("service failed: could not build link for \(urls[0].path, privacy: .public)")
            return
        }

        let general = NSPasteboard.general
        general.clearContents()
        general.setString(link.absoluteString, forType: .string)
        general.setString(link.absoluteString, forType: .URL)
        logger.notice("service copied link for \(urls[0].path, privacy: .public)")
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []

        let readOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let readURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: readOptions
        ) as? [NSURL] {
            urls.append(contentsOf: readURLs.map { $0 as URL }.filter(\.isFileURL))
        }

        if let items = pasteboard.pasteboardItems {
            for item in items {
                if let value = item.string(forType: .fileURL) ?? item.string(forType: .URL),
                   let url = URL(string: value),
                   url.isFileURL {
                    urls.append(url)
                }
            }
        }

        if urls.isEmpty,
           let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = paths.map { URL(fileURLWithPath: $0) }
        }

        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    private func isOrdinaryFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isDirectory != true && values.isPackage != true
    }
}

private extension Notification.Name {
    static let finderXCompressURLsRequested = Notification.Name("dev.finderx.compressURLsRequested")
}

@MainActor
private enum FinderXServiceRequests {
    private static var pendingCompressionURLs: [URL]?
    private static var serviceScopedURLs: [URL] = []

    static func requestCompression(_ urls: [URL], scopedURLs: [URL]) {
        stopAccessingServiceScopedURLs()
        serviceScopedURLs = scopedURLs
        pendingCompressionURLs = urls
        NotificationCenter.default.post(name: .finderXCompressURLsRequested, object: urls)
    }

    static func takePendingCompressionURLs() -> [URL]? {
        defer { pendingCompressionURLs = nil }
        return pendingCompressionURLs
    }

    private static func stopAccessingServiceScopedURLs() {
        serviceScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        serviceScopedURLs = []
    }
}

private enum AppPresentation {
    static func show() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows
                .filter { !$0.isMiniaturized && !$0.title.isEmpty }
                .forEach { window in
                    window.centerIfNeeded()
                    window.makeKeyAndOrderFront(nil)
                }
        }
    }
}

private extension NSWindow {
    func centerIfNeeded() {
        if !isVisible {
            center()
        }
    }
}

@MainActor
final class CompressionRouter: ObservableObject {
    @Published var selectedURLs: [URL] = []
    @Published var replaceSuccessMessage: String?
    private let logger = Logger(subsystem: "dev.finderx.FinderX", category: "URLRouter")
    private var securityScopedURLs: [URL] = []

    func open(_ url: URL) {
        guard url.scheme == "finderx" else { return }
        if url.host == "open" {
            guard let fileURL = FinderXLink.resolveOpenURL(url) else {
                logger.notice("open link ignored: could not resolve \(url.absoluteString, privacy: .public)")
                return
            }
            NSWorkspace.shared.open(fileURL)
            return
        }

        guard url.host == "compress" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let files = components?.queryItems?
            .filter { $0.name == "file" }
            .compactMap(\.value)
            .compactMap { URL(fileURLWithPath: $0) } ?? []
        select(files)
        AppPresentation.show()
    }

    func openCompression(_ urls: [URL]) {
        select(urls)
        AppPresentation.show()
    }

    func replaceSelectedURL(_ oldURL: URL, with newURL: URL, message: String) {
        replaceSuccessMessage = message
        let updated = selectedURLs.map { $0 == oldURL ? newURL : $0 }
        select(updated)
    }

    func pickImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png, .webP]
        if panel.runModal() == .OK {
            select(panel.urls)
            AppPresentation.show()
        }
    }

    private func select(_ urls: [URL]) {
        stopAccessingSelectedURLs()
        securityScopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        selectedURLs = urls
    }

    private func stopAccessingSelectedURLs() {
        securityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        securityScopedURLs = []
    }
}

struct CompressionRootView: View {
    @EnvironmentObject private var router: CompressionRouter

    var body: some View {
        Group {
            if router.selectedURLs.isEmpty {
                EmptyStateView()
            } else if router.selectedURLs.count == 1 {
                CompressionView(urls: router.selectedURLs) { oldURL, newURL, message in
                    router.replaceSelectedURL(oldURL, with: newURL, message: message)
                }
                    .id(router.selectedURLs)
            } else {
                NavigationSplitView {
                    Sidebar(urls: router.selectedURLs)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
                } detail: {
                    CompressionView(urls: router.selectedURLs) { oldURL, newURL, message in
                        router.replaceSelectedURL(oldURL, with: newURL, message: message)
                    }
                        .id(router.selectedURLs)
                }
            }
        }
        .alert("Replaced", isPresented: replaceSuccessBinding) {
            Button("OK", role: .cancel) {
                router.replaceSuccessMessage = nil
            }
        } message: {
            Text(router.replaceSuccessMessage ?? "")
        }
    }

    private var replaceSuccessBinding: Binding<Bool> {
        Binding(
            get: { router.replaceSuccessMessage != nil },
            set: { isPresented in
                if !isPresented {
                    router.replaceSuccessMessage = nil
                }
            }
        )
    }
}

private struct Sidebar: View {
    let urls: [URL]

    var body: some View {
        List {
            Section("Selected") {
                if urls.isEmpty {
                    Text("No images selected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(urls, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "photo")
                            .lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle("FinderX")
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject private var router: CompressionRouter

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Choose JPEG or PNG images to compress.")
                .font(.title3)
            Button {
                router.pickImages()
            } label: {
                Label("Open Images", systemImage: "folder")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CompressionView: View {
    @StateObject private var model: CompressionViewModel

    init(urls: [URL], onCommittedReplacement: @escaping (URL, URL, String) -> Void) {
        _model = StateObject(wrappedValue: CompressionViewModel(
            urls: urls,
            onCommittedReplacement: onCommittedReplacement
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            CompressionHeader(model: model)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await model.inspect()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isWorking {
            ProgressView("Working...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.urls.count == 1, let info = model.infos.first {
            SingleImageView(model: model, info: info, result: model.results.first)
        } else {
            BatchView(model: model)
        }
    }
}

private struct CompressionHeader: View {
    @ObservedObject var model: CompressionViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.urls.count == 1 ? "photo" : "photo.stack")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let result = model.results.first, model.results.count == 1 {
                Text("\(ByteCount.string(result.originalSize)) -> \(ByteCount.string(result.compressedSize))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                if model.overwriteOriginal {
                    Task { await model.compressInPlace() }
                } else {
                    Task { await model.compress() }
                }
            } label: {
                Label("Compress", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.isWorking || model.infos.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var title: String {
        if model.urls.count == 1 {
            return model.urls.first?.lastPathComponent ?? "Image"
        }
        return "\(model.urls.count) images"
    }

    private var subtitle: String {
        if let info = model.infos.first, model.urls.count == 1 {
            return "\(info.format.displayName) - \(info.pixelWidth) x \(info.pixelHeight) - \(ByteCount.string(info.fileSize))"
        }
        return "\(model.infos.count) supported of \(model.urls.count) selected"
    }
}

@MainActor
final class CompressionViewModel: ObservableObject {
    @Published var urls: [URL]
    @Published var infos: [ImageInfo] = []
    @Published var outputFormat = OutputFormat.automatic
    @Published var compressionMode = CompressionMode.balanced
    @Published var quality = 0.8
    @Published var resizePreset = ResizePreset.original
    @Published var keepMetadata = false
    @Published var overwriteOriginal = false
    @Published var results: [CompressionResult] = []
    @Published var skipped: [(URL, String)] = []
    @Published var failures: [(URL, String)] = []
    @Published var isWorking = false
    @Published var inplaceError: String? = nil
    @Published var tempResult: CompressionResult? = nil

    private var inplaceSession: InplaceCompressionSession? = nil
    private let onCommittedReplacement: (URL, URL, String) -> Void

    let availableOutputFormats: [OutputFormat] = OutputFormat.allCases.filter { format in
        guard let concrete = format.concreteFormat else { return true }
        return ImageCompressor.canWrite(concrete)
    }

    let unavailableOutputFormats: [OutputFormat] = OutputFormat.allCases.filter { format in
        guard let concrete = format.concreteFormat else { return false }
        return !ImageCompressor.canWrite(concrete)
    }

    private let logger = Logger(subsystem: "dev.finderx.FinderX", category: "Compression")
    private let inspector = ImageInspector()
    private let compressor = ImageCompressor()

    init(urls: [URL], onCommittedReplacement: @escaping (URL, URL, String) -> Void) {
        self.urls = urls
        self.onCommittedReplacement = onCommittedReplacement
    }

    deinit {
        inplaceSession?.discard()
    }

    func inspect() async {
        isWorking = true
        defer { isWorking = false }

        var loaded: [ImageInfo] = []
        var localSkipped: [(URL, String)] = []
        for url in urls {
            do {
                loaded.append(try inspector.inspect(url))
            } catch {
                localSkipped.append((url, error.localizedDescription))
            }
        }
        infos = loaded
        skipped = localSkipped
    }

    func compress() async {
        isWorking = true
        defer { isWorking = false }

        discardInPlace()
        results = []
        failures = []
        skipped = []
        inplaceError = nil

        let options = currentOptions()
        logger.notice(
            "compress start count=\(self.urls.count, privacy: .public) format=\(options.outputFormat.displayName, privacy: .public) mode=\(options.mode.displayName, privacy: .public) quality=\(options.quality, privacy: .public) resize=\(options.resizeLongEdge ?? 0, privacy: .public)"
        )

        let report = compressor.compressBatch(urls, options: options)

        results = report.results
        skipped = report.skipped
        failures = report.failures

        logger.notice(
            "compress finished results=\(report.results.count, privacy: .public) skipped=\(report.skipped.count, privacy: .public) failures=\(report.failures.count, privacy: .public)"
        )

        if report.results.count == 1, let output = report.results.first?.outputURL {
            NSWorkspace.shared.activateFileViewerSelecting([output])
        }
    }

    func compressInPlace() async {
        guard urls.count == 1, let url = urls.first else { return }
        isWorking = true
        defer { isWorking = false }

        discardInPlace()
        results = []
        failures = []
        skipped = []

        let options = currentOptions()
        logger.notice(
            "compressInPlace start url=\(url.lastPathComponent, privacy: .public) format=\(options.outputFormat.displayName, privacy: .public)"
        )

        do {
            let session = try compressor.compressInPlace(url, options: options)
            inplaceSession = session
            tempResult = session.result
            logger.notice(
                "compressInPlace ready temp=\(session.tempURL.lastPathComponent, privacy: .public) saved=\(session.result.savedFraction, privacy: .public)"
            )
        } catch {
            inplaceError = error.localizedDescription
            logger.error("compressInPlace failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func commitInPlace() async {
        guard let session = inplaceSession else { return }
        isWorking = true
        defer { isWorking = false }
        inplaceError = nil

        do {
            try session.commit()
            let oldURL = session.sourceURL
            let newURL = session.targetURL
            let savedPercent = Int(session.result.savedFraction * 100)
            let message = "\(newURL.lastPathComponent) replaced. Saved \(savedPercent)% (\(ByteCount.string(session.result.originalSize)) → \(ByteCount.string(session.result.compressedSize)))."

            // Update selected URL to the new target (extension may have changed)
            if let index = urls.firstIndex(where: { $0 == oldURL }) {
                urls[index] = newURL
            }
            onCommittedReplacement(oldURL, newURL, message)

            // Clear inplace state
            tempResult = nil
            inplaceSession = nil

            // Re-inspect the replaced file
            await inspect()

            logger.notice(
                "commitInPlace success target=\(newURL.lastPathComponent, privacy: .public)"
            )
        } catch {
            inplaceError = error.localizedDescription
            logger.error("commitInPlace failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func discardInPlace() {
        inplaceSession?.discard()
        inplaceSession = nil
        tempResult = nil
        inplaceError = nil
    }

    private func currentOptions() -> CompressionOptions {
        CompressionOptions(
            outputFormat: outputFormat,
            mode: compressionMode,
            quality: quality,
            resizeLongEdge: resizePreset.longEdge,
            keepMetadata: keepMetadata
        )
    }

    var singleIssueMessage: String? {
        if let error = inplaceError {
            return error
        }
        if let failure = failures.first {
            return failure.1
        }
        if let skipped = skipped.first {
            return skipped.1
        }
        return nil
    }
}

enum ResizePreset: Hashable {
    case original
    case longEdge(Int)

    var longEdge: Int? {
        switch self {
        case .original: nil
        case .longEdge(let value): value
        }
    }
}

private struct SingleImageView: View {
    @ObservedObject var model: CompressionViewModel
    let info: ImageInfo
    let result: CompressionResult?
    @State private var mode = ComparisonMode.sideBySide

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                infoStrip
                Divider()

                if let tempResult = model.tempResult, model.overwriteOriginal {
                    ImageComparisonView(originalURL: info.url, compressedURL: tempResult.outputURL, mode: mode)
                } else if let result {
                    ImageComparisonView(originalURL: info.url, compressedURL: result.outputURL, mode: mode)
                } else {
                    ZStack(alignment: .bottomLeading) {
                        PreviewImage(url: info.url)
                        if let message = model.singleIssueMessage {
                            IssueBanner(message: message)
                                .padding(16)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            if let tempResult = model.tempResult, model.overwriteOriginal {
                InplaceActionPanel(model: model, info: info, tempResult: tempResult)
                    .frame(width: 286)
                    .background(Color(nsColor: .controlBackgroundColor))
            } else {
                CompressionInspector(model: model, info: info, result: result, comparisonMode: $mode)
                    .frame(width: 286)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    private var infoStrip: some View {
        HStack(spacing: 10) {
            InfoPill(title: "Format", value: info.format.displayName)
            InfoPill(title: "Dimensions", value: "\(info.pixelWidth) x \(info.pixelHeight)")
            InfoPill(title: "Size", value: ByteCount.string(info.fileSize))
            InfoPill(title: "Alpha", value: info.hasAlpha ? "Yes" : "No")
            Spacer(minLength: 0)
            if let result {
                InfoPill(title: "Saved", value: "\(Int(result.savedFraction * 100))%")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct CompressionInspector: View {
    @ObservedObject var model: CompressionViewModel
    let info: ImageInfo
    let result: CompressionResult?
    @Binding var comparisonMode: ComparisonMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inspectorSection("Compression") {
                    labeledPicker("Format") {
                        Picker("Format", selection: $model.outputFormat) {
                            ForEach(model.availableOutputFormats, id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)

                        if !model.unavailableOutputFormats.isEmpty {
                            Text(unavailableFormatsText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    labeledPicker("Mode") {
                        Picker("Mode", selection: $model.compressionMode) {
                            ForEach(CompressionMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Quality")
                            Spacer()
                            Text("\(Int(model.quality * 100))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.quality, in: 0.4...1.0)
                    }

                    labeledPicker("Resize") {
                        Picker("Resize", selection: $model.resizePreset) {
                            Text("Original").tag(ResizePreset.original)
                            Text("2560 px").tag(ResizePreset.longEdge(2560))
                            Text("1920 px").tag(ResizePreset.longEdge(1920))
                            Text("1280 px").tag(ResizePreset.longEdge(1280))
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    Toggle("Keep metadata", isOn: $model.keepMetadata)

                    if model.urls.count == 1 {
                        Toggle("Overwrite original", isOn: $model.overwriteOriginal)
                            .onChange(of: model.overwriteOriginal) { _, enabled in
                                if !enabled {
                                    model.discardInPlace()
                                }
                            }
                    }
                }

                inspectorSection("Image") {
                    detailRow("File", info.url.lastPathComponent)
                    detailRow("Color", info.colorSpaceName ?? "Unknown")
                    detailRow("Metadata", info.hasMetadata ? "Yes" : "No")
                }

                if let result {
                    inspectorSection("Output") {
                        detailRow("File", result.outputURL.lastPathComponent)
                        detailRow("Format", result.outputFormat.displayName)
                        detailRow("Size", ByteCount.string(result.compressedSize))
                        detailRow("Savings", "\(Int(result.savedFraction * 100))%")

                        Picker("Compare", selection: $comparisonMode) {
                            ForEach(ComparisonMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .padding(16)
        }
    }

    private var unavailableFormatsText: String {
        let names = model.unavailableOutputFormats.map(\.displayName).joined(separator: ", ")
        return "\(names) output is unavailable on this Mac."
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func labeledPicker<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

private struct InplaceActionPanel: View {
    @ObservedObject var model: CompressionViewModel
    let info: ImageInfo
    let tempResult: CompressionResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Confirm Replacement")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    detailRow("Original", "\(info.url.lastPathComponent) — \(ByteCount.string(info.fileSize))")
                    detailRow("Compressed", "\(tempResult.outputURL.lastPathComponent) — \(ByteCount.string(tempResult.compressedSize))")
                    detailRow("Savings", "\(Int(tempResult.savedFraction * 100))% (\(ByteCount.string(tempResult.savedBytes)))")
                }

                VStack(spacing: 10) {
                    Button {
                        Task { await model.commitInPlace() }
                    } label: {
                        Label("Replace Original", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isWorking)

                    Button {
                        model.discardInPlace()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .controlSize(.large)
                    .disabled(model.isWorking)
                }
                .frame(maxWidth: .infinity)

                if let error = model.inplaceError {
                    IssueBanner(message: error)
                }
            }
            .padding(16)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

private struct InfoPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct IssueBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor))
            )
    }
}

private enum ComparisonMode: CaseIterable {
    case sideBySide
    case slider

    var label: String {
        switch self {
        case .sideBySide: "Side by Side"
        case .slider: "Slider"
        }
    }
}

private struct ImageComparisonView: View {
    let originalURL: URL
    let compressedURL: URL
    let mode: ComparisonMode
    @State private var sliderPosition = 0.5
    @State private var scale = 1.0

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Slider(value: $scale, in: 0.2...2.0)
                    .frame(width: 220)
                Button("100%") { scale = 1.0 }
                Spacer()
            }
            .padding(.horizontal)

            if mode == .sideBySide {
                HStack(spacing: 1) {
                    labeledImage("Original", originalURL)
                    labeledImage("Compressed", compressedURL)
                }
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        PreviewImage(url: compressedURL, scale: scale)
                        PreviewImage(url: originalURL, scale: scale)
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(width: proxy.size.width * sliderPosition)
                            }
                        Rectangle()
                            .fill(.white)
                            .frame(width: 2)
                            .offset(x: proxy.size.width * sliderPosition)
                    }
                    .overlay(alignment: .bottom) {
                        Slider(value: $sliderPosition, in: 0...1)
                            .padding()
                            .background(.regularMaterial)
                    }
                }
            }
        }
    }

    private func labeledImage(_ title: String, _ url: URL) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(.quaternary)
            PreviewImage(url: url, scale: scale)
        }
    }
}

private struct PreviewImage: View {
    let url: URL
    var scale: Double = 1.0

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            GeometryReader { proxy in
                let imageSize = fittedImageSize(image: image, container: proxy.size)

                ZStack {
                    Color(nsColor: .textBackgroundColor)

                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: imageSize.width, height: imageSize.height)
                        .scaleEffect(scale)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ContentUnavailableView("Preview unavailable", systemImage: "photo")
        }
    }

    private func fittedImageSize(image: NSImage, container: CGSize) -> CGSize {
        let padding: CGFloat = 24
        let available = CGSize(
            width: max(container.width - padding * 2, 1),
            height: max(container.height - padding * 2, 1)
        )
        guard image.size.width > 0, image.size.height > 0 else {
            return available
        }
        let factor = min(available.width / image.size.width, available.height / image.size.height)
        return CGSize(width: image.size.width * factor, height: image.size.height * factor)
    }
}

private struct BatchView: View {
    @ObservedObject var model: CompressionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary

                if !model.results.isEmpty {
                    resultSection
                }

                if !model.skipped.isEmpty {
                    issueSection(title: "Skipped", rows: model.skipped)
                }

                if !model.failures.isEmpty {
                    issueSection(title: "Failures", rows: model.failures)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.headline)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                spacing: 10
            ) {
                metric("Selected", model.urls.count)
                metric("Supported", model.infos.count)
                metric("Skipped", model.skipped.count)
                metric("Succeeded", model.results.count)
                metric("Failed", model.failures.count)
            }
            if !model.results.isEmpty {
                HStack(spacing: 18) {
                    Text("Original \(ByteCount.string(model.results.reduce(0) { $0 + $1.originalSize }))")
                    Text("Compressed \(ByteCount.string(model.results.reduce(0) { $0 + $1.compressedSize }))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results")
                .font(.headline)
            ForEach(model.results) { result in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.sourceURL.lastPathComponent)
                            .lineLimit(1)
                        Text("\(ByteCount.string(result.originalSize)) -> \(ByteCount.string(result.compressedSize))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func issueSection(title: String, rows: [(URL, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ForEach(rows, id: \.0) { url, reason in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Text(reason)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }
}

private struct SettingsView: View {
    @State private var monitoredFolders: [URL] = MonitoredFolders.defaults

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monitored Folders")
                .font(.title2)

            List(monitoredFolders, id: \.self) { url in
                Label(url.path, systemImage: "folder")
                    .lineLimit(1)
            }

            HStack {
                Button {
                    addFolder()
                } label: {
                    Label("Add Folder", systemImage: "plus")
                }

                Spacer()

                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                } label: {
                    Label("Open Extension Settings", systemImage: "gearshape")
                }
            }
        }
        .padding()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            monitoredFolders.append(url)
        }
    }
}

enum MonitoredFolders {
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
