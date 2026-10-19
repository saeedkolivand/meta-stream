// Screen share contract: compiled into BOTH the app and the MetaStreamScreen broadcast extension
// (adr/0003). Foundation only: the extension must not see anything app-only.
import Foundation

enum ScreenIPC {
    static let group = "group.com.saeedkolivand.metastream"
    static let frameNote = "com.saeedkolivand.metastream.screen.frame"
    static let startedNote = "com.saeedkolivand.metastream.screen.started"
    static let stoppedNote = "com.saeedkolivand.metastream.screen.stopped"
    static let ring = 8   // frame files <seq % 8>.frame; the app reads at most this far behind the newest

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appending(path: "screen", directoryHint: .isDirectory)
    }
    static func frameFile(_ seq: UInt32, in dir: URL) -> URL { dir.appending(path: "\(Int(seq) % ring).frame") }
    static func latestFile(in dir: URL) -> URL { dir.appending(path: "latest") }

    /// One encoded frame's fixed 28-byte little-endian header; the file is
    /// header | `sets` x (u32 length, bytes) | AVCC frame bytes. Parameter sets (VPS/SPS/PPS or SPS/PPS) ride on keyframes only.
    struct Header {
        var hevc: Bool
        var key: Bool
        var orientation: UInt8   // CGImagePropertyOrientation raw value from ReplayKit (1 = up)
        var sets: UInt8
        var ptsMicros: Int64
        var width: UInt32
        var height: UInt32
        var seq: UInt32
    }
    static let headerSize = 28
    private static let magic: [UInt8] = Array("MSF1".utf8)

    static func pack(_ h: Header, sets: [Data], payload: Data) -> Data {
        func put<T: FixedWidthInteger>(_ v: T, _ d: inout Data) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        var d = Data(magic)
        d.append(contentsOf: [h.hevc ? 0 : 1, h.key ? 1 : 0, h.orientation, UInt8(sets.count)])
        put(h.ptsMicros, &d); put(h.width, &d); put(h.height, &d); put(h.seq, &d)
        for s in sets { put(UInt32(s.count), &d); d.append(s) }
        d.append(payload)
        return d
    }

    static func unpack(_ d: Data) -> (Header, [Data], Data)? {
        guard d.count >= headerSize, Array(d.prefix(4)) == magic else { return nil }
        func get<T: FixedWidthInteger>(_ at: Int, _ t: T.Type) -> T {
            T(littleEndian: d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: T.self) })
        }
        let b = [UInt8](d.subdata(in: d.startIndex + 4..<d.startIndex + 8))
        let h = Header(hevc: b[0] == 0, key: b[1] == 1, orientation: b[2], sets: b[3],
                       ptsMicros: get(8, Int64.self), width: get(16, UInt32.self), height: get(20, UInt32.self), seq: get(24, UInt32.self))
        var off = headerSize
        var sets: [Data] = []
        for _ in 0..<h.sets {
            guard off + 4 <= d.count else { return nil }
            let n = Int(get(off, UInt32.self)); off += 4
            guard off + n <= d.count else { return nil }
            sets.append(d.subdata(in: d.startIndex + off..<d.startIndex + off + n)); off += n
        }
        return (h, sets, d.subdata(in: d.startIndex + off..<d.endIndex))
    }
}
