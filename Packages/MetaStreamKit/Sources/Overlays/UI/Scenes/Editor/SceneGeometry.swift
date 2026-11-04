import SwiftUI

/// Where a layer sits on a canvas of `canvas` output px, as the compositor places it (no {token} resolving, so a
/// text widget uses its raw text size). Used by the scene cards; the editor canvas has its own copy that resolves tokens.
@MainActor func sceneLayerRect(_ layer: OverlayLayer, canvas: CGSize) -> CGRect {
    let store = OverlayStore.shared
    let natural = store.naturalSize(layer) ?? CGSize(width: 400, height: 200)
    if let layout = layer.layout { return widgetRect(layout, natural: natural, canvas: canvas) }
    guard let pack = store.pack else { return .zero }
    let fit = overlayFit(canvasW: pack.canvasW, canvasH: pack.canvasH, outW: canvas.width, outH: canvas.height)
    return fit.apply(overlayPlace(layer, natural.width, natural.height))
}

extension OverlayLayerType {
    /// Colour that tells widget kinds apart in the scene card thumbnails.
    var tint: Color {
        switch self {
        case .chat: .blue
        case .alerts: .pink
        case .events: .purple
        case .goal: .orange
        case .nowplaying: .green
        case .text: .teal
        case .qr: .indigo
        case .image, .slideshow, .media: .yellow
        case .browser, .color: .gray
        }
    }
}

/// Plain-words name of a scene's camera, for subtitles.
func sceneCameraTitle(_ camera: String?) -> String? {
    switch camera {
    case "back": "Back camera"
    case "front": "Front camera"
    case "external": "External camera"
    case "glasses": "Glasses"
    case "auto": "Auto camera"
    default: nil
    }
}

func sceneRoleTitle(_ role: String?) -> String? {
    switch role {
    case "starting": "Starting"
    case "brb": "BRB"
    case "ending": "Ending"
    default: nil
    }
}

func sceneCameraIcon(_ camera: String?) -> String {
    switch camera {
    case "front": "person.crop.circle"
    case "external": "video.fill"
    case "glasses": "eyeglasses"
    default: "camera.fill"
    }
}
