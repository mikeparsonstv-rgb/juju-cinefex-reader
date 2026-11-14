import AppKit
import WebKit

/// Native stand-in for the browser's folder picker, used by the reader's "Build all PDFs".
/// The page asks for a folder once (a normal Mac open panel); afterwards it can only create folders
/// and write files inside that folder, addressed by relative path.
@MainActor
final class SaveFolderBridge: NSObject, WKScriptMessageHandlerWithReply {
    private var folders: [String: URL] = [:]

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
            return (nil, "Bad request")
        }
        if op == "pick" { return (pick(), nil) }
        guard let token = body["token"] as? String, let root = folders[token],
              let path = body["path"] as? String, let url = Self.resolve(path, in: root) else {
            return (nil, "That folder is no longer available.")
        }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
        let create = body["create"] as? Bool ?? false
        do {
            switch op {
            case "dir":
                if exists { return (isDir.boolValue ? "dir" : "file", nil) }
                guard create else { return ("missing", nil) }
                try fm.createDirectory(at: url, withIntermediateDirectories: false)
                return ("dir", nil)
            case "file":
                if exists { return (isDir.boolValue ? "dir" : "file", nil) }
                guard create else { return ("missing", nil) }
                guard fm.createFile(atPath: url.path, contents: nil) else { return (nil, "Could not create \(url.lastPathComponent).") }
                return ("file", nil)
            case "write":
                guard let text = body["data"] as? String, let data = Data(base64Encoded: text) else {
                    return (nil, "Bad data")
                }
                if body["append"] as? Bool == true {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: url)
                }
                return (true, nil)
            case "remove":
                if exists { try fm.removeItem(at: url) }
                return (true, nil)
            default:
                return (nil, "Unknown request")
            }
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func pick() -> [String: String]? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save PDFs Here"
        panel.message = "Choose where to save the PDFs. A “Cinefex PDFs” folder is made inside it."
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let token = UUID().uuidString
        folders[token] = url
        return ["token": token, "name": url.lastPathComponent]
    }

    /// Relative path inside the chosen folder only: no empty, "." or ".." parts.
    private static func resolve(_ path: String, in root: URL) -> URL? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        return parts.reduce(root) { $0.appendingPathComponent($1) }
    }
}

/// Saves downloads the reader starts (a single issue's PDF, or the catalogue ZIP) with a save panel.
@MainActor
final class DownloadSaver: NSObject, WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        // The panel has already asked about replacing; WebKit won't write over an existing file.
        try? FileManager.default.removeItem(at: url)
        return url
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        let alert = NSAlert(error: error)
        alert.messageText = "The file could not be saved."
        alert.runModal()
    }
}
