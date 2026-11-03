// Screen share contract between the app and the MetaStreamScreen broadcast extension (adr/0003).
// Foundation only: the extension must not see anything app-only.
import Foundation

public enum ScreenIPC {
    public static let group = "group.com.saeedkolivand.metastream"
    public static let frameNote = "com.saeedkolivand.metastream.screen.frame"
    public static let startedNote = "com.saeedkolivand.metastream.screen.started"
    public static let stoppedNote = "com.saeedkolivand.metastream.screen.stopped"
    public static let ring = 8   // frame files <seq % 8>.frame; the app reads at most this far behind the newest

    public static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appending(path: "screen", directoryHint: .isDirectory)
    }
    public static func frameFile(_ seq: UInt32, in dir: URL) -> URL { dir.appending(path: "\(Int(seq) % ring).frame") }
    public static func latestFile(in dir: URL) -> URL { dir.appending(path: "latest") }

    /// One encoded frame's fixed 28-byte little-endian header; the file is
    /// header | `sets` x (u32 length, bytes) | AVCC frame bytes. Parameter sets (VPS/SPS/PPS or SPS/PPS) ride on keyframes only.
    public struct Header: Sendable {
        public var hevc: Bool
        public var key: Bool
        public var orientation: UInt8   // CGImagePropertyOrientation raw value from ReplayKit (1 = up)
        public var sets: UInt8
        public var ptsMicros: Int64
        public var width: UInt32
        public var height: UInt32
        public var seq: UInt32

        public init(
            hevc: Bool, key: Bool, orientation: UInt8, sets: UInt8, ptsMicros: Int64, width: UInt32, height: UInt32, seq: UInt32
        ) {
            self.hevc = hevc
            self.key = key
            self.orientation = orientation
            self.sets = sets
            self.ptsMicros = ptsMicros
            self.width = width
            self.height = height
            self.seq = seq
        }
    }
    public static let headerSize = 28
    private static let magic: [UInt8] = Array("MSF1".utf8)

    public static func pack(_ header: Header, sets: [Data], payload: Data) -> Data {
        func put<T: FixedWidthInteger>(_ value: T, _ out: inout Data) {
            withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) }
        }
        var out = Data(magic)
        out.append(contentsOf: [header.hevc ? 0 : 1, header.key ? 1 : 0, header.orientation, UInt8(sets.count)])
        put(header.ptsMicros, &out)
        put(header.width, &out)
        put(header.height, &out)
        put(header.seq, &out)
        for set in sets {
            put(UInt32(set.count), &out)
            out.append(set)
        }
        out.append(payload)
        return out
    }

    public static func unpack(_ data: Data) -> (Header, [Data], Data)? {
        guard data.count >= headerSize, Array(data.prefix(4)) == magic else { return nil }
        func get<T: FixedWidthInteger>(_ at: Int, _ type: T.Type) -> T {
            T(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: T.self) })
        }
        let flags = [UInt8](data.subdata(in: data.startIndex + 4..<data.startIndex + 8))
        let header = Header(hevc: flags[0] == 0, key: flags[1] == 1, orientation: flags[2], sets: flags[3],
                            ptsMicros: get(8, Int64.self), width: get(16, UInt32.self), height: get(20, UInt32.self),
                            seq: get(24, UInt32.self))
        var off = headerSize
        var sets: [Data] = []
        for _ in 0..<header.sets {
            guard off + 4 <= data.count else { return nil }
            let length = Int(get(off, UInt32.self))
            off += 4
            guard off + length <= data.count else { return nil }
            sets.append(data.subdata(in: data.startIndex + off..<data.startIndex + off + length))
            off += length
        }
        return (header, sets, data.subdata(in: data.startIndex + off..<data.endIndex))
    }
}
