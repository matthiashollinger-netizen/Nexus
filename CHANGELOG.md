# Changelog

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
