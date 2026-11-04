import Foundation
import os

protocol Logging: Sendable {
    func log(category: String, message: String, error: Bool)
}

final class OSLogLogger: Logging, @unchecked Sendable {
    private let loggers: [String: Logger] = ["api", "stream", "glasses", "auth", "ui"].reduce(into: [:]) {
        $0[$1] = Logger(subsystem: "com.saeedkolivand.metastream", category: $1)
    }
    private let fallback = Logger(subsystem: "com.saeedkolivand.metastream", category: "ui")
    func log(category: String, message: String, error: Bool) {
        let logger = loggers[category] ?? fallback
        if error { logger.error("\(message, privacy: .public)") } else { logger.info("\(message, privacy: .public)") }
    }
}

final class InMemoryLogger: Logging, @unchecked Sendable {
    func log(category: String, message: String, error: Bool) {
        Task { @MainActor in LogStore.shared.add("[\(category)] \(message)") }
    }
}

final class CompositeLogger: Logging, @unchecked Sendable {
    private let loggers: [Logging]
    init(_ loggers: [Logging]) { self.loggers = loggers }
    func log(category: String, message: String, error: Bool) {
        for logger in loggers { logger.log(category: category, message: message, error: error) }
    }
}

enum AppLogger {
    static let shared: Logging = CompositeLogger([OSLogLogger(), InMemoryLogger()])
}

/// The one log call: redacted, then to the device console (os_log, public) and the in-app Logs screen + file.
public func applog(_ category: String, _ message: String, error: Bool = false) {
    AppLogger.shared.log(category: category, message: redact(message), error: error)
}
