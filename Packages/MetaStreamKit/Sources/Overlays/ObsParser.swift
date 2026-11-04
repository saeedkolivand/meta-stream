// OBS scene-collection JSON -> OverlayPack. Pure and Sendable; never logs or keeps the source text
// (the file carries account tokens inside browser-source URLs).
import CoreGraphics
import Foundation

// ponytail: OBS doesn't store the canvas size in the scene collection (it lives in the profile), so assume 1920x1080.
// Upgrade path: a canvas size field in the import UI.
let obsCanvasW = 1920
let obsCanvasH = 1080

private let maxDepth = 8
private typealias JSON = [String: Any]

private let cameras: Set<String> = ["dshow_input", "v4l2_input", "av_capture_input", "av_capture_input_v2", "decklink-input"]
private let captures: Set<String> = ["game_capture", "window_capture", "monitor_capture", "display_capture", "xshm_input", "screen_capture"]

private func category(_ id: String) -> String {
    if id == "browser_source" { return "non-web browser pages" }
    if cameras.contains(id) { return "cameras" }
    if captures.contains(id) { return "game/window/monitor capture" }
    if ["wasapi", "pulse", "coreaudio", "alsa"].contains(where: { id.hasPrefix($0) }) { return "audio" }
    return "other (\(id))"
}

private extension Dictionary where Key == String, Value == Any {
    func int(_ k: String, _ d: Int) -> Int { (self[k] as? NSNumber)?.intValue ?? d }
    func flt(_ k: String, _ d: CGFloat) -> CGFloat { (self[k] as? NSNumber).map { CGFloat($0.doubleValue) } ?? d }
    func bool(_ k: String, _ d: Bool) -> Bool { (self[k] as? NSNumber)?.boolValue ?? d }
    func str(_ k: String) -> String { self[k] as? String ?? "" }
    func obj(_ k: String) -> JSON? { self[k] as? JSON }
    func list(_ k: String) -> [JSON] { (self[k] as? [Any])?.compactMap { $0 as? JSON } ?? [] }
    func xy(_ k: String, _ d: CGFloat) -> (CGFloat, CGFloat) { obj(k).map { ($0.flt("x", d), $0.flt("y", d)) } ?? (d, d) }
    /// OBS colors are unsigned 32-bit numbers that JSON may hand back as a larger signed or a double.
    func color(_ k: String, _ d: UInt32) -> UInt32 { (self[k] as? NSNumber).map { UInt32(truncatingIfNeeded: $0.int64Value) } ?? d }
}

/// OBS colors are 0xAABBGGRR; the screen wants ARGB. A zero alpha means "unset" in OBS text sources, so it becomes opaque.
func obsColor(_ v: UInt32) -> UInt32 {
    let alpha = (v >> 24) & 255
    let a: UInt32 = alpha == 0 ? 255 : alpha
    let r: UInt32 = v & 255
    let g: UInt32 = (v >> 8) & 255
    let b: UInt32 = (v >> 16) & 255
    return (a << 24) | (r << 16) | (g << 8) | b
}

enum ObsParseError: Error { case notObject }

/// Parser state: the source lookups plus the layers and skipped tally of the scene being walked.
private struct Ctx {
    var byUuid: [String: JSON]
    var byName: [String: JSON]
    var skipped: [String: Set<String>] = [:]
    var layers: [OverlayLayer] = []
}

/// Where a nested item sits: origin + scale of its parent group, and whether every ancestor is visible.
private struct Xf {
    var ox: CGFloat, oy: CGFloat, sx: CGFloat, sy: CGFloat
    var visible: Bool
}

/// Throws on text that isn't a JSON object; a valid object without sources yields zero scenes.
func parseObs(_ json: String) throws -> OverlayPack {
    guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? JSON else { throw ObsParseError.notObject }
    let sources = root.list("sources")
    var ctx = Ctx(byUuid: [:], byName: [:])
    for s in sources {
        if s["uuid"] is String { ctx.byUuid[s.str("uuid")] = s }
        ctx.byName[s.str("name")] = s
    }
    var scenes: [OverlayScene] = []
    for sc in sources where sc.str("id") == "scene" {
        ctx.layers = []
        walk(&ctx, (sc.obj("settings") ?? [:]).list("items"), Xf(ox: 0, oy: 0, sx: 1, sy: 1, visible: true), 0)
        scenes.append(OverlayScene(name: sc.str("name"), layers: ctx.layers))
    }
    return OverlayPack(canvasW: obsCanvasW, canvasH: obsCanvasH, scenes: scenes, skipped: ctx.skipped.mapValues(\.count))
}

private func walk(_ ctx: inout Ctx, _ items: [JSON], _ xf: Xf, _ depth: Int) {
    for item in items {
        guard let src = ctx.byUuid[item.str("source_uuid")] ?? ctx.byName[item.str("name")] else { continue }
        let (px, py) = item.xy("pos", 0)
        let (isx, isy) = item.xy("scale", 1)
        let visible = xf.visible && item.bool("visible", true)
        let id = src.str("id")
        let world = Xf(ox: xf.ox + xf.sx * px, oy: xf.oy + xf.sy * py, sx: xf.sx * isx, sy: xf.sy * isy, visible: visible)
        if id == "group" || id == "scene" {
            // ponytail: group rotation, crop and alignment are ignored; children keep their own transforms scaled by the group's.
            if depth < maxDepth { walk(&ctx, (src.obj("settings") ?? [:]).list("items"), world, depth + 1) }
            continue
        }
        if let layer = makeLayer(src, item, world, xf) {
            ctx.layers.append(layer)
        } else {
            ctx.skipped[category(id), default: []].insert(src.str("name"))
        }
    }
}

private func makeLayer(_ src: JSON, _ item: JSON, _ w: Xf, _ parent: Xf) -> OverlayLayer? {
    guard let (type, data, files) = payload(src.str("id"), src.obj("settings") ?? [:]) else { return nil }
    let (bx, by) = item.xy("bounds", 0)
    return OverlayLayer(
        type: type, name: src.str("name"), visible: w.visible,
        x: w.ox, y: w.oy, sx: w.sx, sy: w.sy,
        align: item.int("align", 5), boundsType: item.int("bounds_type", 0),
        bw: bx * parent.sx, bh: by * parent.sy, boundsAlign: item.int("bounds_align", 0),
        rotation: item.flt("rot", 0),
        crop: ["crop_left", "crop_top", "crop_right", "crop_bottom"].map { item.int($0, 0) },
        data: data, files: files)
}

private func payload(_ id: String, _ s: JSON) -> (OverlayLayerType, [String: String], [String])? {
    switch id {
    case "browser_source":
        let url = s.str("url")
        // Only http(s) pages can load: local-file pages and anything else would need file access, which stays off.
        guard !s.bool("is_local_file", false), url.hasPrefix("http://") || url.hasPrefix("https://") else { return nil }
        return (.browser, ["url": url, "width": String(s.int("width", 800)), "height": String(s.int("height", 600)), "css": s.str("css")], [])
    case "image_source":
        let f = s.str("file")
        return f.isEmpty ? nil : (.image, ["file": f], [])
    case "ffmpeg_source":
        let f = s.str("local_file")
        guard s.bool("is_local_file", true), !f.isEmpty else { return nil }
        // ponytail: media audio is muted on the stream (the mixer takes the mic only). Upgrade path: AudioMixer track for the clip.
        return (.media, ["file": f, "loop": String(s.bool("looping", false))], [])
    case "text_gdiplus", "text_gdiplus_v2", "text_gdiplus_v3", "text_ft2_source", "text_ft2_source_v2":
        let font = s.obj("font") ?? [:]
        let color = s["color"] != nil ? s.color("color", 0xFFFF_FFFF) : s.color("color1", 0xFFFF_FFFF)
        return (.text, [
            "text": s.str("text"), "face": font.str("face"), "size": String(font.int("size", 36)),
            "bold": String(font.int("flags", 0) & 1 != 0), "color": String(obsColor(color)),
        ], [])
    case "color_source", "color_source_v2", "color_source_v3":
        return (.color, ["color": String(obsColor(s.color("color", 0xFFFF_FFFF))), "width": String(s.int("width", 1920)), "height": String(s.int("height", 1080))], [])
    case "slideshow":
        let files = s.list("files").map { $0.str("value") }.filter { !$0.isEmpty }
        return files.isEmpty ? nil : (.slideshow, ["time": String(s.int("slide_time", 8000))], files)
    default:
        return nil
    }
}
