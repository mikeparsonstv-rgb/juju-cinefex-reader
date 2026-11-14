import AppKit
import Observation
import WebKit

@MainActor @Observable
final class AppModel {
    private(set) var showSplash = true
    var showLibrary = false
    /// Where the library panel points: the archive button in the page header (web view coordinates).
    var libraryAnchor = CGRect(x: 0, y: 0, width: 1, height: 1)
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var libraryPath: String
    private(set) var startupError: String? = nil

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored let installer: Installer
    @ObservationIgnored let store: MediaStore
    @ObservationIgnored private let coordinator = WebCoordinator()
    @ObservationIgnored private let saveFolders = SaveFolderBridge()
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private let launched = Date()
    @ObservationIgnored private var lastInstallJS = ""

    init() {
        let library = LibraryLocation.current
        libraryPath = library.path
        var manifest: Manifest
        do {
            manifest = try Manifest(contentsOf: Bundle.main.url(forResource: "manifest", withExtension: "json")
                                    ?? URL(fileURLWithPath: "/nonexistent/manifest.json"))
        } catch {
            startupError = "The archive index is missing from the app bundle. Run tools/prepare-reader.py and rebuild."
            manifest = try! Manifest.empty()
        }
        store = MediaStore(manifest: manifest, library: library)
        installer = Installer(store: store)

        let readerRoot = Bundle.main.url(forResource: "Reader", withExtension: nil)
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Reader")
        let handler = ReaderSchemeHandler(readerRoot: readerRoot, store: store)

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(handler, forURLScheme: ReaderSchemeHandler.scheme)
        config.websiteDataStore = .default()          // keeps bookmarks, read marks and position
        config.preferences.isElementFullscreenEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = false
        config.userContentController.add(coordinator, name: "juju")
        config.userContentController.addScriptMessageHandler(saveFolders, contentWorld: .page, name: "jujuFS")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = NSColor(srgbRed: 0x1e / 255, green: 0x21 / 255, blue: 0x1e / 255, alpha: 1)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinator.model = self

        observers = [
            webView.observe(\.canGoBack) { [weak self] wv, _ in Task { @MainActor in self?.canGoBack = wv.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] wv, _ in Task { @MainActor in self?.canGoForward = wv.canGoForward } },
        ]
        webView.load(URLRequest(url: ReaderSchemeHandler.home))
        installer.check()
        Task { @MainActor [weak self] in            // install progress for the archive button in the page
            while true {
                guard let self else { return }
                self.pushInstallState()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    /// Sends busy / fraction / complete to the page when it changes (the archive button draws it).
    func pushInstallState(force: Bool = false) {
        let js = String(format: "window.jujuInstall&&jujuInstall({busy:%@,fraction:%.4f,complete:%@})",
                        installer.isBusy ? "true" : "false", Double(installer.fraction),
                        installer.isComplete ? "true" : "false")
        guard force || js != lastInstallJS else { return }
        lastInstallJS = js
        webView.evaluateJavaScript(js)
    }

    // MARK: Navigation

    func go(_ page: String) {
        webView.evaluateJavaScript("location.hash = encodeURIComponent(\(Self.jsString(page)))")
    }
    func back() { webView.goBack() }
    func forward() { webView.goForward() }
    func reload() { webView.reload() }

    func readerFinishedLoading() {
        pushInstallState(force: true)
        guard showSplash else { return }
        let wait = max(0, 1.4 - Date().timeIntervalSince(launched))
        Task {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            showSplash = false
        }
    }

    func handle(message: [String: Any]) {
        switch message["action"] as? String {
        case "library":
            let r = (message["rect"] as? [NSNumber])?.map { CGFloat($0.doubleValue) }
            openLibrary(from: r?.count == 4 ? CGRect(x: r![0], y: r![1], width: r![2], height: r![3]) : nil)
        case "issue": if let n = message["issue"] as? Int { store.prefetchIssue(n) }
        default: break
        }
    }

    // MARK: Library folder

    /// Shows the library panel under the archive button (or near the top right when opened from the menu).
    func openLibrary(from rect: CGRect? = nil) {
        libraryAnchor = rect ?? CGRect(x: max(0, webView.bounds.width - 80), y: 24, width: 34, height: 34)
        showLibrary = true
    }

    func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose where the Cinefex archive is kept."
        panel.directoryURL = URL(fileURLWithPath: libraryPath).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        installer.stop()
        LibraryLocation.set(url)
        store.setLibrary(url)
        libraryPath = url.path
        installer.check()
        webView.reload()
    }

    func revealLibrary() {
        let url = URL(fileURLWithPath: libraryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        return String(data: data ?? Data("[\"\"]".utf8), encoding: .utf8).map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }
}

extension Manifest {
    static func empty() throws -> Manifest {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cinefex-empty-manifest.json")
        try Data(#"{"assets":[],"posters":{}}"#.utf8).write(to: url)
        return try Manifest(contentsOf: url)
    }
}

/// Web view delegate: keeps the reader inside the app and opens outside links in the browser.
@MainActor
final class WebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var model: AppModel?
    private let saver = DownloadSaver()

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        if action.shouldPerformDownload { return .download }      // "Save PDF" and "Save ZIP" links
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return .allow }
        if ["cinefex", "about", "blob", "data"].contains(scheme) { return .allow }
        NSWorkspace.shared.open(url)
        return .cancel
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        response.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = saver
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = saver
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.scheme != ReaderSchemeHandler.scheme { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        model?.readerFinishedLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        model?.readerFinishedLoading()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        model?.handle(message: body)
    }
}
