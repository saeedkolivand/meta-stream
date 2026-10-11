// The imported pack (JSON in Application Support), the files copied next to it, and which scene is active.
// Counts and types only reach the log: browser-source URLs carry account tokens.
import Combine
import Foundation

@MainActor
final class OverlayStore: ObservableObject {
    static let shared = OverlayStore()

    @Published private(set) var pack: OverlayPack?
    /// Active scene name; empty means none.
    @Published private(set) var scene = ""
    /// Import/locate result for the settings screen.
    @Published private(set) var message = ""
    @Published private(set) var busy = false
    /// Bumped whenever the pack or the files behind it change, so the compositor rebuilds.
    @Published private(set) var revision = 0

    private let dir = URL.applicationSupportDirectory.appending(path: "overlays")
    private var filesDir: URL { dir.appending(path: "files") }
    private var packURL: URL { dir.appending(path: "pack.json") }

    private init() {
        scene = UserDefaults.standard.string(forKey: "overlayScene") ?? ""
        if let data = try? Data(contentsOf: packURL) { pack = try? JSONDecoder().decode(OverlayPack.self, from: data) }
    }

    var activeScene: OverlayScene? { pack?.scenes.first { $0.name == scene } }

    func select(_ name: String) {
        scene = name
        UserDefaults.standard.set(name, forKey: "overlayScene")
    }

    /// Local copy of a file a scene names by its PC path, or nil while it hasn't been located.
    func local(_ path: String) -> URL? {
        let u = filesDir.appending(path: overlayBaseName(path))
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    var missing: [String] { (pack?.files ?? []).filter { local($0) == nil }.sorted() }

    // MARK: import

    func importPack(from url: URL) async {
        busy = true
        defer { busy = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let parsed = await Task.detached { Self.readCoordinated(url).flatMap { try? parseObs(String(decoding: $0, as: UTF8.self)) } }.value
        guard let parsed, !parsed.scenes.isEmpty else {
            message = "That file isn't an OBS scene collection"
            return
        }
        do {
            try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
            var d = dir
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true   // the pack holds tokenised URLs: keep it out of iCloud/iTunes backups
            try? d.setResourceValues(rv)
            try JSONEncoder().encode(parsed).write(to: packURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            message = "Couldn't save the import"
            return
        }
        pack = parsed
        if !parsed.scenes.contains(where: { $0.name == scene }) { select("") }
        revision += 1
        let layers = parsed.scenes.reduce(0) { $0 + $1.layers.count }
        applog("overlay", "imported \(parsed.scenes.count) scenes, \(layers) layers, \(parsed.skippedCount) skipped")
        message = (["Imported \(parsed.scenes.count) scenes, \(layers) layers.", parsed.skippedText, missingText()]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func missingText() -> String {
        let n = missing.count
        return n == 0 ? "" : "\(n) files not found: tap Locate files."
    }

    // MARK: locate files

    /// Copies every missing file whose name appears anywhere under `folder` into app storage. The folder may live in
    /// iCloud Drive: the picked URL is security-scoped, and a coordinated read downloads a file that isn't local yet.
    func locate(in folder: URL) async {
        let wanted = Dictionary(missing.map { (overlayBaseName($0).lowercased(), overlayBaseName($0)) }, uniquingKeysWith: { a, _ in a })
        guard !wanted.isEmpty else { return }
        busy = true
        defer { busy = false }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let dest = filesDir
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let found = await Task.detached { Self.copyMatches(root: folder, wanted: wanted, dest: dest) }.value
        revision += 1
        applog("overlay", "located \(found) of \(wanted.count) files")
        message = "Copied \(found) of \(wanted.count) files. \(missingText())".trimmingCharacters(in: .whitespaces)
    }

    // File work is synchronous (FileManager's enumerator can't be iterated from async code), so it runs detached.

    nonisolated private static func readCoordinated(_ url: URL) -> Data? {
        nonisolated(unsafe) var data: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { data = try? Data(contentsOf: $0) }
        return data
    }

    /// `wanted` maps lowercased file name -> the spelling the scene uses (saved under that, since `local` looks it up exactly).
    nonisolated private static func copyMatches(root: URL, wanted: [String: String], dest: URL) -> Int {
        let fm = FileManager.default
        // Hidden files stay in: an iCloud file that isn't downloaded yet shows up as a ".name.icloud" placeholder.
        guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return 0 }
        var found = 0
        for case let url as URL in walk {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
            var name = url.lastPathComponent
            var real = url
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
                real = url.deletingLastPathComponent().appending(path: name)
                try? fm.startDownloadingUbiquitousItem(at: real)
            }
            guard let spelled = wanted[name.lowercased()] else { continue }
            let target = dest.appending(path: spelled)
            if fm.fileExists(atPath: target.path) { continue }
            nonisolated(unsafe) var copied = false
            var err: NSError?
            NSFileCoordinator().coordinate(readingItemAt: real, options: [], error: &err) { copied = (try? fm.copyItem(at: $0, to: target)) != nil }
            if copied { found += 1 }
        }
        return found
    }
}
