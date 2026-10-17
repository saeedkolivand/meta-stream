import CoreImage
import Foundation
import HaishinKit

/// A video source's color treatment (CONTEXT.md "Look"). Stored per source as JSON under "look.<source>"
/// (glasses | back | front | external). Same rule as Privacy blur (adr/0001): a non-neutral look needs decoded
/// frames, so it forces a transcode for the glasses -- see StreamViewModel.codec.
struct Look: Codable, Equatable {
    var brightness = 0.0   // -0.5...0.5
    var contrast = 1.0     // 0.5...1.5
    var saturation = 1.0   // 0...2
    var warmth = 0.0       // -1 (cool) ... 1 (warm)
    var lut: String? = nil // file name in Documents/luts

    var isNeutral: Bool { brightness == 0 && contrast == 1 && saturation == 1 && warmth == 0 && lut == nil }

    static func load(_ key: String) -> Look {
        UserDefaults.standard.data(forKey: "look.\(key)").flatMap { try? JSONDecoder().decode(Look.self, from: $0) } ?? Look()
    }
    static func save(_ look: Look, _ key: String) {
        UserDefaults.standard.set(look.isNeutral ? nil : try? JSONEncoder().encode(look), forKey: "look.\(key)")
    }

    // MARK: LUT files

    static var folder: URL {
        let d = URL.documentsDirectory.appending(path: "luts")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.lowercased().hasSuffix(".cube") }.sorted()
    }

    /// Validates a picked .cube file, then copies it into Documents/luts. Returns the stored name or a user-facing error.
    static func importLUT(_ src: URL) -> Result<String, Error> {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        do {
            _ = try parseCube(String(contentsOf: src, encoding: .utf8))
            let name = src.lastPathComponent
            let dst = folder.appending(path: name)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: src, to: dst)
            return .success(name)
        } catch {
            applog("stream", "LUT import failed: \(error.localizedDescription)", error: true)
            return .failure(error)
        }
    }

    struct CubeError: LocalizedError { let errorDescription: String? }

    /// Adobe/Resolve .cube text -> (edge size, RGBA float32 data, red index fastest -- CIColorCube's order). 3D only.
    /// ponytail: DOMAIN_MIN/MAX are ignored (assumed 0...1), as is TITLE.
    static func parseCube(_ text: String) throws -> (size: Int, data: Data) {
        var size = 0
        var rgba: [Float] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: \.isWhitespace)
            switch parts[0] {
            case "LUT_1D_SIZE": throw CubeError(errorDescription: "1D LUTs aren't supported, use a 3D .cube file")
            case "LUT_3D_SIZE":
                guard parts.count > 1, let n = Int(parts[1]), n >= 2 else { throw CubeError(errorDescription: "Bad LUT_3D_SIZE") }
                guard n <= 64 else { throw CubeError(errorDescription: "LUT size \(n) is too big (64 at most)") }
                size = n; rgba.reserveCapacity(n * n * n * 4)
            case "TITLE", "DOMAIN_MIN", "DOMAIN_MAX": continue
            default:
                guard parts.count == 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) else { throw CubeError(errorDescription: "Unreadable line: \(line.prefix(40))") }
                rgba += [r, g, b, 1]
            }
        }
        guard size > 0 else { throw CubeError(errorDescription: "No LUT_3D_SIZE found") }
        guard rgba.count == size * size * size * 4 else { throw CubeError(errorDescription: "Expected \(size * size * size) entries, found \(rgba.count / 4)") }
        return (size, rgba.withUnsafeBufferPointer { Data(buffer: $0) })
    }
}

/// Applies a Look to every frame the mixer renders. Registered on `mixer.screen` next to the privacy blur --
/// same VideoEffect hook, same offscreen-mode requirement (see Streamer.syncBlurEffect). Threading as Privacy:
/// `execute` is nonisolated and runs on HaishinKit's rendering context; `look` is written by the 1 s tick.
@MainActor final class LookEffect: VideoEffect {
    nonisolated(unsafe) var look = Look()
    nonisolated(unsafe) private var built: Look?
    nonisolated(unsafe) private var cube: (size: Int, data: Data)?
    nonisolated private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    nonisolated func execute(_ image: CIImage) -> CIImage {
        let l = look
        if l != built {   // reparse the LUT only when the look actually changed
            built = l
            cube = l.lut.flatMap { name in
                do { return try Look.parseCube(String(contentsOf: Look.folder.appending(path: name), encoding: .utf8)) } catch {
                    applog("stream", "LUT \(name) unusable: \(error.localizedDescription)", error: true); return nil
                }
            }
        }
        var out = image
        if l.brightness != 0 || l.contrast != 1 || l.saturation != 1 {
            out = out.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: l.brightness, kCIInputContrastKey: l.contrast, kCIInputSaturationKey: l.saturation])
        }
        if l.warmth != 0 {
            // Neutral 6500 K; warmth +1 retargets to 4500 K (orange cast), -1 to 8500 K (blue cast).
            out = out.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 - l.warmth * 2000, y: 0)])
        }
        if let cube {
            out = out.applyingFilter("CIColorCubeWithColorSpace", parameters: ["inputCubeDimension": cube.size, "inputCubeData": cube.data, "inputColorSpace": Self.space])
        }
        return out
    }
}

extension Streamer {
    /// Which source's look is live: glasses, or the phone camera position / external camera.
    var lookKey: String {
        if source == "glasses" { return "glasses" }
        if manualSource == "external" { return "external" }
        return manualSource == "front" || (manualSource == "auto" && fallbackPosition == .front) ? "front" : "back"
    }

    /// A non-neutral look on a source whose frames reach the mixer (glasses HEVC passthrough can't be graded).
    var lookWanted: Bool { overlaysUsable && !Look.load(lookKey).isNeutral }

    /// Registers/unregisters the look; while on, also pushes the current look. Idempotent on lookEffectActive.
    func setLookEffect(_ on: Bool) async {
        if on { lookEffect.look = Look.load(lookKey) }
        guard lookEffectActive != on else { return }
        lookEffectActive = on
        await Self.registerLook(mixer, lookEffect, on: on)
        applog("stream", "look effect \(on ? "registered" : "unregistered")")
    }

    @ScreenActor static func registerLook(_ mixer: MediaMixer, _ effect: LookEffect, on: Bool) {
        if on { _ = mixer.screen.registerVideoEffect(effect) } else { _ = mixer.screen.unregisterVideoEffect(effect) }
    }
}

#if DEBUG
extension Look {
    static func demo() {
        assert(Look().isNeutral, "default look is neutral")
        assert(!Look(warmth: 0.1).isNeutral && !Look(lut: "a.cube").isNeutral, "any change is not neutral")
        let cube = "# c\nTITLE \"t\"\nDOMAIN_MIN 0 0 0\nLUT_3D_SIZE 2\n\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n"
        let p = try? parseCube(cube)
        assert(p?.size == 2 && p?.data.count == 8 * 4 * 4, "2x2x2 cube -> 8 RGBA float entries")
        assert((try? parseCube("LUT_1D_SIZE 4\n0 0 0")) == nil, "1D rejected")
        assert((try? parseCube("LUT_3D_SIZE 65")) == nil, "oversize rejected")
        assert((try? parseCube("LUT_3D_SIZE 2\n0 0 0")) == nil, "short cube rejected")
        applog("stream", "Look.demo() passed")
    }
}
#endif
