// OBS scene import model: value types only, so a parsed pack crosses actors freely and persists as plain JSON.
import CoreGraphics
import Foundation

enum OverlayLayerType: String, Codable, Sendable { case browser, image, media, text, color, slideshow }

/// One OBS scene item, flattened (group transforms already applied). Position/scale/bounds are OBS canvas px.
/// `data` holds the type's payload as strings: browser url/width/height/css, image/media file (+loop), text/face/size/
/// bold/color, color/width/height, slideshow time. `files` is the slideshow list.
struct OverlayLayer: Codable, Sendable, Equatable {
    var type: OverlayLayerType
    var name: String
    var visible: Bool
    var x: CGFloat
    var y: CGFloat
    var sx: CGFloat
    var sy: CGFloat
    var align: Int
    var boundsType: Int
    var bw: CGFloat
    var bh: CGFloat
    var boundsAlign: Int
    var rotation: CGFloat
    var crop: [Int]          // left, top, right, bottom in source px
    var data: [String: String]
    var files: [String] = []
}

struct OverlayScene: Codable, Sendable, Equatable {
    var name: String
    var layers: [OverlayLayer]
}

/// `skipped` maps a PC-only category ("cameras", "game/window/monitor capture"...) to how many sources were left out.
struct OverlayPack: Codable, Sendable, Equatable {
    var canvasW: Int
    var canvasH: Int
    var scenes: [OverlayScene]
    var skipped: [String: Int]

    var skippedCount: Int { skipped.values.reduce(0, +) }

    var skippedText: String {
        skippedCount == 0 ? "" : "Skipped \(skippedCount) PC-only sources: " + skipped.keys.sorted().joined(separator: ", ")
    }

    /// Every local file the scenes reference (images, media, slideshow frames), as OBS wrote the path.
    var files: Set<String> {
        var out = Set<String>()
        for l in scenes.flatMap(\.layers) {
            if l.type == .image || l.type == .media, let f = l.data["file"] { out.insert(f) }
            out.formUnion(l.files)
        }
        return out
    }
}

/// Last path component of a Windows or POSIX path: OBS files are named as on the streamer's PC (`E:\a\b.png`).
func overlayBaseName(_ path: String) -> String {
    String(path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last ?? "")
}
