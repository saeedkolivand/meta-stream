import Foundation
import SwiftUI

/// One log for everything: mirrored to the device console (os_log, public) and kept in memory for the Logs screen.
@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()
    @Published private(set) var text = ""
    private var lines: [String] = []
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
    /// Documents/metastream.log -- os_log lines never reach Windows (see device-debugging notes), this file does:
    /// `pymobiledevice3 apps pull com.saeedkolivand.metastream Documents/metastream.log app.log`
    /// ponytail: starts over at launch once past 2 MB instead of rotating.
    private let file: FileHandle? = {
        let url = URL.documentsDirectory.appending(path: "metastream.log")
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 2_000_000 { try? fm.removeItem(at: url) }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        _ = try? h?.seekToEnd()
        return h
    }()

    func add(_ line: String) {
        let stamped = Self.fmt.string(from: Date()) + " " + line
        try? file?.write(contentsOf: Data((stamped + "\n").utf8))
        lines.append(stamped)
        text += (text.isEmpty ? "" : "\n") + stamped
        if lines.count > 2200 {
            let drop = lines.count - 2000
            lines.removeFirst(drop)
            var idx = text.startIndex
            for _ in 0..<drop {
                guard let nl = text[idx...].firstIndex(of: "\n") else { idx = text.endIndex; break }
                idx = text.index(after: nl)
            }
            text = String(text[idx...])
        }
    }
    func clear() { lines = []; text = "" }
}

/// Masks values of JSON/query fields that look like credentials before they reach the log or the console.
/// Covers stream keys (Kick `key`, Twitch `stream_key`, Restream `streamKey`, YouTube `streamName`) and OAuth material.
private let secretField = try! NSRegularExpression(
    pattern: #"("(?:[a-zA-Z_]*(?:key|token|secret|password|authorization|streamName)[a-zA-Z_]*)"\s*:\s*")([^"]*)(")"#,
    options: [.caseInsensitive])
private let streamIDField = try! NSRegularExpression(pattern: #"streamid=[^&\s"]*"#, options: [.caseInsensitive])
private let keyParamField = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])key=[^&\s"]*"#, options: [.caseInsensitive])
func redact(_ s: String) -> String {
    var out = secretField.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1***$3")
    out = streamIDField.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "streamid=***")
    out = keyParamField.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "key=***")
    return out
}

/// SRT Ingest URLs carry the secret as `?streamid=...`; strip the value so URLs are safe to log.
/// Falls back to `redact` when the string is not a parseable URL.
func redactedURL(_ s: String) -> String {
    guard var c = URLComponents(string: s), c.queryItems != nil else { return redact(s) }
    c.queryItems = c.queryItems!.map {
        $0.name.lowercased() == "streamid" ? URLQueryItem(name: $0.name, value: "***") : $0
    }
    return redact(c.string ?? s)
}

func redactedURL(_ url: URL) -> String { redactedURL(url.absoluteString) }

struct LogView: View {
    @ObservedObject var store = LogStore.shared
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(store.text.isEmpty ? "No log lines yet." : store.text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .id("end")
            }
            .onChange(of: store.text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { ShareLink(item: store.text) { Image(systemName: "square.and.arrow.up") } }
            ToolbarItem(placement: .cancellationAction) { Button("Clear") { store.clear() } }
        }
    }
}
