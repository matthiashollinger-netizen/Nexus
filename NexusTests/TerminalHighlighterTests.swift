import Testing
import Foundation
@testable import Nexus

/// Tests for context-sensitive port highlighting — a timestamp must NOT be
/// mistaken for a port, while real host:port / "port N" forms should highlight.
struct TerminalHighlighterTests {

    private let esc = "\u{1B}"   // ANSI escape introducer

    private func highlight(_ line: String, rulesets: Set<HighlightRuleset>) -> String {
        let h = TerminalHighlighter()
        h.enabledRulesets = rulesets
        let out = h.process(Array(line.utf8))
        return String(bytes: out, encoding: .utf8) ?? line
    }

    @Test func timestampIsNotHighlightedAsPort() {
        // Only the network ruleset, so default/log rules don't add noise.
        let line = "2026-06-02 20:22:51 system started"
        let result = highlight(line, rulesets: [.network])
        // No ANSI escape should be injected — the timestamp is not a port.
        #expect(!result.contains(esc))
    }

    @Test func ipWithPortIsHighlighted() {
        let line = "connecting to 10.0.0.1:8080 now"
        let result = highlight(line, rulesets: [.network])
        #expect(result.contains(esc))         // the :8080 port is coloured
        #expect(result.contains(":8080"))     // text preserved
    }

    @Test func hostnameWithPortIsHighlighted() {
        let line = "ssh localhost:22"
        let result = highlight(line, rulesets: [.network])
        #expect(result.contains(esc))
    }

    @Test func portKeywordIsHighlighted() {
        let line = "Server listening on Port 2222"
        let result = highlight(line, rulesets: [.network])
        #expect(result.contains(esc))
    }

    @Test func plainTimeRangeNotHighlighted() {
        // A bare time range like "12:00-13:00" must stay uncoloured.
        let line = "window 12:00-13:00 maintenance"
        let result = highlight(line, rulesets: [.network])
        #expect(!result.contains(esc))
    }

    @Test func alreadyColouredLineIsLeftAlone() {
        // Lines that already contain ANSI are passed through unchanged.
        let coloured = "\(esc)[31mred\(esc)[0m 10.0.0.1:80"
        let result = highlight(coloured, rulesets: [.network])
        #expect(result == coloured)
    }
}
