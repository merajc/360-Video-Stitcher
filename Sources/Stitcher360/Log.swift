import Foundation
import os

/// Centralised logging. Diagnostic chatter is emitted at `debug` level so it stays out
/// of the Console by default; failures are emitted at `error` level.
///
/// To watch a run:
///   log stream --predicate 'subsystem == "com.merajc.360VideoStitcher"' --level debug
enum Log {
    private static let subsystem = "com.merajc.360VideoStitcher"
    private static let logger = Logger(subsystem: subsystem, category: "app")

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
