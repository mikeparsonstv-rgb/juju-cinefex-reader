import SwiftUI

@main
struct CinefexReaderApp: App {
    @State private var model = AppModel()
    @StateObject private var updates = Updates()

    var body: some Scene {
        Window("Cinefex Reader", id: "reader") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1440, height: 920)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            AboutCommand()
            UpdateCommands(updates: updates)
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Archive") {
                Button("Issues") { model.go("index.html") }.keyboardShortcut("1")
                Button("Browse") { model.go("titles.html") }.keyboardShortcut("2")
                Divider()
                Button("Back") { model.back() }.keyboardShortcut("[")
                Button("Forward") { model.forward() }.keyboardShortcut("]")
                Button("Reload") { model.reload() }.keyboardShortcut("r")
                Divider()
                Button("Library…") { model.openLibrary() }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Install All Issues") { model.installer.start() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Show Library in Finder") { model.revealLibrary() }
                Button("Change Library Folder…") { model.chooseLibraryFolder() }
            }
        }

        Window("About JUJU Cinefex Reader", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
    }
}
