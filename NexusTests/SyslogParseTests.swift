import Testing
import Foundation
@testable import Nexus

/// Tests for the RFC 3164 / RFC 5424 syslog parser (the flagship server feature).
struct SyslogParseTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func parsesPriorityFacilityAndSeverity() {
        // <134> = facility 16 (local0), severity 6 (info)
        let e = SyslogEntry.parse("<134>test message", sourceIP: "10.0.0.1", now: now)
        #expect(e.facility == 16)
        #expect(e.severity == .info)
        #expect(e.sourceIP == "10.0.0.1")
    }

    @Test func errorSeverityIsAlert() {
        // <131> = facility 16, severity 3 (error)
        let e = SyslogEntry.parse("<131>link down", sourceIP: "10.0.0.2", now: now)
        #expect(e.severity == .error)
        #expect(e.severity.isAlert)
    }

    @Test func debugIsNotAlert() {
        // <191> = severity 7 (debug)
        let e = SyslogEntry.parse("<191>verbose", sourceIP: "10.0.0.3", now: now)
        #expect(e.severity == .debug)
        #expect(!e.severity.isAlert)
    }

    @Test func parsesRFC3164Legacy() {
        // <34>Oct 11 22:14:15 mymachine su: 'su root' failed
        let e = SyslogEntry.parse("<34>Oct 11 22:14:15 switch01 mgmt: interface Gi0/1 down",
                                  sourceIP: "192.168.90.1", now: now)
        #expect(e.severity == .critical)        // 34 % 8 = 2
        #expect(e.hostname == "switch01")
        #expect(e.tag == "mgmt")
        #expect(e.message == "interface Gi0/1 down")
    }

    @Test func parsesRFC5424() {
        let raw = "<165>1 2003-10-11T22:14:15 host1 evntslog ID47 - message text here"
        let e = SyslogEntry.parse(raw, sourceIP: "192.168.90.2", now: now)
        #expect(e.hostname == "host1")
        #expect(e.tag == "evntslog")
        #expect(e.message.contains("message text here"))
    }

    @Test func noPriorityDoesNotCrash() {
        let e = SyslogEntry.parse("a bare line without a priority", sourceIP: "1.2.3.4", now: now)
        #expect(e.message.contains("bare line"))
    }
}
