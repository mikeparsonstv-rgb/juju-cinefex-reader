import Foundation

/// One media file the reader can ask for.
struct Asset: Sendable, Hashable {
    let url: String      // the Internet Archive URL, exactly as the reader's data uses it
    let path: String     // where it lives under <library>/media
    let size: Int
    let crc: UInt32
    var isLocalOnly: Bool { url.hasPrefix("local-media:") }
}

/// Built from the reader's data by tools/make-manifest.py and bundled with the app.
final class Manifest: @unchecked Sendable {
    static let iaPrefix = "https://archive.org/download/"

    let assets: [Asset]
    let downloadable: [Asset]
    let byKey: [String: Asset]      // percent-decoded Internet Archive URL -> asset
    let posters: [String: String]   // poster path -> the clip's Internet Archive URL

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["assets"] as? [[Any]] else { throw CocoaError(.fileReadCorruptFile) }
        var list = [Asset](); list.reserveCapacity(rows.count)
        var keys = [String: Asset](minimumCapacity: rows.count)
        for row in rows {
            guard row.count == 4, let u = row[0] as? String, let p = row[1] as? String,
                  let s = row[2] as? NSNumber, let c = row[3] as? NSNumber else { continue }
            let a = Asset(url: u, path: p, size: s.intValue, crc: UInt32(truncatingIfNeeded: c.int64Value))
            list.append(a)
            if !a.isLocalOnly { keys[Manifest.key(u)] = a }
        }
        assets = list
        downloadable = list.filter { !$0.isLocalOnly }
        byKey = keys
        posters = root["posters"] as? [String: String] ?? [:]
    }

    /// Lookup key: the URL with percent-escapes removed, which is what WebKit hands the scheme handler.
    static func key(_ url: String) -> String { url.removingPercentEncoding ?? url }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func of(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw -> UInt32 in
            var c: UInt32 = 0xFFFF_FFFF
            table.withUnsafeBufferPointer { t in
                for byte in raw { c = t[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
            }
            return c ^ 0xFFFF_FFFF
        }
    }
}
