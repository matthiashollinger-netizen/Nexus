import Foundation

/// Lets Nexus's embedded TFTP/FTP servers be reached on the STANDARD privileged ports
/// (69 / 21) that network gear hardcodes — without running the app as root.
///
/// A non-root, ad-hoc-signed macOS app cannot bind ports below 1024. Instead we ask
/// macOS's built-in packet filter (pf) — once, behind a native admin-password prompt —
/// to REDIRECT the privileged ports to the high ports the app already binds:
///
///     69/udp  →  6969        21/tcp  →  2121
///
/// The redirect rules are loaded into pf's `com.apple/nexus` sub-anchor, which the stock
/// `/etc/pf.conf` evaluates through its `rdr-anchor "com.apple/*"` line, and pf is
/// enabled ref-counted with `pfctl -E`. Every value in the elevated command is
/// hard-coded, so the shell string carries **no user input** (no injection surface).
///
/// Lifecycle: enabling is explicit and persists (the redirect is harmless while Nexus
/// isn't listening — packets to the high port just find no server). It is removed by an
/// explicit `disable()`, which is why we never prompt for a password on quit.
///
/// NOTE: the elevated pf path cannot be exercised in a sandboxed/CI environment; it must
/// be verified on a real machine with admin rights.
enum PrivilegedPortManager {

    static let tftpStandard = 69,  tftpHigh = 6969
    static let ftpStandard  = 21,  ftpHigh  = 2121

    /// Sub-anchor of Apple's namespace so the stock ruleset actually evaluates our rdr.
    private static let anchor = "com.apple/nexus"

    enum PortError: LocalizedError {
        case cancelled
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .cancelled:      return String(localized: "server.error.privileged_denied")
            case .failed(let m):  return String(format: String(localized: "server.error.privileged_failed"), m)
            }
        }
    }

    // MARK: - Public API (call off the main thread — shows a modal admin dialog)

    /// Installs the privileged-port redirects. Shows one admin-password prompt.
    /// Idempotent: re-running replaces the anchor's rules with the same set.
    static func enable() throws {
        // printf expands the \n escapes into the newline-separated rules pf expects.
        let rules =
            "rdr pass inet proto udp from any to any port \(tftpStandard) -> 127.0.0.1 port \(tftpHigh)\\n" +
            "rdr pass inet proto tcp from any to any port \(ftpStandard) -> 127.0.0.1 port \(ftpHigh)\\n"
        let shell = "printf \(shellQuote(rules)) | /sbin/pfctl -a \(anchor) -f - && /sbin/pfctl -E"
        try runAdmin(shell)
    }

    /// Removes the redirects. Shows one admin-password prompt.
    static func disable() throws {
        try runAdmin("/sbin/pfctl -a \(anchor) -F all")
    }

    // MARK: - Elevated execution

    private static func runAdmin(_ shellCommand: String) throws {
        let script = "do shell script \"\(appleScriptEscape(shellCommand))\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let errPipe = Pipe(); proc.standardError = errPipe
        let outPipe = Pipe(); proc.standardOutput = outPipe

        do { try proc.run() } catch { throw PortError.failed(error.localizedDescription) }
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // osascript reports "User canceled" / AppleScript error -128 when the auth
            // dialog is dismissed.
            if msg.localizedCaseInsensitiveContains("cancel") || msg.contains("-128") {
                throw PortError.cancelled
            }
            throw PortError.failed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Escaping (defensive; inputs are already constant)

    /// Wraps a string in POSIX single quotes for `/bin/sh`.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a string for embedding inside an AppleScript double-quoted literal.
    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
