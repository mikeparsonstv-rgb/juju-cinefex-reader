import Combine
import Sparkle
import SwiftUI

/// Sparkle: checks the GitHub feed once a day and offers new versions; "Check for Updates…" in the app menu.
/// The updater only starts once tools/setup-updates.sh has put the public signing key in Info.plist.
@MainActor
final class Updates: ObservableObject {
    @Published private(set) var canCheck = false
    private let controller: SPUStandardUpdaterController?

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { controller = nil; return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func check() { controller?.checkForUpdates(nil) }
}

struct UpdateCommands: Commands {
    @ObservedObject var updates: Updates

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updates.check() }
                .disabled(!updates.canCheck)
        }
    }
}
