# Changelog

---

## [2.0.0] - 2026-05-29

### Neu

- **Feature 4 — SFTP-Browser**: Integrierter SFTP-Dateimanager (280pt Seitenleiste)
  - Toggle-Button in der Toolbar (Ordner-Icon) — sichtbar wenn SSH-Session aktiv
  - Breadcrumb-Navigation, Dateiliste mit Icon/Name/Größe/Datum
  - Upload/Download, Umbenennen, Löschen, Neuer Ordner via Kontextmenü
  - Progress-Overlay bei Transfers, Hidden-Files-Toggle
  - Nutzt /usr/bin/sftp -b- (kein externes Framework)

- **Feature 5 — Eingebauter Texteditor**:
  - NSTextView-basierter Editor mit Zeilennummern (RulerView)
  - Syntax-Highlighting für Swift, Python, Bash, JSON, YAML, XML/HTML
  - NSTextFinder (⌘F / ⌘H), Encoding-Wahl, Schriftgrößensteuerung (⌘+ / ⌘-)
  - SFTP-Doppelklick öffnet Datei im Editor → automatischer Re-Upload nach Speichern

- **Feature 6 — Makros + Hotkeys + Zeitplanung**:
  - Makro-Manager-Fenster: Liste + Editor, Befehle (mehrzeilig), Delay-Slider (0–5s)
  - Hotkey-Recorder: globale Tastenkürzel für direktes Ausführen
  - Zeitplanung: Interval-Timer + "Bei Verbindung ausführen"-Option
  - Persistenz in ~/Library/Application Support/Nexus/macros.json
  - Menü-Integration: Makros-Menü mit allen definierten Makros

- **Feature 7 — Eingebettete Server**:
  - HTTP-Server (python3 -m http.server), FTP (pyftpdlib), TFTP (/usr/libexec/tftpd)
  - 2-Spalten Grid mit Server-Karten, Start/Stop/Konfigurieren-Buttons
  - Log-Viewer (letzte 200 Zeilen), AutoStart-Option
  - Eigenes Fenster ("servers")

- **Feature 8 — RDP via FreeRDP**:
  - NexusRDPTerminalView ersetzt Platzhalter
  - Sucht xfreerdp3/xfreerdp in /opt/homebrew/bin und /usr/local/bin
  - Installation-Anleitung mit "brew install freerdp"-Copy-Button falls Binary fehlt
  - Reconnect-Button nach Verbindungsabbruch

- **Feature 9 — Erweitertes Syntax-Highlighting**:
  - Cisco IOS: Prompts (Router#/Switch>), Keywords, Interface-Typen → blau/cyan
  - Log-Level: ERROR/CRITICAL→rot, WARN→orange, INFO→blau, SUCCESS→grün, DEBUG→cyan
  - Netzwerk: URLs→magenta+unterstrichen, bekannte Ports→magenta
  - Regelset-Verwaltung in Einstellungen → Syntax-Tab

- **Feature 10 — Themes / Professional Customizer**:
  - NexusTheme-Modell mit vollständigem ANSI-16-Farbpaletten-Support
  - 7 eingebaute Themes: Nexus Dark, Nexus Light, Solarized Dark, Monokai, Nord, Dracula, Cisco Green
  - Theme-Editor-Fenster: Terminal/UI/Schrift/Verhalten-Tabs mit ColorPickern
  - Live-Vorschau, Import/Export (.nexustheme-Dateien)

- **Feature 11 — Unit Tests** (37 Tests, alle bestanden):
  - SSHArgumentBuilderTests: basicArgs, legacyAlgorithms, jumpHost, portForwarding, socks5, combinedArgs
  - MacroTests: saveMacroAndReload, hotkey, schedule, codableRoundTrip
  - SFTPItemParserTests: parseLsLine, parseSymlink, parseHiddenFile, parseLsOutput, pathConstruction

### Behoben
- macOS App Crash beim Start in Test-Umgebung: MacroMenuItems verwendet nun @FocusedValue
  statt @Environment(AppViewModel.self) um EXC_BREAKPOINT in SwiftUI-Menü-Initialisierung zu verhindern
- ConnectionState: Equatable-Konformität ergänzt (benötigt für RDP-Statusvergleiche)

---

## [1.3.1] - 2026-05-29

### Verbessert
- Release-Workflow: `build_beta.sh` berechnet Version automatisch aus Issue-Labels
  - Bug-Issues (Label `bug-open`): PATCH-Bump (1.3.0 → 1.3.1)
  - Feature-Issues (Label `feature-request`): MINOR-Bump (1.3.0 → 1.4.0)
  - Basis: letzter stabiler Release via GitHub API — kein manuelles Eingeben der Version
- Release-Workflow: `promote_beta.sh` prüft Owner-Freigabe vor dem Promote
  - Nur der Repo-Owner (`matthiashollinger-netizen`) kann mit 👍 freigeben
  - Fremde Reaktionen werden ignoriert + Hinweis-Kommentar auf dem Issue
- `beta-appcast.xml` und `appcast.xml` werden via GitHub Contents API direkt auf `main` gepusht
  — funktioniert unabhängig vom aktuellen Git-Branch (z.B. während `fix/issue-*`)
- BUGFIX_WORKFLOW.md aktualisiert mit neuen Befehlen und Versions-Automatik-Tabelle

---

## [1.3.0] - 2026-05-28

### Neu
- In-App Bug Reporter: Bug melden direkt aus Nexus (Hilfe → Bug melden… / ⌘⇧B)
  - Schweregrad-Picker (Crash / Schwerwiegend / Mittel / Kosmetisch)
  - Automatische Erfassung: App-Version, macOS, Architektur, aktive Sessions, freier RAM, App-Logs
  - Optionaler Screenshot (kein Screen-Recording-Permission erforderlich)
  - Erstellt GitHub Issue direkt mit Label `bug-open`
- In-App Feature Request: Feature wünschen (Hilfe → Feature wünschen…)
  - Titel, Beschreibung, Warum-Begründung, Priorität-Picker
  - Erstellt GitHub Issue mit Label `feature-request`
- GitHub Project Board: Kanban-Board für Bug-Tracking (5 Spalten)
- GitHub Labels: bug-open, fix-pending, test-ready, verified, wont-fix, feature-request
- GitHub Actions Workflow: Auto-Kommentar und Label-Management bei neuen Issues
- Beta-Release Pipeline: build_beta.sh für Pre-Releases ohne Stable-Kanal-Update
- Promote-Pipeline: promote_beta.sh zum Promoten von Beta → Stable
- BUGFIX_WORKFLOW.md: vollständiger autonomer Fix-Workflow für Claude Code

---

## [1.2.0] - 2026-05-28

### Neu
- In-App-Hilfe: vollständige Dokumentation aller Features unter Hilfe → Nexus Hilfe (⌘?)
- Versionsverlauf-Fenster: Nexus öffnet den Changelog direkt in der App statt extern im Browser
- Beide Fenster vollständig zweisprachig (Deutsch / Englisch), strukturiert mit Icons und Abschnitten

---

## [1.1.0] - 2026-05-28

### Neu
- App-Icon: stylisches Nexus-Logo (dunkler Hintergrund, Netzwerkknoten, N-Lettermark)
- Stylisches DMG-Installationsfenster mit Logo, Pfeil und Drag-Anleitung
- GitHub-Repository öffentlich — appcast.xml via raw.githubusercontent.com erreichbar
- MARKETING_VERSION auf 1.0.0 korrigiert für korrekte Sparkle-Versionsprüfung
- Build-Script: Notarization-Support (NOTARIZE=1), Versionsnummern-Logik verbessert

### Behoben
- "Fehler beim Aktualisieren": appcast.xml war durch privates Repository nicht erreichbar
- Version 1.0 vs 1.0.0 Mismatch in Sparkle-Versionsprüfung behoben

---

All notable changes to Nexus are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-05-28

### Neu
- SSH-Verbindungen mit vollständigem Legacy-Algorithmus-Support (diffie-hellman-group14-sha1, ssh-rsa)
- Telnet-Sessions
- Serielle / COM-Verbindungen (konfigurierbare Baudrate, Datenbits, Parität, Flusssteuerung)
- Ordner-Hierarchie mit unbegrenzter Verschachtelung
- Browser-Tabs für mehrere gleichzeitige Sessions — frei verschiebbar per Drag
- Integrierter Password Manager (AES-256-GCM, verschlüsselt exportierbar/importierbar)
- Anmeldedaten per Credential-Gruppe an Sessions und Ordner vererbbar
- CSV-Import im Termius-Format mit grafischer Spalten-Zuordnung
- Reconnect-Overlay bei Verbindungsabbruch (R / ↩ oder Button)
- Known-Hosts vollständig umgangen (`StrictHostKeyChecking=no`, `UserKnownHostsFile=/dev/null`)
- Sidebar: Einzelklick wählt, Doppelklick verbindet — zuverlässig ohne Konflikte
- Dark / Light Mode automatisch per macOS-Systemeinstellung
- Deutsch / Englisch — Sprachumschaltung zur Laufzeit ohne Neustart
- Auto-Update via Sparkle (EdDSA-signierte DMGs, Silent Background Check)
