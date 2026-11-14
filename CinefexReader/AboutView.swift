import SwiftUI

/// App > About JUJU Cinefex Reader: the artwork, version and credits.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image("AboutArt")
                .resizable()
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 320, height: 320)
                .overlay(Rectangle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
                .accessibilityLabel("The JUJU dog reading Cinefex 172 and Cinefex number 1")
                .padding(.top, 40)

            Text("JUJU Cinefex Reader")
                .font(.system(size: 22, weight: .semibold))
                .kerning(-0.4)
                .padding(.top, 28)
            Text(version)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.top, 4)

            VStack(spacing: 6) {
                Text("All 172 issues of Cinefex, 1980–2021, on your Mac.")
                    .foregroundStyle(.primary)
                credit("Reader by Emmett Redding", url: "https://github.com/holmesredding/cinefex-reader")
                credit("Magazine files from Internet Archive", url: "https://archive.org/details/cinefex-index")
                Text("Mac app and extra indexing by JUJU VFX")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
            .padding(.top, 20)

            Text("JUJU Cinefex Reader © 2026 JUJU VFX. All rights reserved.\nCinefex is © Cinefex. This reader is not affiliated with Cinefex.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .padding(.bottom, 32)
        }
        .padding(.horizontal, 44)
        .frame(width: 440)
        .textSelection(.enabled)
    }

    private func credit(_ title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Text(title).underline(false)
        }
        .foregroundStyle(.secondary)
        .help(url)
    }
}

/// Replaces the standard About item so it opens the window above.
struct AboutCommand: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About JUJU Cinefex Reader") { openWindow(id: "about") }
        }
    }
}
