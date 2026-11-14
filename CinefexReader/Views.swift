import SwiftUI
import WebKit

struct ReaderWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            ReaderWebView(webView: model.webView)
                .popover(isPresented: $model.showLibrary,
                         attachmentAnchor: .rect(.rect(model.libraryAnchor)), arrowEdge: .bottom) {
                    LibraryPanel(installer: model.installer).environment(model)
                }
            if model.showSplash {
                SplashView(installer: model.installer, error: model.startupError)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.6), value: model.showSplash)
        .background(Color(red: 0x1e / 255, green: 0x21 / 255, blue: 0x1e / 255))
        .frame(minWidth: 900, minHeight: 600)
        .modifier(ReaderToolbar())
    }
}

/// Back and forward as bare icons, like the Issues / Browse / Search links in the page.
/// macOS 26 puts toolbar buttons in grey glass capsules; that background is switched off there.
struct ReaderToolbar: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    back
                    forward
                }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    back
                    forward
                }
            }
        }
    }

    private var back: some View {
        IconButton(symbol: "chevron.left", help: "Back") { model.back() }.disabled(!model.canGoBack)
    }
    private var forward: some View {
        IconButton(symbol: "chevron.right", help: "Forward") { model.forward() }.disabled(!model.canGoForward)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hover && enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .opacity(enabled ? 1 : 0.35)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// The cover mosaic, full bleed, while the reader opens.
struct SplashView: View {
    let installer: Installer
    let error: String?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Color.black
                Image("Splash")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                Text(error ?? "Opening the archive")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(28)
            }
        }
        .ignoresSafeArea()
    }
}

/// Toolbar button: a ring that fills while the archive installs.
struct InstallBadge: View {
    let installer: Installer
    var body: some View {
        if installer.isBusy {
            ProgressView(value: installer.fraction)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: installer.isComplete ? "books.vertical.fill" : "arrow.down.circle")
        }
    }
}

struct LibraryPanel: View {
    @Environment(AppModel.self) private var model
    let installer: Installer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ARCHIVE")
                .font(.system(size: 11, weight: .semibold)).tracking(0.6)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(installer.fraction, format: .percent.precision(.fractionLength(installer.isBusy ? 1 : 0)))
                    .font(.system(size: 40, weight: .thin)).monospacedDigit()
                Text("installed").font(.system(size: 13)).foregroundStyle(.secondary)
            }

            ProgressView(value: installer.fraction).progressViewStyle(.linear)

            VStack(alignment: .leading, spacing: 6) {
                row("Files", "\(installer.present.formatted()) of \(installer.total.formatted())")
                row("Size", "\(bytes(installer.bytesPresent)) of \(bytes(installer.bytesTotal))")
                if installer.phase == .downloading, installer.rate > 0 {
                    row("Speed", "\(bytes(Int64(installer.rate)))/s · \(remaining)")
                }
                if installer.phase == .posters || installer.postersDone > 0 {
                    row("Posters", "\(installer.postersDone) of \(installer.postersTotal)")
                }
                if installer.failed > 0 { row("Not fetched", "\(installer.failed)") }
            }
            .font(.system(size: 12)).monospacedDigit()

            Text(installer.note).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if installer.isBusy {
                    Button("Pause") { installer.stop() }.keyboardShortcut(.defaultAction)
                } else if !installer.isComplete {
                    Button(installer.present > 0 ? "Continue Install" : "Install All Issues") { installer.start() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Check Again") { installer.start() }
                }
                Spacer()
                Button("Show in Finder") { model.revealLibrary() }
                Button("Change…") { model.chooseLibraryFolder() }.disabled(installer.isBusy)
            }
            .controlSize(.regular)

            Text(model.libraryPath)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
        }
        .padding(24)
        .frame(width: 380)
    }

    private var remaining: String {
        guard installer.rate > 0 else { return "" }
        let secs = Double(installer.bytesTotal - installer.bytesPresent) / installer.rate
        let f = DateComponentsFormatter()
        f.allowedUnits = secs > 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        return (f.string(from: secs) ?? "") + " left"
    }

    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 16) {
            Text(label).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Text(value)
        }
    }
}
