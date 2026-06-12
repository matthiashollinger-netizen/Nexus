# Changelog

---

## [3.0.1] - 2026-06-12

### Behoben — KRITISCH (Terminal)

- **ncurses-Programme (nano, vim, top, htop, less) brachen über SSH mit
  „Error opening terminal: unknown" ab.** Ursache: eine GUI-App besitzt keine
  `TERM`-Umgebungsvariable, also übergab Nexus dem Remote-PTY `TERM=unknown` —
  ncurses findet dafür keine Terminal-Beschreibung. Fix: SSH-Sitzungen setzen
  jetzt `TERM=xterm-256color` und `COLORTERM=truecolor` (SwiftTerm ist
  xterm-256color-kompatibel). An echter Hardware verifiziert: `nano` öffnet korrekt.

---

## [3.0.0] - 2026-06-12

### Neu — Großes UI-Rework

- **Design-System (DS):** ein einheitliches Token-System für Abstände, Radien,
  Typografie und semantische Farben ersetzt die zuvor 8 verschiedenen Eckenradien,
  ~149 Ad-hoc-Schriftgrößen und verstreuten, hartkodierten Farben. Die ganze App
  wirkt jetzt wie ein zusammenhängendes, natives macOS-Werkzeug. Neue
  wiederverwendbare Bausteine: StatusDot, StateBadge, NexusCard, EmptyState,
  SectionHeader, KeyHint, MonoText, IconBadge, QuickActionTile.
- **Dashboard / Start-Bildschirm:** ersetzt den faden „Willkommen"-Platzhalter durch
  einen echten Launchpad — zeitabhängige Begrüßung, Schnell-Verbinden-Leiste (⌘K),
  Schnellaktionen, Statistik (Sessions/Ordner/aktive Server), zuletzt verwendete und
  favorisierte Verbindungen sowie Live-Status der eingebetteten Server.
- **Befehlspalette (⌘K):** Spotlight-artige Fuzzy-Suche über Sessions, offene Tabs,
  Ordner und Aktionen. Drei Buchstaben, ⏎ — verbunden, ganz ohne Maus. Volle
  Tastatur-Navigation (↑/↓/⏎/esc, ⌥⏎ = verbinden & offen lassen), Live-Hervorhebung
  der Treffer.
- **Status-auf-einen-Blick-Seitenleiste:** jede aktive Session zeigt einen
  farbcodierten, „atmenden" Status-Punkt (farbenblind-sicher: Farbe + Symbol). Beim
  Überfahren erscheinen Verbinden/Bearbeiten direkt in der Zeile; eine leere
  Seitenleiste lädt jetzt mit einem klaren Erst-Schritt ein.
- **Favoriten:** Sessions mit Stern markieren; eigener Bereich im Dashboard.
- **Snippets:** wiederverwendbare Befehle pro Session (z. B. „show running-config"),
  per Menü mit einem Klick in das laufende Terminal gesendet (SSH/Telnet/Serial).
- **Mitteilungen:** native macOS-Benachrichtigung, wenn eine Verbindung unerwartet
  abbricht (abschaltbar; reguläres Schließen löst keine Mitteilung aus).
- **nexus:// Deep-Links:** `nexus://open/<id>` und `nexus://connect?host=…&type=ssh`
  öffnen/verbinden eine Session aus Browser, Wiki oder Chat.

### Neu — MobaXterm-Features & Server-Hosting

- **Syslog-Server:** nativer UDP-Empfänger (RFC 3164 + 5424) im Server-Manager —
  Switch-Logs live mitlesen (farbcodierte Severity, Freitext-Filter, Alarm-Zähler,
  CSV-Export). Der wichtigste fehlende Server fürs Firmware-Update.
- **Netzwerk-Toolbox:** Ping, Traceroute, DNS, Port-Check und Wake-on-LAN (eigenes
  Fenster, ⌘K + Werkzeuge-Menü) — alles über macOS-Systemtools, keine Installation.
- **MultiExec:** denselben Befehl an mehrere Terminals gleichzeitig senden
  (Tab-Auswahl per Checkbox + Broadcast-Leiste).
- **Find-in-Terminal (⌘F).**
- **SFTP-Browser:** Drag-&-Drop-Upload direkt aus dem Finder.
- **Server-Manager** komplett auf das neue Design-System umgestellt (Status-Punkte,
  „Im Finder zeigen").

### Behoben — SFTP (durch Live-Test an echter Hardware gefunden)

- **SFTP-Browser-Authentifizierung:** schlug bei passwortbasierten Hosts immer fehl
  („Authentication failed"), obwohl dasselbe gespeicherte Passwort im SSH-Terminal
  funktionierte. Ursache: `sftp` lief im Batch-Modus (`-b`), der ssh `BatchMode=yes`
  erzwingt und damit die Passwort-Auth (SSH_ASKPASS) komplett abschaltet — nur das
  Terminal maskierte es, weil es das Passwort als Fallback *tippt*. Behoben (Kommandos
  über stdin statt `-b`), gegen ein echtes Gerät verifiziert.
- **Unterordner** zeigten volle Pfade statt Dateinamen — behoben (Basename).
- Verbindungsabbrüche bzw. ssh-Exit-Code 255 werden jetzt sauber als Fehler
  angezeigt statt als (leeres) Listing.

### Behoben

- **Makros auf SSH-Sessions:** SSH hatte zuvor keinen Sende-Kanal, sodass Makros
  SSH-Terminals nie erreichten — jetzt einheitlich für SSH/Telnet/Serial verkabelt
  (dieselbe Mechanik trägt auch die neuen Snippets).
- Tab-Status nutzt jetzt den gemeinsamen Status-Punkt statt der „…/✕"-Emoji-Suffixe;
  Tab-Schließen-Button mit Hover-Hervorhebung.
- Reconnect-Overlay nutzt System-Material statt hartem Schwarz, respektiert
  Hell/Dunkel und bietet „Schließen" (esc) neben „Neu verbinden" (⏎).

### Technisch

- Neue Modellfelder (`isFavorite`, `snippets`, `recentSessionIds`, …) verwenden
  dieselben toleranten Decoder wie v2.3 — alte Daten laden unverändert, kein
  Datenverlust.
- Tastenkürzel ⌘K (Palette) kollidiert nicht mit ⌘⇧K (Passwort-Manager).
- Alle neuen Strings vollständig zweisprachig (de + en).

### Bewusst offen / nicht machbar

- **RDP:** weiterhin nicht einbettbar (keine native Bibliothek; FreeRDP bräuchte
  XQuartz/Homebrew → widerspricht dem self-contained-Ziel).
- **SFTP-/Telnet-Server:** bräuchten einen vollständigen SSH-Server bzw. würden eine
  unauthentifizierte Shell exponieren — bewusst nicht ausgeliefert (TFTP/FTP decken
  Geräte-Uploads ab).
- Voller Token-Sweep über die restlichen Fenster (Einstellungen, Server-Manager,
  Hilfe, Onboarding) folgt als separater Schritt; die zentralen Flächen (Seitenleiste,
  Tabs, Dashboard, Palette) sind bereits umgestellt.

---

## [2.3.0] - 2026-06-09

### Behoben — KRITISCH (Datenverlust)
- **Sessions verschwanden bei einem Versions-Update** und Backups zeigten „0 Sessions".
  Ursache: Swifts synthetisiertes Codable verlangte jeden neuen Pflicht-Schlüssel im
  alten `sessions.json` — fehlte einer, schlug das Laden ALLER Sessions fehl (Ordner
  blieben, da unverändert). Fix: tolerante Decoder für Session/Folder/Settings, die
  fehlende Schlüssel mit Defaults auffüllen → nie wieder Verlust bei Schema-Änderungen.
  Zusätzliche Schutznetze: beschädigte Dateien werden bewahrt statt überschrieben,
  und eine nicht-leere Sessions-Datei wird nie kommentarlos durch eine leere ersetzt.

### Behoben
- **SFTP „Authentication failed"**: SFTP wendet jetzt dieselben Legacy-Algorithmen,
  Host-Key-, Timeout- und Jump-Host-Einstellungen an wie die SSH-Session (gemeinsamer
  Code) — verbindet sich damit zu denselben (alten) Switches.
- **Konfigurierter Port**: SFTP nutzt korrekt `-P` (Großbuchstabe), SSH `-p` — der
  in der Session gesetzte Port (z. B. 2222) wird zuverlässig verwendet.
- **Sidebar Einzel-/Doppelklick (3× zurückgekehrt — jetzt dauerhaft)**: ganze Zeile
  per Einzelklick auswählbar; Doppelklick öffnet immer das angeklickte Item (nicht
  mehr das zuvor ausgewählte). Begründung in NOTES.md dokumentiert.
- **Sidebar-Drag**: sichtbarer Einfüge-Strich (Akzentfarbe) zeigt die genaue
  Zielposition; Ordner werden beim Hineinziehen hervorgehoben.
- Session-Editor: überflüssige Platzhalter-Texte rechts neben Host/Benutzername/Name
  entfernt.
- **Crash-Härtung (autonomer Smoke-Test)**: ungültige Portnummern (> 65535 oder 0)
  führten bei Telnet-Verbindungen und der Server-Port-Prüfung zu einem Absturz; der
  native HTTP-Server wickelte zu große Ports still um. Alle drei Stellen lehnen
  ungültige Ports jetzt sauber ab. 23 zusätzliche automatische Tests (CSV-Import,
  Telnet/Serial/Askpass-Robustheit, Theme-Roundtrip, Server-Edge-Cases, echter
  SFTP-Auth-Pipeline-Test).

### Neu
- **Echte eingebettete Server** im Server-Manager (Mac = Server, Switch = Client):
  - **TFTP-Server** nativ (der Cisco/HP-Standard), Up- und Download, Default-Port 6969.
  - **FTP-Server** nativ (Passive Mode), Up- und Download, Default-Port 2121.
  - HTTP weiterhin nativ. Bei laufendem Server wird die erreichbare Adresse angezeigt
    (z. B. `tftp://192.168.x.x:6969`).
  - SFTP-/Telnet-Server deaktiviert mit ehrlicher Begründung.

---

## [2.2.0] - 2026-06-02

### Neu
- **Session-Editor komplett neu (MobaXterm-Stil)**: oben eine horizontale Leiste
  großer Protokoll-Icons (SSH / Telnet / Serial), darunter prominente Basis-
  Einstellungen und einzeln aufklappbare Advanced-Bereiche (Verbindung & Sicherheit,
  Gateway & Tunneling, Serielle Parameter, Terminal & Darstellung, Verhalten).
  Live-Validierung, aufgeräumter Erstkontakt.
- **Per-Session-Optionen**: eigenes Theme, Schriftgröße, Syntax-Regelset,
  „Macro bei Verbindung ausführen" und „beim Start automatisch verbinden".
- **Server-Manager** als eigener Menüpunkt (Werkzeuge → Server-Manager, ⌘⌥⇧S):
  eine Karte pro Server-Typ. HTTP (nativ) und TFTP (System) startbar; SFTP über
  macOS-Remoteanmeldung; FTP/Telnet bewusst deaktiviert mit Begründung.

### Behoben
- **SFTP-Browser zeigte keine Dateien**: beim Verbinden wird jetzt das Home-
  Verzeichnis gelistet (statt „/"), leere Ordner und Listing-Fehler sind sichtbar.
- **Einzelklick in der Sidebar** funktioniert wieder auf der ganzen Zeile inkl.
  Text (nicht nur daneben).
- **Sidebar-Drag** fühlt sich wie Verschieben an (Move-Cursor, kein „+"-Kopier-
  Badge mehr).
- **Syntax-Highlighting** färbt Zahlen in Uhrzeiten (z. B. `20:22:51`) nicht mehr
  fälschlich als Ports — Ports nur noch im Kontext (IP:Port, Host:Port, „Port N").

---

## [2.1.0] - 2026-06-02

### Verbessert
- **Kein Keychain-Popup mehr** beim Aufbau von SSH-Verbindungen — Passwort-Übergabe
  läuft jetzt keychain-frei über ein kurzlebiges, sofort gelöschtes Temp-Script.
- **Self-Contained**: Der eingebaute HTTP-Server läuft jetzt **nativ** (kein `python3`
  mehr nötig — das fehlt auf frischem macOS). SSH/SFTP/Telnet/Serial brauchen keinerlei
  Zusatzinstallation.
- **Übersichtlicherer Session-Editor**: Gateway/Tunneling-Optionen (Jump Host, Port
  Forwarding, SOCKS5) in einer aufklappbaren, standardmäßig eingeklappten Gruppe.
- Freundlichere, zweisprachige Fehlermeldungen bei Verbindungs- und Serial-Problemen
  (statt technischem Error-Dump).

### Neu
- **Automatische Backups**: Nexus sichert Sessions/Ordner beim Start und vor Änderungen
  (rollierend, neueste 15). Verwaltung unter Einstellungen → Sicherheit → Backups
  verwalten (Wiederherstellen / Löschen / Jetzt sichern).

### Behoben
- Crash-Härtung: alle gefährlichen Force-Unwraps (UTType/URL/UUID) entfernt —
  insbesondere die Klasse, die v2.0.0 zum Absturz brachte.
- Verwaiste temporäre Key-/Askpass-Dateien werden beim App-Start aufgeräumt.

### Deaktiviert (bewusst, dokumentiert)
- **RDP**: keine native einbettbare Engine verfügbar, FreeRDP benötigt XQuartz —
  als Protokoll vorerst deaktiviert (FreeRDP-Code entfernt). Folgt in einer
  kommenden Version.
- **FTP-Server**: benötigt eine externe Bibliothek — vorerst deaktiviert. HTTP läuft
  nativ, TFTP nutzt das macOS-System-Binary.

### Sicherheit
- Security-Audit durchgeführt (siehe SECURITY_AUDIT.md): keine kritischen/hohen
  aktiven Schwachstellen. Krypto-Tests (AES-256-GCM) ergänzt.

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
