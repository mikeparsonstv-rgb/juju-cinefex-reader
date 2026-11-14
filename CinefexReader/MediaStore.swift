import Foundation
import AVFoundation
import AppKit

/// Where the archive lives. Defaults to the RAID folder, falls back to Application Support.
enum LibraryLocation {
    private static let key = "libraryPath"
    static let preferred = URL(fileURLWithPath:
        "/Volumes/EDITBOX-RAID/APP DEV Claude Codex etc/CINEFEX archive/Cinefex Library", isDirectory: true)

    static var current: URL {
        if let p = UserDefaults.standard.string(forKey: key) { return URL(fileURLWithPath: p, isDirectory: true) }
        if FileManager.default.fileExists(atPath: preferred.deletingLastPathComponent().path) { return preferred }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("JUJU Cinefex Reader/Library", isDirectory: true)
    }
    static func set(_ url: URL) { UserDefaults.standard.set(url.path, forKey: key) }
}

/// Reads media from the library folder; anything missing is fetched from Internet Archive once,
/// checked against its size and CRC, and kept. Thread-safe; file reads never queue behind downloads.
final class MediaStore: @unchecked Sendable {
    let manifest: Manifest
    private let lock = NSLock()
    private var library: URL
    private var inflight: [String: Task<Data?, Never>] = [:]
    private var prefetched = Set<Int>()
    private let session: URLSession
    private static let userAgent = "JUJU-Cinefex-Reader/1.0 (personal archive mirror)"

    init(manifest: Manifest, library: URL) {
        self.manifest = manifest
        self.library = library
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 10
        config.timeoutIntervalForRequest = 120
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    var libraryURL: URL { lock.withLock { library } }
    var mediaURL: URL { libraryURL.appendingPathComponent("media", isDirectory: true) }

    func setLibrary(_ url: URL) { lock.withLock { library = url; prefetched.removeAll() } }

    func fileURL(_ path: String) -> URL { mediaURL.appendingPathComponent(path) }

    func isPresent(_ a: Asset) -> Bool {
        guard let n = (try? FileManager.default.attributesOfItem(atPath: fileURL(a.path).path))?[.size] as? NSNumber
        else { return false }
        return n.intValue == a.size
    }

    // MARK: Reader requests

    /// Bytes for a rewritten Internet Archive URL (key = percent-decoded URL).
    func data(forKey key: String) async -> Data? {
        guard let a = manifest.byKey[key] else { return nil }
        return await data(for: a)
    }

    func data(for a: Asset) async -> Data? {
        if let d = try? Data(contentsOf: fileURL(a.path), options: .mappedIfSafe), d.count == a.size { return d }
        return await download(a)
    }

    /// Video poster frames are not on Internet Archive; make them from the clip and keep them.
    func poster(path: String) async -> Data? {
        let file = fileURL(path)
        if let d = try? Data(contentsOf: file), !d.isEmpty { return d }
        guard let clipURL = manifest.posters[path], let clip = manifest.byKey[Manifest.key(clipURL)],
              await data(for: clip) != nil,
              let jpeg = await Self.makePoster(from: fileURL(clip.path)) else { return nil }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpeg.write(to: file, options: .atomic)
        return jpeg
    }

    /// Pull an issue's missing files in the background as soon as it is opened.
    func prefetchIssue(_ n: Int) {
        guard lock.withLock({ prefetched.insert(n).inserted }) else { return }
        Task.detached(priority: .utility) {
            let prefix = "issues/\(n)/"
            let missing = self.manifest.downloadable.filter { $0.path.hasPrefix(prefix) && !self.isPresent($0) }
            if !missing.isEmpty { await self.fetchAll(missing, width: 6) }
        }
    }

    // MARK: Downloading

    /// One download per file, however many callers ask for it at once.
    func download(_ a: Asset) async -> Data? {
        let task: Task<Data?, Never> = lock.withLock {
            if let t = inflight[a.path] { return t }
            let t = Task<Data?, Never> { await self.fetch(a) }
            inflight[a.path] = t
            return t
        }
        let d = await task.value
        lock.withLock { if inflight[a.path] == task { inflight[a.path] = nil } }
        return d
    }

    private func fetch(_ a: Asset) async -> Data? {
        guard let url = URL(string: a.url) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        for attempt in 0..<4 {
            do {
                let (data, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 404 { return nil }
                if code == 200 {
                    // A damaged upstream copy is shown but not kept; the installer's repair pass replaces it.
                    if data.count == a.size && CRC32.of(data) == a.crc { store(data, path: a.path) }
                    return data
                }
            } catch {}
            try? await Task.sleep(nanoseconds: UInt64(2 << attempt) * 1_000_000_000)
        }
        return nil
    }

    func store(_ data: Data, path: String) {
        let file = fileURL(path)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// Downloads a list with a fixed number in flight. `progress` is called for each file as it lands.
    func fetchAll(_ list: [Asset], width: Int, progress: (@Sendable (Asset, Bool) -> Void)? = nil) async {
        await withTaskGroup(of: (Asset, Bool).self) { group in
            var next = 0
            while next < min(width, list.count) {
                let a = list[next]; next += 1
                group.addTask { (a, await self.download(a) != nil && self.isPresent(a)) }
            }
            while let result = await group.next() {
                progress?(result.0, result.1)
                if Task.isCancelled { group.cancelAll(); continue }
                if next < list.count {
                    let a = list[next]; next += 1
                    group.addTask { (a, await self.download(a) != nil && self.isPresent(a)) }
                }
            }
        }
    }

    // MARK: Posters

    static func makePoster(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        var time = CMTime(seconds: 1, preferredTimescale: 600)
        if let d = try? await asset.load(.duration), d.seconds.isFinite, d.seconds > 0 {
            time = CMTime(seconds: min(1, d.seconds * 0.1), preferredTimescale: 600)
        }
        guard let result = try? await generator.image(at: time) else { return nil }
        return NSBitmapImageRep(cgImage: result.image).representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}
