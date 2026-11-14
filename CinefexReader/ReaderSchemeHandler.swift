import Foundation
import WebKit

/// Serves cinefex://reader/…
///   /__ia/<item>/<file>   Internet Archive media, from the library folder (fetched once if missing)
///   /__local/<path>       video posters, generated from the clip on first use
///   anything else         the bundled reader
@MainActor
final class ReaderSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "cinefex"
    static let home = URL(string: "cinefex://reader/session.html#index.html")!

    let readerRoot: URL
    let store: MediaStore
    private var live = Set<ObjectIdentifier>()

    init(readerRoot: URL, store: MediaStore) {
        self.readerRoot = readerRoot
        self.store = store
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        live.insert(id)
        guard let url = task.request.url else { return }
        let path = url.path(percentEncoded: false)
        let range = task.request.value(forHTTPHeaderField: "Range")
        let root = readerRoot, store = store
        Task.detached(priority: .userInitiated) {
            let reply = await Self.respond(path: path, root: root, store: store)
            await MainActor.run { self.deliver(reply, range: range, url: url, task: task, id: id) }
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        live.remove(ObjectIdentifier(task))
    }

    struct Reply: Sendable { let data: Data?; let mime: String }

    nonisolated static func respond(path: String, root: URL, store: MediaStore) async -> Reply {
        if path.hasPrefix("/__ia/") {
            let key = Manifest.iaPrefix + path.dropFirst("/__ia/".count)
            return Reply(data: await store.data(forKey: key), mime: mime(for: path))
        }
        if path.hasPrefix("/__local/") {
            return Reply(data: await store.poster(path: String(path.dropFirst("/__local/".count))), mime: "image/jpeg")
        }
        var rel = String(path.drop(while: { $0 == "/" }))
        if rel.isEmpty { rel = "index.html" }
        guard !rel.split(separator: "/").contains("..") else { return Reply(data: nil, mime: "text/plain") }
        let data = try? Data(contentsOf: root.appendingPathComponent(rel), options: .mappedIfSafe)
        return Reply(data: data, mime: mime(for: rel))
    }

    private func deliver(_ reply: Reply, range: String?, url: URL, task: any WKURLSchemeTask, id: ObjectIdentifier) {
        guard live.remove(id) != nil else { return }      // WebKit already cancelled it
        guard let data = reply.data else {
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1",
                                    headerFields: ["Content-Type": "text/plain", "Content-Length": "0"])!
            task.didReceive(r); task.didReceive(Data()); task.didFinish()
            return
        }
        var body = data, status = 200
        var headers = ["Content-Type": reply.mime,
                       "Cache-Control": "max-age=31536000, immutable",
                       "Accept-Ranges": "bytes",
                       "Access-Control-Allow-Origin": "*"]
        if let range, let r = Self.byteRange(range, count: data.count) {
            body = data.subdata(in: r); status = 206
            headers["Content-Range"] = "bytes \(r.lowerBound)-\(r.upperBound - 1)/\(data.count)"
        }
        headers["Content-Length"] = String(body.count)
        task.didReceive(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(body)
        task.didFinish()
    }

    nonisolated static func byteRange(_ header: String, count: Int) -> Range<Int>? {
        guard count > 0, header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst(6).split(separator: ",").first ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty, let suffix = Int(parts[1]) { return max(0, count - suffix)..<count }
        guard let start = Int(parts[0]), start < count else { return nil }
        let end = Int(parts[1]).map { min($0, count - 1) } ?? count - 1
        return end >= start ? start..<(end + 1) : nil
    }

    nonisolated static func mime(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        case "mp4", "m4v": return "video/mp4"
        case "otf": return "font/otf"
        case "ttf": return "font/ttf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }
}
