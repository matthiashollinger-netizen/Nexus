import Foundation

/// Injects ANSI colour codes into plain-text terminal output.
///
/// Rules applied (in priority order):
///   MAC address  → yellow
///   IPv4 address → cyan
///   Error words  → bold red
///   Success words → green
///   Warning words → yellow
///
/// Lines that already contain any ESC sequence are passed through unchanged
/// so that interactive programs (vim, htop, …) keep their own colours.
final class TerminalHighlighter {

    static let shared = TerminalHighlighter()

    // ANSI colour codes
    private let yellow   = "\u{1B}[33m"
    private let cyan     = "\u{1B}[36m"
    private let boldRed  = "\u{1B}[1;31m"
    private let green    = "\u{1B}[32m"
    private let reset    = "\u{1B}[0m"

    private struct Rule {
        let regex: NSRegularExpression
        let open: String
        let close: String
    }

    private let rules: [Rule]

    private init() {
        func re(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: options)
        }

        let y  = "\u{1B}[33m"
        let c  = "\u{1B}[36m"
        let r  = "\u{1B}[1;31m"
        let g  = "\u{1B}[32m"
        let rst = "\u{1B}[0m"

        rules = [
            // MAC address  aa:bb:cc:dd:ee:ff  or  aa-bb-cc-dd-ee-ff
            Rule(regex: re("[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}|[0-9A-Fa-f]{2}(?:-[0-9A-Fa-f]{2}){5}"),
                 open: y, close: rst),

            // IPv4 address
            Rule(regex: re("\\b(?:(?:25[0-5]|2[0-4]\\d|[01]?\\d\\d?)\\.){3}" +
                           "(?:25[0-5]|2[0-4]\\d|[01]?\\d\\d?)\\b"),
                 open: c, close: rst),

            // Error / failure keywords (case-insensitive)
            Rule(regex: re("\\b(?:error|fail(?:ed|ure)?|false|down|critical|denied|" +
                           "timeout|unreachable|refused|inactive|disabled|not found|" +
                           "not running|administratively down)\\b",
                           options: .caseInsensitive),
                 open: r, close: rst),

            // Success / ok keywords (case-insensitive)
            Rule(regex: re("\\b(?:ok|true|up|success(?:ful)?|active|connected|running|" +
                           "enabled|online|reachable|yes)\\b",
                           options: .caseInsensitive),
                 open: g, close: rst),

            // Warning keywords (case-insensitive)
            Rule(regex: re("\\b(?:warn(?:ing)?|notice|caution|deprecated)\\b",
                           options: .caseInsensitive),
                 open: y, close: rst),
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

    // MARK: - Private

    private func applyRules(to text: String) -> String {
        struct Hit {
            let range: Range<String.Index>
            let open: String
            let close: String
        }

        // Collect all matches from all rules
        var hits: [Hit] = []
        for rule in rules {
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
