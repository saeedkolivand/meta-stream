import CoreModel
import Foundation
import Observation

/// One log for everything: mirrored to the device console (os_log, public) and kept in memory for the Logs screen.
@MainActor
@Observable
public final class LogStore {
    public static let shared = LogStore()
    public private(set) var text = ""
    @ObservationIgnored private var lines: [String] = []
    private static let stampFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    /// Documents/metastream.log -- os_log lines never reach Windows (see device-debugging notes), this file does:
    /// `pymobiledevice3 apps pull com.saeedkolivand.metastream Documents/metastream.log app.log`
    /// Survives restarts; past 5 MB at launch it moves to metastream.1.log (one previous file kept, ~a shift each).
    private let file: FileHandle? = {
        let url = URL.documentsDirectory.appending(path: "metastream.log")
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 5_000_000 {
            let old = URL.documentsDirectory.appending(path: "metastream.1.log")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        let handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        try? handle?.write(contentsOf: Data("=== launch \(Date().formatted(.iso8601)) ===\n".utf8))   // lines carry only the time
        return handle
    }()

    public func add(_ line: String) {
        let stamped = Self.stampFormat.string(from: Date()) + " " + line
        try? file?.write(contentsOf: Data((stamped + "\n").utf8))
        lines.append(stamped)
        text += (text.isEmpty ? "" : "\n") + stamped
        if lines.count > 2200 {
            let drop = lines.count - 2000
            lines.removeFirst(drop)
            var idx = text.startIndex
            for _ in 0..<drop {
                guard let newline = text[idx...].firstIndex(of: "\n") else { idx = text.endIndex; break }
                idx = text.index(after: newline)
            }
            text = String(text[idx...])
        }
    }

    public func clear() {
        lines = []
        text = ""
    }
}

/// Masks values of JSON/query fields that look like credentials before they reach the log or the console.
/// Covers stream keys (Kick `key`, Twitch `stream_key`, Restream `streamKey`, YouTube `streamName`) and OAuth material.
private let secretField = NSRegularExpression.literal(
    #"("(?:[a-zA-Z_]*(?:key|token|secret|password|authorization|streamName)[a-zA-Z_]*)"\s*:\s*")([^"]*)(")"#,
    options: [.caseInsensitive])
private let streamIDField = NSRegularExpression.literal(#"streamid=[^&\s"]*"#, options: [.caseInsensitive])
private let keyParamField = NSRegularExpression.literal(#"(?<![A-Za-z0-9_])key=[^&\s"]*"#, options: [.caseInsensitive])

public func redact(_ text: String) -> String {
    var out = secretField.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1***$3")
    out = streamIDField.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "streamid=***")
    out = keyParamField.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "key=***")
    return out
}

/// SRT Ingest URLs carry the secret as `?streamid=...`; strip the value so URLs are safe to log.
/// Falls back to `redact` when the string is not a parseable URL.
public func redactedURL(_ text: String) -> String {
    guard var parts = URLComponents(string: text), let items = parts.queryItems else { return redact(text) }
    parts.queryItems = items.map { $0.name.lowercased() == "streamid" ? URLQueryItem(name: $0.name, value: "***") : $0 }
    return redact(parts.string ?? text)
}

public func redactedURL(_ url: URL) -> String { redactedURL(url.absoluteString) }
