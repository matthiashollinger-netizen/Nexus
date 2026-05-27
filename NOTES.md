# Nexus — Development Notes

## Architecture Decisions

### App Sandbox: DISABLED
Nexus is a developer tool requiring unrestricted access to:
- Serial/COM ports (IOKit)
- Arbitrary network connections (SSH, Telnet)
- PTY creation (SwiftTerm LocalProcess)

### SSH Implementation
Uses the **system `/usr/bin/ssh` binary** via SwiftTerm's `LocalProcess` (which creates a proper PTY using `openpty()`).
- Password authentication: auto-detects "password:" prompt in terminal output and sends stored credentials
- Legacy algorithms: passed via `-o` flags (`KexAlgorithms`, `HostKeyAlgorithms`, `PubkeyAcceptedAlgorithms`)
- Private key from password manager: written to a temp file (0600 permissions), deleted on disconnect

### Terminal Emulator
Uses **SwiftTerm** (SPM: `https://github.com/migueldeicaza/SwiftTerm`) — a mature VT100/xterm emulator used in many commercial macOS SSH clients.
- SSH: `LocalTerminalView` subclass (manages its own PTY + process)
- Telnet/Serial: `TerminalView` + Network.framework / IOKit data bridge

### Database
- Plain JSON for sessions/folders/settings (`~/Library/Application Support/Nexus/`)
- AES-256-GCM encrypted JSON for credentials (`credentials.enc`)
- Key derivation: HKDF-SHA256 from master password + random 32-byte salt
- Export format: same AES-256-GCM encrypted JSON bundle

### Password Inheritance
Sessions inherit credentials from their parent folder chain if no direct credential is assigned.

## Known Limitations / TODOs

1. **SSH_ASKPASS**: Password auto-send relies on scanning terminal output for "password:" — fragile for non-English SSH daemons. Future: implement proper SSH_ASKPASS helper.
2. **Terminal resize (SIGWINCH)**: SwiftTerm handles this automatically for the SSH case via its LocalProcess.
3. **Serial port listing**: Uses IOKit `kIOSerialBSDServiceValue` — only lists tty.* devices. USB serial adapters should appear automatically.
4. **Drag & Drop** in sidebar: Visually reordering sessions/folders via drag & drop is planned for v1.1. Currently, sortOrder is set at creation time.
5. **Telnet protocol handling**: Current implementation is raw TCP. Proper Telnet option negotiation (IAC) is partially handled by the terminal emulator.

## Version 2.0 Architecture Prep
- `ConnectionType` enum has room for `.rdp`, `.vnc`, `.http` cases
- `ConnectionSession` uses a protocol-based service pattern — add `RDPService`, `VNCService` without changing `ConnectionSession`
- `DatabaseService` is versioned via the export format — forward migration possible

## Build Requirements
- Xcode 26.5+
- macOS 26.5+ deployment target
- SwiftTerm resolves automatically via SPM on first build
