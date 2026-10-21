// Shared by the GPU chat and event-list widgets. Each row (a message card, an event pill) is rasterised ONCE on the CPU
// with its SwiftUI view (emote images, badges, name colours and bidi text come out exactly as in the editor) and cached by
// a key; stacking the rows, the entry slide, the fade-out, the top dissolve and the clipping are Core Image recipes the GPU
// evaluates each composited frame, as functions of time. So a new message costs one row raster, never a whole-box re-render.
import CoreImage
import QuartzCore
import SwiftUI
import UIKit

/// A row's picture inside a Sendable scene. A CGImage is immutable once made, so sharing it across threads is safe; the box
/// only tells the compiler so.
struct ChatRowBox: @unchecked Sendable { let image: CGImage }

/// One rasterised row: its picture (with `pad` points of room around it for shadows), the content height in widget
/// points (without the padding) and when it was born (drives the entry slide and the fade-out).
struct ChatRowItem: Sendable {
    let picture: ChatRowBox
    let height: CGFloat
    let born: Date
}

/// How a stack of rows sits in the widget. Points are the widget's natural ones; `scale` turns them into canvas px.
struct ChatStackSpec: Sendable {
    var scale: CGFloat
    /// The widget box's top-left inside the GPU object (px): the object covers only the visible part of the box.
    var origin: CGPoint
    var size: CGSize
    var gap: CGFloat
    var pad: CGFloat = 8
    /// true: newest row at the bottom, older ones pushed up (chat). false: the first row on top, the rest below (events).
    var upward = true
    /// Entry slide distance in points (0 = rows just appear).
    var enters: CGFloat = 0
    /// Seconds a row lives before it is gone (0 = never); it dissolves over the last two.
    var fadeSeconds: Double = 0
    /// Older rows dissolve into the video at the top instead of ending on a hard edge.
    var topFade = false
}

/// Time functions of a row's life, shared by the draw and by the loop that decides whether the scene must keep moving.
enum ChatMotion {
    static let entry = 0.32
    static let ramp = 2.0

    /// 0 -> 1 over a row's first 0.32 s (ease-out), as the SwiftUI chat did.
    static func appear(_ born: Date, _ now: Date, enabled: Bool) -> Double {
        guard enabled else { return 1 }
        let step = min(1, max(0, now.timeIntervalSince(born) / entry))
        return 1 - pow(1 - step, 3)
    }

    /// 1 until the last 2 s before the fade deadline, then ramps to 0.
    static func opacity(_ born: Date, fade: Double, _ now: Date) -> Double {
        guard fade > 0 else { return 1 }
        return max(0, min(1, (fade - now.timeIntervalSince(born)) / ramp))
    }

    /// Is any row sliding in or fading out at `now`? Only then does the scene need to redraw every frame.
    static func moving(_ born: [Date], _ spec: ChatStackSpec, now: Date) -> Bool {
        born.contains { date in
            let age = now.timeIntervalSince(date)
            return (spec.enters > 0 && age < entry) || (spec.fadeSeconds > 0 && age > spec.fadeSeconds - ramp)
        }
    }
}

/// The scene of a stack: still while nothing animates, moving (time advances on the GPU) while a row enters or fades.
enum ChatScene {
    static func make(_ rows: [ChatRowItem], _ spec: ChatStackSpec, moving: Bool) -> GPUScene {
        let began = Date()
        return GPUScene(draw: { pen, time in
            pen.chStack(rows, spec, now: moving ? began.addingTimeInterval(time) : began)
        }, moving: moving, epoch: CACurrentMediaTime())
    }
}

extension StingerCanvas {
    /// The rows laid out, faded and clipped to the widget box. `rows` run oldest first for an upward stack, top first otherwise.
    func chStack(_ rows: [ChatRowItem], _ spec: ChatStackSpec, now: Date) -> CIImage {
        var layers: [CIImage] = []
        var cursor = spec.upward ? spec.size.height - spec.pad : spec.pad
        for row in spec.upward ? Array(rows.reversed()) : rows {
            let ease = CGFloat(ChatMotion.appear(row.born, now, enabled: spec.enters > 0))
            let alpha = Double(ease) * ChatMotion.opacity(row.born, fade: spec.fadeSeconds, now)
            let top = spec.upward ? cursor - row.height : cursor
            // Older rows rise as the newest one eases in: the cursor only advances by the share that has appeared.
            cursor += (row.height + spec.gap) * (spec.upward ? -ease : 1)
            layers.append(opacity(chPlace(row, y: top - spec.pad + (1 - ease) * spec.enters, spec), alpha))
        }
        let stacked = stack(spec.upward ? Array(layers.reversed()) : layers)
        let wide = spec.size.width * spec.scale, high = spec.size.height * spec.scale
        let box = CGRect(x: spec.origin.x, y: spec.origin.y, width: wide, height: high)
        return (spec.topFade ? clip(stacked, to: chTopMask(box)) : stacked).cropped(to: box)
    }

    /// The row's raster with its top-left corner `y` points below the box top.
    func chPlace(_ row: ChatRowItem, y: CGFloat, _ spec: ChatStackSpec) -> CIImage {
        let image = row.picture.image
        let high = CGFloat(image.height)
        return CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: high))   // into top-left space
            .transformed(by: CGAffineTransform(translationX: spec.origin.x, y: spec.origin.y + y * spec.scale))
    }

    /// Transparent at the box top, opaque from 18% down (the SwiftUI mask's gradient).
    func chTopMask(_ box: CGRect) -> CIImage {
        linear(CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.minX, y: box.minY + box.height * 0.18), 0x0000_0000, 0xFF00_0000)
    }
}

/// Row rasters by key. The widget keeps only the keys it still shows (`keep`), so the cache never outgrows the screen.
@MainActor
final class ChatRowCache {
    private var items: [String: ChatRowItem] = [:]
    /// Rasters made so far: the widgets log how many a pass added.
    private(set) var made = 0

    /// A stable id for one event: the platform's message id when there is one, else what identifies it by content.
    static func key(_ e: ChatEvent) -> String {
        let base = e.id.isEmpty ? "\(e.kind)|\(e.user)|\(e.text.count)|\(e.amountCents)|\(e.count)" : e.id
        return "\(e.origin)|\(base)|\(e.at.timeIntervalSince1970)"
    }

    /// The cached row, or `view` rasterised at `scale` px per point inside `pad` points of room. nil if SwiftUI made no image.
    func item<V: View>(_ key: String, born: Date, scale: CGFloat, pad: CGFloat, view: () -> V) -> ChatRowItem? {
        if let hit = items[key] { return hit }
        let renderer = ImageRenderer(content: view().padding(pad))
        renderer.scale = scale
        renderer.isOpaque = false
        guard let image = renderer.cgImage, image.height > 0 else { return nil }
        let row = ChatRowItem(picture: ChatRowBox(image: image), height: CGFloat(image.height) / scale - 2 * pad, born: born)
        items[key] = row
        made += 1
        return row
    }

    func keep(_ keys: Set<String>) {
        guard items.count > keys.count else { return }
        items = items.filter { keys.contains($0.key) }
    }
}
