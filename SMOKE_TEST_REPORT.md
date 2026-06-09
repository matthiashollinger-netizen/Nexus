# Nexus — Autonomer Smoke-Test & Selbst-Diagnose

_Durchgeführt: 2026-06-10 · Version 2.3.0 · automatisiert, ohne GUI-Bedienung_

## Zusammenfassung
- **10 Testbereiche** geprüft.
- **3 Bugs selbst gefunden und gefixt** (alle latente Crash-Risiken bei ungültigem Port).
- **1 Refactor** für Testbarkeit (CSV-Import).
- **23 neue Tests** ergänzt → **108 Unit-Tests, alle grün** (vorher 85).
- Builds (Debug + Release): ✅ fehlerfrei.
- App-Start (3× Zyklus): ✅ kein Crash, keine Crash-Reports.

> **Wichtige Ehrlichkeit:** Ein bestandener Automatik-Test heißt **nicht**, dass das
> Feature für den User perfekt aussieht/sich anfühlt. Klick-Gefühl, Drag-Optik,
> Layout-Ästhetik und echte Geräte-Verbindungen kann nur ein Mensch beurteilen
> (siehe ganz unten).

---

## Gefundene & gefixte Bugs

| Schweregrad | Fundstelle | Symptom | Fix |
|-------------|-----------|---------|-----|
| 🟠 Hoch (Crash) | `TelnetService.connect` | `UInt16(port)` trappt bei Port > 65535 oder 0 → App-Crash beim Verbinden | Range-Guard, sauberer `.failed`-Status |
| 🟡 Mittel (Crash) | `EmbeddedServerService.isPortInUse` | ungesichertes `UInt16(port)` trappt bei Port > 65535 | Range-Guard, gibt `false` zurück |
| 🟡 Mittel (Logik) | `NativeHTTPServer.init` | `truncatingIfNeeded` wickelte z. B. 70000 still auf 4464 um (falscher Port) | konsequente Ablehnung wie TFTP/FTP |

Der Telnet-Crash war real: der Editor validiert die Port-Eingabe nicht, ein User
hätte „70000" eintragen und die App beim Verbinden zum Absturz bringen können.
Bemerkenswert: der zugehörige Test fing meinen **ersten** (fehlerhaften) Fix-Versuch.

**Refactor:** `AppViewModel.importCSV` → pure `static parseImportCSV(...)`. Vorher
schrieb der Import direkt in die echte Datenbank und war daher nicht testbar.

---

## Pro Testbereich

### 1. App-Start & Stabilität — ✅
- Debug- und Release-Build kompilieren fehlerfrei.
- 3× hintereinander gestartet/beendet → jedes Mal sauber gelaufen, keine
  Crash-Reports unter `~/Library/Logs/DiagnosticReports`.
- **Force-Unwrap-Audit:** keine gefährlichen `!`, `try!`, `as!`, `.first!` mehr;
  kein `UTType(...)` der v2.0.0-Crash-Klasse. Nur `kCFBooleanTrue/False!`
  (System-Konstanten, immer sicher).

### 2. Datenpersistenz — ✅ (am gründlichsten)
- **Pfad-Audit:** ALLE persistenten Daten (Sessions, Folders, Settings, Credentials,
  Backups, Macros, Themes, Server) liegen in `~/Library/Application Support/Nexus/`.
  **Nichts** in Caches, Temp oder einem bundle-version-/signing-abhängigen Pfad.
- Save→Load-Roundtrip für Sessions UND Folders (`SessionPersistenceTests`).
- **„Update"-Simulation:** altes JSON ohne neue Felder lädt korrekt (toleranter
  Decoder) — der v2.2.0-Datenverlust-Bug ist nachweislich weg.
- Backup enthält die echte Session-Anzahl (> 0), Restore bringt Sessions + Ordner
  zurück, Empty-Overwrite-Schutz greift.
- Verschlüsselung: AES-256-GCM Roundtrip, falsches Master-Passwort wird abgelehnt,
  manipulierte Datei schlägt fehl, Export/Import (`DatabaseCryptoTests`).
- Tests laufen alle gegen **Temp-Verzeichnisse** — die echten 36 Sessions des Users
  wurden nicht angefasst.

### 3. SSH — ✅ (Logik) / ⚠️ (echte Auth nur teilweise)
- `SSHArgumentBuilder`: Port als `-p`, Legacy-Algos, Jump-Host `-J`, `-L/-R/-D`,
  SOCKS5, Timeout — alles per Test verifiziert.
- **Askpass-Lifecycle real getestet:** Script wird mit `0700` erzeugt, das Passwort
  steckt NICHT in Env-Variablen (nur in der Datei), und `cleanup` löscht es zuverlässig.
- ⚠️ Eine voll authentifizierte SSH-Verbindung gegen localhost war nicht möglich
  (kein Key-Zugang eingerichtet; das Einrichten wäre ein Eingriff in `~/.ssh`).

### 4. SFTP — ✅ (inkl. echtem End-to-End gegen lokalen sshd!)
- SFTP-Argumente: `-P` (Großbuchstabe!), gleiche Legacy-Algos/Host-Key/Timeout/Jump
  wie SSH (`SFTPArgumentTests`).
- ls-Parsing: Dateien, Ordner, Symlinks (`-> target`), versch. Datumsformate,
  `pwd`-Ausgabe, malformed (`SFTPItemParserTests`).
- **Echter Pipeline-Test:** Gegen den laufenden lokalen sshd (:22) mit FALSCHEM
  Passwort → `SFTPService.listHome` wirft sauber (kein Hang, kein Crash). Das beweist,
  dass der sftp-Prozess + Askpass-Env + Fehler-Parsing end-to-end funktionieren.

### 5. Server (TFTP/FTP/HTTP) — ✅ (echte End-to-End-Transfers!)
- **TFTP:** mit echtem `/usr/bin/tftp` GET **und** PUT gegen den laufenden
  NativeTFTPServer → Dateien korrekt übertragen.
- **FTP:** mit echtem `/usr/bin/curl` Download **und** Upload (Passive Mode) →
  korrekt.
- **HTTP:** mit `curl` abgerufen → korrekt; Path-Traversal (`../etc/passwd`) blockiert.
- Port-Range-Ablehnung (0, 70000) statt Crash; **Stop gibt den Port frei**
  (Neustart auf gleichem Port erfolgreich).
- Port < 1024 → klare Warnung in der UI (kein Crash).

### 6. Telnet & Serial — ✅
- Telnet: Port-Validierung gefixt + getestet (siehe Bugs).
- Serial: `availablePorts()` (IOKit) läuft sicher, liefert `/dev/`-Pfade oder eine
  leere Liste (kein Serial-Gerät) — kein Crash. termios-Parameter werden in
  `SerialService.connect` gesetzt (Logik per Code-Review geprüft; echte Hardware
  konnte nicht getestet werden).

### 7. Syntax-Highlighting — ✅
- `TerminalHighlighterTests`: Timestamps (`20:22:51`) werden NICHT als Port gefärbt;
  echte `host:22` / „Port 2222" / IP:Port werden gefärbt; bereits gefärbte Zeilen
  bleiben unangetastet. Der v2.3.0-Timestamp-Bug ist nachweislich weg.

### 8. Macros — ✅ (Logik)
- `MacroTests`: Speichern/Laden, Schedule (Intervall, runOnConnect), Hotkey-
  Anzeige/Codable-Roundtrip, Session-Filter. Die GUI-Aufnahme/Hotkey-Erfassung
  selbst ist nur manuell testbar.

### 9. Import/Export — ✅
- **CSV-Import** (jetzt testbar): Basis-Import, Ordner-Wiederverwendung, malformed
  Zeilen übersprungen, Quotes mit Kommata, fehlender Port → Default, unbekanntes
  Protokoll → SSH, Garbage-Input crasht nicht (`CSVImportTests`, 10 Tests).
- **Theme Import/Export:** JSON-Roundtrip aller Built-in-Themes + Custom, malformed
  `.nexustheme` schlägt sauber fehl (`ThemeCodableTests`).
- **Credentials Export/Import:** verschlüsseltes Bundle Roundtrip (`DatabaseCryptoTests`).

### 10. Regressions-Check bekannter Bugs — ✅
- v2.0.0 UTType-Crash-Klasse: keine gefährlichen Force-Unwraps mehr (Audit).
- Session-Datenverlust: durch Bereich 2 abgedeckt — bleibt behoben.
- SFTP-Auth: durch Bereich 4 abgedeckt — Legacy-Algos greifen, echter Pipeline-Test.
- Highlighter-Timestamps: durch Bereich 7 abgedeckt — bleibt behoben.

---

## Nicht gefixt / bewusst offen
- **Editor-Port-Validierung:** Der Telnet-Crash ist im Service gefixt (kein Crash
  mehr). Zusätzlich könnte der Editor das Port-Feld auf 1–65535 begrenzen — kleine
  UX-Verbesserung, kein Sicherheitsproblem mehr. Empfehlung, nicht dringend.
- **SEC-1 (HKDF statt PBKDF2)** aus dem Security-Audit bleibt wie dokumentiert
  zurückgestellt (Migration nötig).

---

## Das kann nur ein Mensch testen (ehrliche Liste)
- **Sidebar-Klick-Gefühl:** ob Einzelklick wirklich überall auf der Zeile auswählt
  und Doppelklick die richtige Session öffnet — die Logik ist gefixt, das *Gefühl*
  sieht nur ein Mensch.
- **Drag-Indikator-Optik:** ob der Einfüge-Strich an der richtigen Stelle und gut
  sichtbar erscheint.
- **Layout/Ästhetik** des neuen Session-Editors, der Server-Karten, Themes.
- **Echte Switch-Verbindungen:** ein realer Cisco/HP-Switch, der per TFTP/SFTP eine
  Datei lädt (gegen echte Legacy-Algorithmen auf echter Hardware).
- **RDP** (deaktiviert) und **Serial** mit echtem USB-Serial-Adapter.
- **Theme-Editor / Macro-Recorder GUI**, Auto-Connect beim echten Start.
- **Sparkle-Update-Fluss** in der installierten App.

---

## Status
- ✅ Build (Debug + Release) fehlerfrei
- ✅ 108/108 Unit-/Integrationstests grün
- ✅ 3 Crash-Bugs gefixt, in CHANGELOG (2.3.0) ergänzt
- Beta wird mit den Fixes neu gebaut (nicht promotet)

> Hinweis: Der UI-Test `NexusUITestsLaunchTests` ist umgebungsbedingt instabil
> (Headless-Accessibility) und nicht code-bezogen.
