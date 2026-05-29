import Foundation

// MARK: - Highlight Ruleset IDs

enum HighlightRuleset: String, CaseIterable {
    case `default` = "default"
    case ciscoIOS  = "cisco"
    case logLevel  = "log"
    case network   = "network"
}

/// Injects ANSI colour codes into plain-text terminal output.
///
/// Rules applied (in priority order):
///   MAC address  → yellow
///   IPv4 address → cyan
///   Error words  → bold red
///   Success words → green
///   Warning words → yellow
///   Cisco IOS     → blue/green/cyan (cisco ruleset)
///   Log levels    → extended (log ruleset)
///   URLs/ports    → magenta/underline (network ruleset)
///
/// Lines that already contain any ESC sequence are passed through unchanged
/// so that interactive programs (vim, htop, …) keep their own colours.
final class TerminalHighlighter {

    static let shared = TerminalHighlighter()

    // ANSI colour codes
    private let yellow    = "\u{1B}[33m"
    private let cyan      = "\u{1B}[36m"
    private let boldRed   = "\u{1B}[1;31m"
    private let green     = "\u{1B}[32m"
    private let orange    = "\u{1B}[38;5;208m"
    private let blue      = "\u{1B}[34m"
    private let boldBlue  = "\u{1B}[1;34m"
    private let magenta   = "\u{1B}[35m"
    private let underline = "\u{1B}[4m"
    private let reset     = "\u{1B}[0m"

    private struct Rule {
        let regex: NSRegularExpression
        let open: String
        let close: String
        let rulesets: Set<HighlightRuleset>
    }

    private let rules: [Rule]

    /// Which rulesets are enabled — can be changed at runtime from AppSettings
    var enabledRulesets: Set<HighlightRuleset> = [.default, .logLevel]

    private init() {
        func re(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
            // swiftlint:disable:next force_try
            (try? NSRegularExpression(pattern: pattern, options: options)) ??
                (try! NSRegularExpression(pattern: "(?!)", options: []))
        }

        let y  = "\u{1B}[33m"
        let c  = "\u{1B}[36m"
        let r  = "\u{1B}[1;31m"
        let g  = "\u{1B}[32m"
        let o  = "\u{1B}[38;5;208m"
        let b  = "\u{1B}[34m"
        let bb = "\u{1B}[1;34m"
        let m  = "\u{1B}[35m"
        let u  = "\u{1B}[4m"
        let rst = "\u{1B}[0m"

        rules = [
            // ── Default ruleset ─────────────────────────────────────────────

            // MAC address  aa:bb:cc:dd:ee:ff  or  aa-bb-cc-dd-ee-ff
            Rule(regex: re("[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}|[0-9A-Fa-f]{2}(?:-[0-9A-Fa-f]{2}){5}"),
                 open: y, close: rst, rulesets: [.default]),

            // IPv4 address
            Rule(regex: re("\\b(?:(?:25[0-5]|2[0-4]\\d|[01]?\\d\\d?)\\.){3}" +
                           "(?:25[0-5]|2[0-4]\\d|[01]?\\d\\d?)\\b"),
                 open: c, close: rst, rulesets: [.default]),

            // Error / failure keywords (case-insensitive)
            Rule(regex: re("\\b(?:error|fail(?:ed|ure)?|false|down|critical|denied|" +
                           "timeout|unreachable|refused|inactive|disabled|not found|" +
                           "not running|administratively down)\\b",
                           options: .caseInsensitive),
                 open: r, close: rst, rulesets: [.default]),

            // Success / ok keywords (case-insensitive)
            Rule(regex: re("\\b(?:ok|true|up|success(?:ful)?|active|connected|running|" +
                           "enabled|online|reachable|yes)\\b",
                           options: .caseInsensitive),
                 open: g, close: rst, rulesets: [.default]),

            // Warning keywords (case-insensitive)
            Rule(regex: re("\\b(?:warn(?:ing)?|notice|caution|deprecated)\\b",
                           options: .caseInsensitive),
                 open: y, close: rst, rulesets: [.default]),

            // ── Log Level ruleset ────────────────────────────────────────────

            // ERROR / CRITICAL  → bold red
            Rule(regex: re("\\b(?:ERROR|CRITICAL|FATAL|SEVERE)\\b"),
                 open: r, close: rst, rulesets: [.logLevel]),

            // WARN / WARNING → orange
            Rule(regex: re("\\b(?:WARN(?:ING)?|ALERT)\\b"),
                 open: o, close: rst, rulesets: [.logLevel]),

            // INFO → blue
            Rule(regex: re("\\bINFO\\b"),
                 open: b, close: rst, rulesets: [.logLevel]),

            // SUCCESS / OK → green
            Rule(regex: re("\\b(?:SUCCESS|OK|DONE|PASS(?:ED)?)\\b"),
                 open: g, close: rst, rulesets: [.logLevel]),

            // DEBUG → cyan
            Rule(regex: re("\\bDEBUG\\b"),
                 open: c, close: rst, rulesets: [.logLevel]),

            // ── Cisco IOS ruleset ────────────────────────────────────────────

            // Cisco prompts: Router#, Switch>, Router(config)#
            Rule(regex: re("^[A-Za-z0-9_-]+(?:\\(config[^)]*\\))?[#>]\\s",
                           options: .anchorsMatchLines),
                 open: bb, close: rst, rulesets: [.ciscoIOS]),

            // Cisco keywords
            Rule(regex: re("\\b(?:interface|ip address|no shutdown|show|configure terminal|" +
                           "hostname|router|spanning-tree|vlan|switchport|access-list|" +
                           "line vty|service password-encryption|enable secret|" +
                           "shutdown|description|duplex|speed)\\b",
                           options: .caseInsensitive),
                 open: b, close: rst, rulesets: [.ciscoIOS]),

            // Cisco interface types
            Rule(regex: re("\\b(?:GigabitEthernet|FastEthernet|Ethernet|Serial|Loopback|" +
                           "Vlan|Tunnel|Management)\\d+(?:\\/\\d+)*\\b",
                           options: .caseInsensitive),
                 open: c, close: rst, rulesets: [.ciscoIOS]),

            // ── Network ruleset ───────────────────────────────────────────────

            // URLs (https/http/ftp/ssh)
            Rule(regex: re("(?:https?|ftp|ssh)://[A-Za-z0-9._~:/?#\\[\\]@!$&'()*+,;=%]+"),
                 open: m + u, close: rst, rulesets: [.network]),

            // Port numbers :80, :443, :22, :8080
            Rule(regex: re(":\\b(80|443|22|23|8080|8443|3306|5432|6379|27017|21|25|53|" +
                           "3389|5900|9200|9300|6443|2375|2376|5000|8000|9000|4433)\\b"),
                 open: m, close: rst, rulesets: [.network]),
        ]
    }

    // MARK: - Public API

    /// Processes a raw byte chunk from the terminal output stream.
    /// Returns modified bytes with ANSI highlighting, or the original bytes unchanged.
    func process(_ bytes: [UInt8]) -> [UInt8] {
        guard let text = String(bytes: bytes, encoding: .utf8) else { return bytes }

        // If ANY ESC byte is present, the stream is already coloured — leave it alone.
        guard !text.contains("\u{1B}") else { return bytes }

        let highlighted = applyRules(to: text)
        // Only replace if something changed (avoids unnecessary allocation)
        guard highlighted != text else { return bytes }
        return Array(highlighted.utf8)
    }

    /// Update which rulesets are active based on AppSettings string array.
    func updateEnabledRulesets(_ names: [String]) {
        enabledRulesets = Set(names.compactMap { HighlightRuleset(rawValue: $0) })
    }

    // MARK: - Private

    private func applyRules(to text: String) -> String {
        struct Hit {
            let range: Range<String.Index>
            let open: String
            let close: String
        }

        // Collect all matches from enabled rulesets
        var hits: [Hit] = []
        for rule in rules where !rule.rulesets.isDisjoint(with: enabledRulesets) {
            let ns = NSRange(text.startIndex..., in: text)
            for m in rule.regex.matches(in: text, range: ns) {
                if let r = Range(m.range, in: text) {
                    hits.append(Hit(range: r, open: rule.open, close: rule.close))
                }
            }
        }
        guard !hits.isEmpty else { return text }

        // Sort by position; discard overlapping (first match wins)
        hits.sort { $0.range.lowerBound < $1.range.lowerBound }
        var kept: [Hit] = []
        var cursor = text.startIndex
        for h in hits {
            if h.range.lowerBound >= cursor {
                kept.append(h)
                cursor = h.range.upperBound
            }
        }

        // Build output string
        var out = ""
        var pos = text.startIndex
        for h in kept {
            out += text[pos..<h.range.lowerBound]
            out += h.open + text[h.range] + h.close
            pos = h.range.upperBound
        }
        out += text[pos...]
        return out
    }
}
