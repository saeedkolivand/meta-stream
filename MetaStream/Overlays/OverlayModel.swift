// OBS scene import model: value types only, so a parsed pack crosses actors freely and persists as plain JSON.
import CoreGraphics
import Foundation

enum OverlayLayerType: String, Codable, Sendable { case browser, image, media, text, color, slideshow, chat, alerts, events, qr, goal }

/// Frame-relative placement for in-app widgets, so one layout works in portrait, landscape and any resolution.
/// anchor: 0..8 row-major (0 TL, 1 TC, 2 TR, 3 ML, 4 C, 5 MR, 6 BL, 7 BC, 8 BR).
/// dx/dy: offset of the widget from its anchored position, as a fraction of canvas width/height (+ = right/down).
/// scale: multiplier on the widget's natural size, where natural px are defined for a 1080 px short side.
struct WidgetLayout: Codable, Sendable, Equatable {
    var anchor: Int = 6
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var scale: CGFloat = 1

    /// Anchored with the standard safe inset: 2.5% of width / 4% of height, pointing inward (0 on a centre axis).
    static func inset(_ anchor: Int, scale: CGFloat = 1) -> WidgetLayout {
        let col = anchor % 3, row = anchor / 3
        return WidgetLayout(anchor: anchor, dx: col == 0 ? 0.025 : col == 2 ? -0.025 : 0,
                            dy: row == 0 ? 0.04 : row == 2 ? -0.04 : 0, scale: scale)
    }
}

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
    /// In-app widget placement; nil keeps the OBS transform above (imports).
    var layout: WidgetLayout? = nil
}

extension OverlayLayer {
    /// In-app widget: uses `layout`, OBS fields neutral (align 5, scale 1, no bounds, no crop), visible.
    static func widget(_ type: OverlayLayerType, name: String, layout: WidgetLayout, data: [String: String]) -> OverlayLayer {
        OverlayLayer(type: type, name: name, visible: true, x: 0, y: 0, sx: 1, sy: 1, align: 5, boundsType: 0, bw: 0, bh: 0,
                     boundsAlign: 0, rotation: 0, crop: [0, 0, 0, 0], data: data, files: [], layout: layout)
    }
}

struct OverlayScene: Codable, Sendable, Equatable {
    var name: String
    var layers: [OverlayLayer]
    /// "back" | "front" | "external" | "glasses" | "auto"; nil leaves the camera alone when the scene is selected.
    var camera: String? = nil
    /// "starting" | "brb" | "ending": a job the app switches to this scene for on its own; nil = none. One scene per role.
    var role: String? = nil
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

#if DEBUG
enum OverlayChecks {
    static func demo() {
        for canvas in [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920)] {
            for a in 0...8 {
                let l = WidgetLayout.inset(a, scale: 1.5)
                let r = widgetRect(l, natural: CGSize(width: 300, height: 100), canvas: canvas)
                let back = widgetLayout(for: r, natural: CGSize(width: 300, height: 100), canvas: canvas, scale: 1.5)
                assert(back.anchor == a && abs(back.dx - l.dx) < 1e-6 && abs(back.dy - l.dy) < 1e-6, "widget layout round trip")
            }
        }
        let old = #"{"name":"S","layers":[{"type":"color","name":"c","visible":true,"x":0,"y":0,"sx":1,"sy":1,"align":5,"boundsType":0,"bw":0,"bh":0,"boundsAlign":0,"rotation":0,"crop":[0,0,0,0],"data":{},"files":[]}]}"#
        let scene = try? JSONDecoder().decode(OverlayScene.self, from: Data(old.utf8))
        assert(scene?.camera == nil && scene?.role == nil && scene?.layers.first?.layout == nil, "old scene JSON decodes")
        let layer = OverlayLayer.widget(.chat, name: "Chat", layout: .inset(6), data: ChatWidgetStyle().data)
        assert((try? JSONDecoder().decode(OverlayLayer.self, from: JSONEncoder().encode(layer))) == layer, "layer round trip")
        assert(ChatWidgetStyle(ChatWidgetStyle().data) == ChatWidgetStyle() && ChatWidgetStyle([:]) == ChatWidgetStyle())
        assert(AlertWidgetStyle(AlertWidgetStyle().data) == AlertWidgetStyle() && AlertWidgetStyle([:]) == AlertWidgetStyle())
        assert(EventListStyle(EventListStyle().data) == EventListStyle() && EventListStyle([:]) == EventListStyle())
        assert(GoalWidgetStyle(GoalWidgetStyle().data) == GoalWidgetStyle() && GoalWidgetStyle([:]) == GoalWidgetStyle())
        assert(GoalWidgetStyle(["design": "road"]).design == "road" && GoalWidgetStyle(GoalWidgetStyle(["design": "liquid"]).data).design == "liquid")
        assert(QRWidgetStyle(QRWidgetStyle().data) == QRWidgetStyle() && QRWidgetStyle([:]) == QRWidgetStyle())
        assert(TextWidgetStyle(TextWidgetStyle().data) == TextWidgetStyle() && TextWidgetStyle([:]) == TextWidgetStyle())
        applog("overlay", "OverlayChecks.demo() passed")
    }
}
#endif
