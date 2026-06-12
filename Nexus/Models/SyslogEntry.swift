import Foundation
import SwiftUI

// MARK: - Syslog severity (RFC 5424 §6.2.1)

enum SyslogSeverity: Int, CaseIterable, Identifiable, Hashable {
    case emergency = 0, alert, critical, error, warning, notice, info, debug

    var id: Int { rawValue }

    /// Short keyword used in badges/filters.
    var keyword: String {
        switch self {
        case .emergency: return "EMERG"
        case .alert: return "ALERT"
        case .critical: return "CRIT"
        case .error: return "ERR"
        case .warning: return "WARN"
        case .notice: return "NOTICE"
        case .info: return "INFO"
        case .debug: return "DEBUG"
        }
    }

    /// Anything error-and-worse is red, warnings amber, the rest calm — the same
    /// rationing the rest of the app uses, so a wall of syslog reads at a glance.
    var color: Color {
        switch self {
        case .emergency, .alert, .critical, .error: return DS.Color.stateFailed
        case .warning: return DS.Color.stateConnecting
        case .notice, .info: return DS.Color.stateConnected
        case .debug: return DS.Color.textSecondary
        }
    }

    /// Severities at or above (numerically ≤) error — the "alerts" counter.
    var isAlert: Bool { rawValue <= SyslogSeverity.error.rawValue }
}

// MARK: - A single received syslog message

struct SyslogEntry: Identifiable, Hashable {
    let id: UUID
    let receivedAt: Date
    let deviceTimestamp: Date?
    let sourceIP: String
    let severity: SyslogSeverity
    let facility: Int
    let hostname: String
    let tag: String
    let message: String

    /// Parses a raw syslog datagram (RFC 3164 legacy or RFC 5424) into an entry.
    /// `now` is injected so parsing stays testable.
    static func parse(_ raw: String, sourceIP: String, now: Date) -> SyslogEntry {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var facility = 1            // "user" default when no PRI present
        var severity = SyslogSeverity.notice

        // PRI header: "<PRI>" where PRI = facility*8 + severity.
        if text.hasPrefix("<"), let close = text.firstIndex(of: ">"),
           let pri = Int(text[text.index(after: text.startIndex)..<close]) {
            facility = pri / 8
            severity = SyslogSeverity(rawValue: pri % 8) ?? .notice
            text = String(text[text.index(after: close)...])
        }

        var hostname = ""
        var tag = ""
        var deviceTimestamp: Date? = nil
        var message = text

        // RFC 5424 begins with the version "1 " right after the PRI.
        if text.hasPrefix("1 ") {
            // 1 TIMESTAMP HOSTNAME APP-NAME PROCID MSGID [SD] MSG
            let parts = text.components(separatedBy: " ")
            if parts.count >= 7 {
                deviceTimestamp = iso8601.date(from: parts[1])
                hostname = parts[2] == "-" ? "" : parts[2]
                tag = parts[3] == "-" ? "" : parts[3]
                // Re-join the remainder (skipping PROCID, MSGID, optional SD) as the message.
                message = parts.dropFirst(6).joined(separator: " ")
            }
        } else {
            // RFC 3164: "Mmm dd hh:mm:ss HOST TAG: message"
            let parts = text.components(separatedBy: " ").filter { !$0.isEmpty }
            if parts.count >= 5,
               legacyStamp.date(from: "\(parts[0]) \(parts[1]) \(parts[2])") != nil {
                deviceTimestamp = legacyStamp.date(from: "\(parts[0]) \(parts[1]) \(parts[2])")
                hostname = parts[3]
                let rest = parts.dropFirst(4).joined(separator: " ")
                if let colon = rest.firstIndex(of: ":") {
                    tag = String(rest[..<colon]).trimmingCharacters(in: .whitespaces)
                    message = String(rest[rest.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    message = rest
                }
            }
        }

        return SyslogEntry(
            id: UUID(), receivedAt: now, deviceTimestamp: deviceTimestamp,
            sourceIP: sourceIP, severity: severity, facility: facility,
            hostname: hostname, tag: tag, message: message
        )
    }

    private static let iso8601: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"   // tolerate fractional/zone tail being ignored
        return f
    }()

    private static let legacyStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d HH:mm:ss"
        return f
    }()
}
