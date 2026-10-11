import XCTest
@testable import MetaStream

final class PlacementTests: XCTestCase {
    private func layer(x: CGFloat = 0, y: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1, align: Int = 5,
                       boundsType: Int = 0, bw: CGFloat = 0, bh: CGFloat = 0, boundsAlign: Int = 0) -> OverlayLayer {
        OverlayLayer(type: .image, name: "n", visible: true, x: x, y: y, sx: sx, sy: sy, align: align, boundsType: boundsType,
                     bw: bw, bh: bh, boundsAlign: boundsAlign, rotation: 0, crop: [0, 0, 0, 0], data: [:])
    }

    func testTopLeftScaled() {
        XCTAssertEqual(overlayPlace(layer(x: 10, y: 20, sx: 2, sy: 2), 100, 50), CGRect(x: 10, y: 20, width: 200, height: 100))
    }

    func testCenterAligned() {
        XCTAssertEqual(overlayPlace(layer(x: 960, y: 540, align: 0), 200, 100), CGRect(x: 860, y: 490, width: 200, height: 100))
    }

    func testBoundsScaleInnerCentersInBox() {
        XCTAssertEqual(overlayPlace(layer(boundsType: 2, bw: 400, bh: 400), 200, 100), CGRect(x: 0, y: 100, width: 400, height: 200))
    }

    func testBoundsStretchFillsBox() {
        XCTAssertEqual(overlayPlace(layer(boundsType: 1, bw: 400, bh: 300), 200, 100), CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    func testLandscapeCanvasIsCenteredInPortraitOutput() {
        let f = overlayFit(canvasW: 1920, canvasH: 1080, outW: 720, outH: 1280)
        XCTAssertEqual(f.scale, 0.375, accuracy: 0.0001)
        XCTAssertEqual(f.offX, 0, accuracy: 0.001)
        XCTAssertEqual(f.offY, (1280 - 405) / 2, accuracy: 0.01)
        XCTAssertEqual(f.apply(CGRect(x: 0, y: 0, width: 1920, height: 1080)).width, 720, accuracy: 0.01)
    }
}
