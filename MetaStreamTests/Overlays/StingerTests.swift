import CoreImage
import XCTest
@testable import MetaStream

final class StingerTests: XCTestCase {
    func testCurveAndTrack() {
        XCTAssertEqual(Curve.linear(0.3), 0.3, accuracy: 1e-6)
        XCTAssertEqual(Curve.easeInOut(0.5), 0.5, accuracy: 0.01)
        XCTAssertEqual(Curve.linear.track(0.1, [(0.25, 0), (0.5, 1)]), 0)
        XCTAssertEqual(Curve.linear.track(0.375, [(0.25, 0), (0.5, 1)]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Curve.linear.track(0.9, [(0.25, 0), (0.5, 1), (0.6, 1)]), 1)
        XCTAssertEqual(StingerArt.mixWhite(0xFF00_0000, 0.5), 0xFF80_8080)
        XCTAssertEqual(StingerArt.fg(on: 0xFFF2_F1EC), 0xFF0B_0B0C)
    }

    /// The scene switches at the cut, so every stinger must hide the whole frame there, on landscape and portrait
    /// canvases, and leave nothing behind on its last frame.
    func testCoversAtCutAndClearsAtEnd() {
        let style = StingerStyle()
        for kind in StingerKind.allCases {
            XCTAssertLessThan(kind.span.start, kind.span.cut)
            XCTAssertLessThan(kind.span.cut, kind.span.end)
            for size in [CGSize(width: 480, height: 270), CGSize(width: 270, height: 480)] {
                let cut = alphas(kind, size, kind.cutSeconds(style), style)
                XCTAssertTrue(cut.allSatisfy { $0 > 250 }, "\(kind) \(size) not covered at the cut: \(cut)")
                let end = alphas(kind, size, kind.seconds(style), style)
                XCTAssertTrue(end.allSatisfy { $0 < 5 }, "\(kind) \(size) leaves pixels at the end: \(end)")
            }
        }
    }

    /// Alpha at the corners, edge midpoints and centre of one frame.
    private let context = CIContext()

    private func alphas(_ kind: StingerKind, _ size: CGSize, _ t: Double, _ style: StingerStyle) -> [UInt8] {
        guard let image = kind.frame(StingerCanvas(size: size), t: t, style: style, context: context),
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        let w = image.width, h = image.height, row = image.bytesPerRow
        var out: [UInt8] = []
        for y in [1, h / 2, h - 2] {
            for x in [1, w / 2, w - 2] { out.append(bytes[y * row + x * 4 + 3]) }   // BGRA: alpha last
        }
        return out
    }
}
