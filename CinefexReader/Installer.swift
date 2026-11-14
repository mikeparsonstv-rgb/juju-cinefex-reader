import Foundation
import Observation

/// Installs the whole archive into the library folder: every file the reader uses, the repairs for
/// issues 11–16, and the video posters. Resumable; files already present are skipped. Uses the same
/// layout as tools/cinefex-download.py, so either can finish what the other started.
@MainActor @Observable
final class Installer {
    enum Phase: Equatable { case idle, checking, downloading, repairing, posters, finished, stopped }

    private(set) var phase: Phase = .idle
    private(set) var present = 0
    private(set) var total = 0
    private(set) var bytesPresent: Int64 = 0
    private(set) var bytesTotal: Int64 = 0
    private(set) var failed = 0
    private(set) var postersDone = 0
    private(set) var postersTotal = 0
    private(set) var rate: Double = 0          // bytes per second while downloading
    private(set) var note = ""

    @ObservationIgnored private let store: MediaStore
    @ObservationIgnored private var job: Task<Void, Never>?

    static let repairURL = URL(string:
        "https://archive.org/download/cinefex-reader-repairs-011-016/Cinefex%20Reader%20Repairs%20011-016.zip")!

    init(store: MediaStore) { self.store = store }

    var isBusy: Bool { [.checking, .downloading, .repairing, .posters].contains(phase) }
    var fraction: Double { bytesTotal > 0 ? min(1, Double(bytesPresent) / Double(bytesTotal)) : 0 }
    var isComplete: Bool { total > 0 && present == total }

    /// Count what is already in the library.
    func check() {
        guard !isBusy else { return }
        job = Task {
            _ = await self.survey()
            if self.phase == .checking { self.phase = self.isComplete ? .finished : .idle }
        }
    }

    func start() {
        guard !isBusy else { return }
        job = Task { await self.run() }
    }

    func stop() {
        job?.cancel()
        phase = .stopped
        note = "Paused. Start again to carry on where it stopped."
    }

    // MARK: -

    private func survey() async -> [Asset] {
        phase = .checking
        note = "Checking the library…"
        let store = self.store
        let list = store.manifest.downloadable
        total = list.count
        bytesTotal = list.reduce(0) { $0 + Int64($1.size) }
        let result = await Task.detached(priority: .userInitiated) { () -> (Int, Int64, [Asset]) in
            var count = 0, bytes: Int64 = 0, missing = [Asset]()
            for a in list { if store.isPresent(a) { count += 1; bytes += Int64(a.size) } else { missing.append(a) } }
            return (count, bytes, missing)
        }.value
        present = result.0; bytesPresent = result.1
        postersTotal = store.manifest.posters.count
        note = isComplete ? "All \(total.formatted()) files are installed." : "\((total - present).formatted()) files to install."
        return result.2
    }

    private func run() async {
        let missing = await survey()
        if Task.isCancelled { return }

        // 1. Everything the reader uses.
        var failures = [Asset]()
        if !missing.isEmpty {
            phase = .downloading
            note = "Downloading from Internet Archive…"
            let counter = Counter()
            let basePresent = present, baseBytes = bytesPresent
            let started = Date()
            let poll = Task { @MainActor in
                while !Task.isCancelled {
                    self.absorb(counter.snapshot(), basePresent, baseBytes, started)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            await store.fetchAll(missing, width: 10) { a, ok in counter.record(a, ok) }
            poll.cancel()
            let snap = counter.snapshot()
            absorb(snap, basePresent, baseBytes, started)
            failures = snap.failures
            if Task.isCancelled { return }
        }

        // 2. Files that are damaged on Internet Archive come from the reader's repair ZIP.
        if !failures.isEmpty {
            phase = .repairing
            note = "Applying the repairs for \(failures.count) files…"
            let fixed = await Self.repair(failures, store: store)
            present += fixed.count
            bytesPresent += fixed.reduce(0) { $0 + Int64($1.size) }
            failures.removeAll { fixed.contains($0) }
        }
        failed = failures.count
        if Task.isCancelled { return }

        // 3. Video posters.
        phase = .posters
        let posters = Array(store.manifest.posters.keys).sorted()
        postersTotal = posters.count
        postersDone = 0
        for p in posters {
            if Task.isCancelled { return }
            note = "Making video posters…"
            _ = await store.poster(path: p)
            postersDone += 1
        }

        phase = .finished
        rate = 0
        note = failed == 0 ? "All \(total.formatted()) files are installed."
                           : "Installed. \(failed) files could not be fetched; they will be tried again next time."
        if failed > 0 { writeFailures(failures) }
    }

    private func absorb(_ s: Counter.Snapshot, _ basePresent: Int, _ baseBytes: Int64, _ started: Date) {
        present = basePresent + s.ok
        bytesPresent = baseBytes + s.bytes
        failed = s.failures.count
        let t = Date().timeIntervalSince(started)
        if t > 2 { rate = Double(s.bytes) / t }
    }

    private func writeFailures(_ list: [Asset]) {
        let text = list.map { "\($0.path)\t\($0.url)" }.joined(separator: "\n")
        try? text.write(to: store.libraryURL.appendingPathComponent("install-failures.txt"), atomically: true, encoding: .utf8)
    }

    /// Downloads and unpacks the repair ZIP, then places each file whose size and CRC match.
    nonisolated static func repair(_ wanted: [Asset], store: MediaStore) async -> [Asset] {
        let fm = FileManager.default
        let library = store.libraryURL
        let zip = library.appendingPathComponent("Cinefex Reader Repairs 011-016.zip")
        if !fm.fileExists(atPath: zip.path) {
            guard let result = try? await URLSession.shared.download(from: repairURL),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            try? fm.createDirectory(at: library, withIntermediateDirectories: true)
            try? fm.moveItem(at: result.0, to: zip)
        }
        let unpacked = fm.temporaryDirectory.appendingPathComponent("cinefex-repairs-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: unpacked) }
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        guard (try? ditto.run()) != nil else { return [] }
        ditto.waitUntilExit()

        var bySignature = [String: Asset]()
        for a in wanted { bySignature["\(a.size):\(a.crc)"] = a }
        var fixed = [Asset]()
        let files = fm.enumerator(at: unpacked, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        while let url = files?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true, let size = values.fileSize,
                  wanted.contains(where: { $0.size == size }),
                  let data = try? Data(contentsOf: url),
                  let a = bySignature["\(size):\(CRC32.of(data))"] else { continue }
            store.store(data, path: a.path)
            fixed.append(a)
        }
        return fixed
    }
}

/// Thread-safe tally fed by the download workers.
final class Counter: @unchecked Sendable {
    struct Snapshot { var ok = 0; var bytes: Int64 = 0; var failures: [Asset] = [] }
    private let lock = NSLock()
    private var s = Snapshot()
    func record(_ a: Asset, _ ok: Bool) {
        lock.withLock { if ok { s.ok += 1; s.bytes += Int64(a.size) } else { s.failures.append(a) } }
    }
    func snapshot() -> Snapshot { lock.withLock { s } }
}
