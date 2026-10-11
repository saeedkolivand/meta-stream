import XCTest
@testable import MetaStream

final class ObsParserTests: XCTestCase {
    // Synthetic collection with fake URLs: a scene with a browser source, a group holding an image and text, and PC-only sources.
    private let json = #"""
    {"sources":[
     {"id":"browser_source","name":"alerts","uuid":"u1","settings":{"url":"https://example.invalid/alerts","width":1920,"height":1080,"css":"body{color:red}"}},
     {"id":"browser_source","name":"local","uuid":"u2","settings":{"url":"file:///c:/x.html","is_local_file":true}},
     {"id":"image_source","name":"frame","uuid":"u3","settings":{"file":"E:/fake/Frames/frame.png"}},
     {"id":"text_gdiplus","name":"title","uuid":"u4","settings":{"text":"Hello","font":{"face":"Arial","size":48,"flags":1},"color":4278190335}},
     {"id":"dshow_input","name":"cam","uuid":"u5","settings":{}},
     {"id":"game_capture","name":"game","uuid":"u6","settings":{}},
     {"id":"wasapi_input_capture","name":"mic","uuid":"u7","settings":{}},
     {"id":"ffmpeg_source","name":"clip","uuid":"u8","settings":{"local_file":"E:/fake/clip.mp4","looping":true}},
     {"id":"group","name":"grp","uuid":"g1","settings":{"items":[
        {"name":"frame","source_uuid":"u3","pos":{"x":10,"y":20},"scale":{"x":2,"y":2},"visible":true},
        {"name":"title","source_uuid":"u4","pos":{"x":0,"y":0},"visible":false}]}},
     {"id":"scene","name":"Live","uuid":"s1","settings":{"items":[
        {"name":"cam","source_uuid":"u5"},
        {"name":"alerts","source_uuid":"u1","pos":{"x":0,"y":0},"bounds_type":2,"bounds":{"x":960,"y":540},"bounds_align":0},
        {"name":"grp","source_uuid":"g1","pos":{"x":100,"y":100},"scale":{"x":0.5,"y":0.5}},
        {"name":"clip","source_uuid":"u8","visible":true},
        {"name":"local","source_uuid":"u2"}]}},
     {"id":"scene","name":"BRB","uuid":"s2","settings":{"items":[{"name":"mic","source_uuid":"u7"}]}}
    ]}
    """#

    private func parsed() throws -> OverlayPack { try parseObs(json) }

    func testScenesAndLayerTypes() throws {
        let pack = try parsed()
        XCTAssertEqual(pack.scenes.map(\.name), ["Live", "BRB"])
        XCTAssertEqual(pack.scenes[0].layers.map(\.type), [.browser, .image, .text, .media])
        XCTAssertTrue(pack.scenes[1].layers.isEmpty)
    }

    func testGroupTransformIsFlattened() throws {
        let layers = try parsed().scenes[0].layers
        XCTAssertEqual(layers[1].x, 100 + 0.5 * 10, accuracy: 0.001)
        XCTAssertEqual(layers[1].y, 100 + 0.5 * 20, accuracy: 0.001)
        XCTAssertEqual(layers[1].sx, 1.0, accuracy: 0.001)
        XCTAssertTrue(layers[1].visible)
        XCTAssertFalse(layers[2].visible, "hidden inside the group")
    }

    func testSkippedSourcesAreCountedByCategory() throws {
        let pack = try parsed()
        XCTAssertEqual(pack.skipped, ["cameras": 1, "audio": 1, "non-web browser pages": 1])
        XCTAssertEqual(pack.skippedCount, 3)
        XCTAssertTrue(pack.skippedText.hasPrefix("Skipped 3"))
    }

    func testPayloads() throws {
        let layers = try parsed().scenes[0].layers
        XCTAssertEqual(layers[0].data["url"], "https://example.invalid/alerts")
        XCTAssertEqual(layers[0].data["css"], "body{color:red}")
        XCTAssertEqual(layers[0].bw, 960, accuracy: 0.001)
        XCTAssertEqual(layers[2].data["bold"], "true")
        XCTAssertEqual(layers[2].data["color"], String(0xFFFF_0000 as UInt32), "OBS ABGR 0xFF0000FF is opaque red")
        XCTAssertEqual(layers[3].data["loop"], "true")
    }

    func testObsColorOpaquesUnsetAlpha() {
        XCTAssertEqual(obsColor(0x0000_00FF), 0xFFFF_0000, "zero alpha means unset in OBS text sources")
        XCTAssertEqual(obsColor(0x80FF_0000), 0x8000_00FF, "blue stays blue, alpha kept")
    }

    func testPackSurvivesJson() throws {
        let pack = try parsed()
        let back = try JSONDecoder().decode(OverlayPack.self, from: JSONEncoder().encode(pack))
        XCTAssertEqual(back, pack)
        XCTAssertEqual(pack.files, ["E:/fake/Frames/frame.png", "E:/fake/clip.mp4"])
    }

    func testBaseNameHandlesWindowsPaths() {
        XCTAssertEqual(overlayBaseName(#"E:\fake\Frames\frame.png"#), "frame.png")
        XCTAssertEqual(overlayBaseName("E:/fake/clip.mp4"), "clip.mp4")
    }

    func testGarbageIsRejected() throws {
        XCTAssertThrowsError(try parseObs("not json"))
        XCTAssertThrowsError(try parseObs("[1,2]"))
        XCTAssertTrue(try parseObs("{}").scenes.isEmpty)
    }
}
