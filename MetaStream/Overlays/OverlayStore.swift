// The imported pack (JSON in Application Support), the files copied next to it, and which scene is active.
// Counts and types only reach the log: browser-source URLs carry account tokens.
import Combine
import CoreGraphics
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

    /// "fade" | "cut" | "stinger": how overlays change when the scene does. Defaults-backed, not part of pack.json.
    @Published var transition: String { didSet { UserDefaults.standard.set(transition, forKey: "sceneTransition") } }
    /// The stinger clip (a name under files/, "" = none) and where in it the scene changes, 0.1...0.9 of its length.
    @Published var stingerFile: String { didSet { UserDefaults.standard.set(stingerFile, forKey: "stingerFile") } }
    @Published var stingerCut: Double { didSet { UserDefaults.standard.set(stingerCut, forKey: "stingerCut") } }
    /// A built-in StingerKind raw value, or "" to play `stingerFile` instead.
    @Published var stingerKind: String { didSet { UserDefaults.standard.set(stingerKind, forKey: "stingerKind") } }
    @Published var rotateOn: Bool { didSet { UserDefaults.standard.set(rotateOn, forKey: "sceneRotateOn") } }
    @Published var rotateScenes: [String] { didSet { UserDefaults.standard.set(rotateScenes, forKey: "sceneRotateScenes") } }
    @Published var rotateSeconds: Int { didSet { UserDefaults.standard.set(rotateSeconds, forKey: "sceneRotateSeconds") } }

    private let dir = URL.applicationSupportDirectory.appending(path: "overlays")
    private var filesDir: URL { dir.appending(path: "files") }
    private var packURL: URL { dir.appending(path: "pack.json") }

    private init() {
        let d = UserDefaults.standard
        transition = d.string(forKey: "sceneTransition") ?? "fade"
        stingerFile = d.string(forKey: "stingerFile") ?? ""
        stingerCut = d.object(forKey: "stingerCut") as? Double ?? 0.5
        stingerKind = d.string(forKey: "stingerKind") ?? StingerKind.lens.rawValue
        rotateOn = d.bool(forKey: "sceneRotateOn")
        rotateScenes = d.stringArray(forKey: "sceneRotateScenes") ?? []
        rotateSeconds = d.object(forKey: "sceneRotateSeconds") as? Int ?? 60
        scene = UserDefaults.standard.string(forKey: "overlayScene") ?? ""
        if let data = try? Data(contentsOf: packURL) { pack = try? JSONDecoder().decode(OverlayPack.self, from: data) }
    }

    var activeScene: OverlayScene? { pack?.scenes.first { $0.name == scene } }
    var scenes: [OverlayScene] { pack?.scenes ?? [] }

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
        // Merge: scenes built in the app survive an import; same-named ones are replaced.
        let before = pack
        let names = Set(parsed.scenes.map(\.name))
        // ponytail: the pack keeps one OBS canvas size (the latest import's); older OBS scenes from a different canvas shift.
        var merged = parsed
        merged.scenes = (before?.scenes.filter { !names.contains($0.name) } ?? []) + parsed.scenes
        pack = merged
        guard persist() else {
            pack = before
            message = "Couldn't save the import"
            return
        }
        if !merged.scenes.contains(where: { $0.name == scene }) { select("") }
        revision += 1
        let layers = parsed.scenes.reduce(0) { $0 + $1.layers.count }
        applog("overlay", "imported \(parsed.scenes.count) scenes, \(layers) layers, \(parsed.skippedCount) skipped")
        message = (["Imported \(parsed.scenes.count) scenes, \(layers) layers.", parsed.skippedText, missingText()]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func missingText() -> String {
        let n = missing.count
        return n == 0 ? "" : "\(n) files not found: tap Locate files."
    }

    /// Writes the pack. The directory stays out of backups: the pack holds tokenised URLs.
    private func persist() -> Bool {
        guard let pack else { return false }
        do {
            try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
            var d = dir
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            try? d.setResourceValues(rv)
            try JSONEncoder().encode(pack).write(to: packURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            applog("overlay", "pack save failed", error: true)
            return false
        }
    }

    // MARK: scene editing

    /// `base`, then "base 2", "base 3"... (or "Scene 1", "Scene 2"... when `numbered`), whichever is free first.
    private func freeName(_ base: String, numbered: Bool) -> String {
        let taken = Set(scenes.map(\.name))
        if !numbered, !taken.contains(base) { return base }
        var n = numbered ? 1 : 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    func addScene() -> String {
        if pack == nil { pack = OverlayPack(canvasW: 1920, canvasH: 1080, scenes: [], skipped: [:]) }
        let name = freeName("Scene", numbered: true)
        pack?.scenes.append(OverlayScene(name: name, layers: []))
        _ = persist()
        return name
    }

    /// Adds the template's Starting / BRB / Ending scenes; each takes its role off whichever scene had it.
    func addTemplate(_ t: SceneTemplate, channel: String) {
        if pack == nil { pack = OverlayPack(canvasW: 1920, canvasH: 1080, scenes: [], skipped: [:]) }
        for var s in t.scenes(channel: channel) {
            s.name = freeName("\(t.rawValue) · \(s.name)", numbered: false)
            for i in scenes.indices where pack?.scenes[i].role == s.role { pack?.scenes[i].role = nil }
            pack?.scenes.append(s)
        }
        _ = persist()
    }

    func duplicateScene(_ name: String) -> String? {
        guard var copy = scenes.first(where: { $0.name == name }) else { return nil }
        copy.name = freeName("\(name) copy", numbered: false)
        pack?.scenes.append(copy)
        _ = persist()
        return copy.name
    }

    func renameScene(_ old: String, to new: String) -> Bool {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let i = scenes.firstIndex(where: { $0.name == old }) else { return false }
        if n == old { return true }
        guard !scenes.contains(where: { $0.name == n }) else { return false }
        pack?.scenes[i].name = n
        if scene == old { select(n) }
        rotateScenes = rotateScenes.map { $0 == old ? n : $0 }
        _ = persist()
        return true
    }

    func deleteScene(_ name: String) {
        pack?.scenes.removeAll { $0.name == name }
        if scene == name { select("") }
        rotateScenes.removeAll { $0 == name }
        _ = persist()
        revision += 1
    }

    func setLayers(_ layers: [OverlayLayer], in scene: String) {
        guard let i = scenes.firstIndex(where: { $0.name == scene }) else { return }
        pack?.scenes[i].layers = layers
        _ = persist()
        revision += 1
    }

    func setCamera(_ camera: String?, in scene: String) {
        guard let i = scenes.firstIndex(where: { $0.name == scene }) else { return }
        pack?.scenes[i].camera = camera
        _ = persist()
    }

    /// Giving a scene a role takes it off whichever scene had it (one scene per role); nil clears it.
    func setRole(_ role: String?, in scene: String) {
        guard scenes.contains(where: { $0.name == scene }) else { return }
        for i in scenes.indices {
            if pack?.scenes[i].name == scene { pack?.scenes[i].role = role }
            else if role != nil, pack?.scenes[i].role == role { pack?.scenes[i].role = nil }
        }
        _ = persist()
    }

    var stingerURL: URL? { stingerFile.isEmpty ? nil : local(stingerFile) }

    /// Copies a picked clip next to the imported media under a fresh name and makes it the stinger.
    func setStinger(from src: URL) {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        let name = "stinger-\(UUID().uuidString.prefix(8)).\(src.pathExtension)"
        do {
            try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: src, to: filesDir.appending(path: name))
            if let old = stingerURL { try? FileManager.default.removeItem(at: old) }
            stingerFile = name
        } catch {
            applog("overlay", "stinger copy failed: \(error.localizedDescription)", error: true)
        }
    }

    /// Stores picked image bytes untouched (a GIF must stay animated) and returns the name for `data["file"]`.
    func saveImage(_ data: Data) -> String? {
        let b = [UInt8](data.prefix(12))
        let ext: String
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { ext = "png" }
        else if b.starts(with: [0xFF, 0xD8, 0xFF]) { ext = "jpg" }
        else if b.starts(with: [0x47, 0x49, 0x46, 0x38]) { ext = "gif" }
        else if b.count >= 8, Array(b[4...7]) == [0x66, 0x74, 0x79, 0x70] { ext = "heic" }   // "ftyp"
        else { ext = "png" }   // unknown: UIImage sniffs the content anyway
        let name = "img-\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
            try data.write(to: filesDir.appending(path: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return name
        } catch {
            return nil
        }
    }

    // mediaSize is async now: the first ask returns nil, loads in the background and redraws observers when it lands.
    private var mediaSizes: [URL: CGSize] = [:]

    private func mediaSize(_ url: URL) -> CGSize? {
        if let s = mediaSizes[url] { return s }
        Task {
            guard mediaSizes[url] == nil, let s = await OverlayRaster.mediaSize(url) else { return }
            mediaSizes[url] = s
            objectWillChange.send()
        }
        return nil
    }

    /// The layer's own size before its transform/layout: what `widgetRect` scales. nil when its file isn't there yet.
    func naturalSize(_ l: OverlayLayer) -> CGSize? {
        func dim(_ k: String, _ d: Double) -> CGFloat { CGFloat(Double(l.data[k] ?? "") ?? d) }
        switch l.type {
        case .image:
            guard let url = local(l.data["file"] ?? ""), let img = OverlayRaster.load(url) else { return nil }
            return OverlayRaster.croppedSize(img, l.crop)
        case .text:
            let t = TextWidgetStyle(l.data)
            if l.layout != nil { return OverlayRaster.textNatural(t) }
            return OverlayRaster.textSize(t.text, OverlayRaster.textAttributes(face: t.face, bold: t.bold, px: t.size, argb: t.color))
        case .chat: return ChatWidgetStyle(l.data).natural
        case .events: return EventListStyle(l.data).natural
        case .alerts: return AlertWidgetStyle(l.data).natural
        case .qr: return QRWidgetStyle(l.data).natural
        case .goal: return GoalWidgetStyle(l.data).natural
        case .browser: return CGSize(width: dim("width", 800), height: dim("height", 600))
        case .color: return CGSize(width: dim("width", 1920), height: dim("height", 1080))
        case .media: return local(l.data["file"] ?? "").flatMap { mediaSize($0) }
        case .slideshow:
            guard let f = l.files.first, let url = local(f), let img = OverlayRaster.load(url) else { return nil }
            return img.size
        }
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
