# Changelog

---

## [2.0.0] - 2026-05-29

### Neu

- **SFTP-Browser**: Integrierter SFTP-Dateimanager (280pt Seitenleiste)
  - Toggle-Button in der Toolbar — sichtbar wenn SSH-Session aktiv
  - Breadcrumb-Navigation, Upload/Download, Umbenennen, Löschen, Neuer Ordner
  - Progress-Overlay bei Transfers, Hidden-Files-Toggle

- **Eingebauter Texteditor**:
  - Syntax-Highlighting für Swift, Python, Bash, JSON, YAML, XML/HTML
  - Zeilennummern, ⌘F/⌘H Suchen & Ersetzen, Encoding-Wahl

- **Makros + Hotkeys + Zeitplanung**:
  - Makro-Manager mit Hotkey-Recorder und Zeitplanung
  - Globale Tastenkürzel, "Bei Verbindung ausführen"-Option

- **Eingebettete Server**: HTTP, FTP, TFTP — direkt aus Nexus starten

- **RDP via FreeRDP**: Vollständige RDP-Integration (benötigt brew install freerdp)

- **Erweitertes Syntax-Highlighting**:
  - Cisco IOS, Log-Level, Netzwerk-URLs/Ports
  - Regelset-Verwaltung in Einstellungen

- **Themes / Professional Customizer**:
  - 7 eingebaute Themes: Nexus Dark, Nexus Light, Solarized Dark, Monokai, Nord, Dracula, Cisco Green
  - Eigener Theme-Editor mit ColorPickern und Live-Vorschau

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
