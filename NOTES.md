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

## Sidebar click & drag — why the current design is stable (v2.3.0)

The single-click / double-click behaviour regressed THREE times. Root causes and the
permanent fixes (do not revert these without understanding why):

### Single-click only worked "beside the text"
Cause: `.onDrag` / `.draggable` applied to the **row content**. On macOS this steals
the `List` single-click selection on exactly the area the modifier covers, so only the
leading inset still selected.
Fix: the drag source (`.onDrag`) lives ONLY on a small trailing grip handle
(`SidebarDragHandle`), never on the selectable text. The row content is a clean List
selection target via `.contentShape(Rectangle())`.

### Double-click opened the previously-selected item, not the clicked one
Cause: a GLOBAL `NSEvent` monitor (`SidebarDoubleClickMonitor`) that connected
`vm.selectedSidebarItem` — i.e. the already-selected item. Double-clicking a different,
not-yet-selected row fired before the selection updated → wrong item.
Fix: a per-row `simultaneousGesture(TapGesture(count: 2))` that captures THIS row's
`session` value, so it is always the correct item. No global state, no monitor.
`simultaneousGesture` coexists with List's single-click selection.

### Drag had no visible insertion indicator
Cause: `.onMove`'s native line was suppressed by the row `.onDrag`, and cross-folder
`.onDrop` only highlighted the folder.
Fix: each row is its own `.onDrop` target; while hovered it publishes itself to the
shared `SidebarDragModel`, which draws an accent `InsertionLine` above the row
(reorder) or a folder highlight (move-into). Fully under our control, no `.onMove`.

RULE: never put `.onDrag`/`.draggable` on the row's selectable content again. Keep the
grip handle as the only drag source.
