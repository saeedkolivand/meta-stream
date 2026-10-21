import SwiftUI

/// One scene in the Scenes grid: a 16:9 thumbnail of where its widgets sit, the name, role and a one-line summary.
struct SceneCard: View {
    let scene: OverlayScene
    let onStream: Bool

    private var subtitle: String {
        let count = scene.layers.count
        let widgets = count == 1 ? "1 widget" : "\(count) widgets"
        guard let cam = sceneCameraTitle(scene.camera) else { return widgets }
        return "\(widgets) · \(cam)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SceneThumbnail(layers: scene.layers)
                .overlay(alignment: .topLeading) {
                    if onStream {
                        Text("ON STREAM").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.red, in: Capsule()).padding(6)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(onStream ? Color.red : Color.white.opacity(0.1), lineWidth: onStream ? 2 : 1))
            HStack(spacing: 6) {
                Text(scene.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 0)
                if let role = sceneRoleTitle(scene.role) {
                    Text(role).font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.top, -6)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(onStream ? "On stream" : "")
    }
}

/// ponytail: boxes at each visible layer's real position and size (tinted by kind, with the kind's icon), not the live
/// widget views: a grid of ten scenes would otherwise run ten chat/QR/goal renderers. Ceiling: no real widget look here.
struct SceneThumbnail: View {
    let layers: [OverlayLayer]
    private static let canvas = CGSize(width: 1920, height: 1080)

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / Self.canvas.width
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(white: 0.18), Color(white: 0.07)], startPoint: .top, endPoint: .bottom)
                ForEach(layers.indices, id: \.self) { idx in
                    if layers[idx].visible { box(layers[idx], scale: scale) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func box(_ layer: OverlayLayer, scale: CGFloat) -> some View {
        let rect = sceneLayerRect(layer, canvas: Self.canvas)
        let width = max(rect.width * scale, 4), height = max(rect.height * scale, 4)
        let icon = min(width, height) * 0.45
        return RoundedRectangle(cornerRadius: 3)
            .fill(layer.type.tint.opacity(0.55))
            .overlay {
                if min(width, height) > 14 {
                    Image(systemName: layer.type.icon).font(.system(size: icon)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: width, height: height)
            .offset(x: rect.minX * scale, y: rect.minY * scale)
    }
}
