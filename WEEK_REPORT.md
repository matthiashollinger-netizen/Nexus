# Nexus — Week Hardening Report

_Begonnen: 2026-05-29 · Basis-Tag: `stable-pre-week` · Ziel-Version: 2.1.0_

> **Sicherheitsanker:** Der Git-Tag `stable-pre-week` markiert den Stand vor diesem
> Durchgang. Rückkehr jederzeit möglich mit `git reset --hard stable-pre-week`.

---

## ⚠️ AUFGABE 1 — GATE-ENTSCHEIDUNG: SSH-Umbau GESTOPPT (bewusst)

**Ergebnis des Gates: Die native Swift-SSH-Bibliothek wird NICHT integriert.
Die funktionierende `/usr/bin/ssh`-Lösung bleibt erhalten.**

### Begründung
Die Kern-Daseinsberechtigung von Nexus ist die Verbindung zu **Legacy-Netzwerk-
Switches** (Cisco IOS, HP/Aruba Comware), die ausschließlich veraltete Algorithmen
anbieten:
- `diffie-hellman-group14-sha1` (Key Exchange)
- `ssh-rsa` (Host-Key / SHA-1-Signaturen)

**Citadel** und die darunterliegende Apple-Bibliothek **swift-nio-ssh** unterstützen
diese SHA-1-basierten Algorithmen **prinzipiell nicht** — Apple hat sie als unsicher
bewusst weggelassen, und es gibt **keinen Konfigurationsschalter**, um sie zu
reaktivieren. Citadel erbt diese Einschränkung direkt.

Ein Umbau auf Citadel würde also genau die Geräte unerreichbar machen, für die
Nexus gebaut wurde. Das ist exakt der Fall, den die Gate-Regel abfangen sollte.

### Konsequenz
- `/usr/bin/ssh` bleibt der SSH-Transport (unterstützt Legacy-Algorithmen via `-o`)
- Citadel wird **nicht** als Abhängigkeit aufgenommen
- Es wurde **nicht** auf einer kaputten SSH-Basis weitergebaut

### Aber: die echten Schmerzpunkte hinter Aufgabe 1 werden trotzdem gelöst
Die Gründe, warum der User den Umbau wollte, lassen sich ohne Citadel beheben:

| Schmerzpunkt | Status |
|--------------|--------|
| `sshpass`-Abhängigkeit | ✅ Bereits entfernt — kein Vorkommen mehr im Code |
| SFTP „keine Verbindung" | ✅ In v2.0.2 behoben (force-askpass, Host-Parsing, Temp-Script) |
| Keychain-Popup bei jeder SSH-Verbindung | ✅ Behoben in diesem Durchgang (siehe unten) |

Damit ist das eigentliche Ziel (keine externen Tools für SSH/SFTP, keine
Keychain-Popups) erreicht — nur eben mit `/usr/bin/ssh` als bewährtem Transport
statt einer Bibliothek, die die Kern-Hardware nicht bedienen kann.

---

## Durchgeführte Änderungen

_(wird fortlaufend ergänzt)_

### Aufgabe 1-Folge: Keychain-Popup bei SSH-Verbindung entfernt
- `NexusSSHTerminalView.startSSH()` injiziert das Passwort jetzt über ein
  temporäres Askpass-Script (wie SFTP), statt es im Keychain abzulegen.
- Der Keychain-basierte Pfad in `NexusAskPassService` entfällt → **kein
  Sicherheits-Popup** mehr beim Verbinden.
- Das Temp-Script wird mit `0700` geschrieben und nach Prozess-Ende garantiert
  gelöscht (auch im Fehlerfall).
- Ungenutztes Bundle-Script `Resources/nexus-askpass` entfernt.

### Aufgabe 6: Automatische Backups (Datenverlust-Schutz)
- `DatabaseService.createBackup()` — Backup-Bundle (sessions/folders/settings +
  verschlüsselter Credentials-Blob als base64) als `backup_<timestamp>_<id>.json`.
- **Backup beim App-Start** (force) + **throttled vor jedem Speichern** (max. 1×
  pro 5 min, damit häufige Saves den Ring nicht zumüllen).
- **Rolling Window**: neueste 15 Backups, ältere werden automatisch gelöscht.
- **Atomares Speichern** war bereits aktiv (`.atomic` = temp-Datei + Rename) →
  keine korrupten Dateien bei Crash während des Schreibens.
- **Eindeutiger Datei-Suffix** verhindert Kollision zweier Backups in derselben
  Sekunde (sonst stiller Verlust).
- UI: **Einstellungen → Sicherheit → Backups verwalten** — Liste mit Datum,
  Session-Anzahl, Größe; Wiederherstellen (mit Bestätigung), Löschen, „Jetzt
  Backup erstellen". Vor jeder Wiederherstellung wird der aktuelle Stand gesichert.
- `DatabaseService.init(rootDirectory:)` für hermetische Tests injizierbar.
- Tests: `BackupTests` (Bundle-Round-Trip, Create/List/Restore, Empty-Skip,
  Max-Konstante).

### Aufgabe 5: Crash-Prävention (nil-Safety)
Gesamte Codebase nach gefährlichen Force-Unwraps durchsucht und abgesichert:
- `UTType(filenameExtension: "nexustheme")!` in ThemeEditorView → `if let` mit
  Fallback (**exakt die Crash-Klasse von v2.0.0**).
- 8× `UUID(uuidString: "…")!` (Theme-IDs) → `?? UUID()` (crash-proof; valide
  Literale verhalten sich identisch).
- 6× `FileManager…urls(for:…).first!` (App-Support/Downloads) → `?? Fallback-Pfad`.
- `try!` in `TerminalHighlighter.re()` → optionale Kette ohne Force-Try.
- Keine `as!`-Force-Casts und keine ungeprüften Array-Zugriffe gefunden.

### Aufgabe 10: Security Audit → siehe SECURITY_AUDIT.md
Keine kritischen/hohen aktiven Schwachstellen. Highlights:
- ✅ Keine hardcodierten Secrets, kein Passwort-Logging, kein UserDefaults für Secrets.
- ✅ Prozess-Aufrufe durchgängig mit Argument-Arrays (kein Shell-Injection).
- ✅ AES-256-GCM korrekt (CryptoKit, Random-Nonce, 32-Byte-Salt), Keychain
  `WhenUnlocked`, Sparkle EdDSA aktiv.
- 🟡 SEC-1: HKDF statt Passwort-KDF — Empfehlung PBKDF2 (Migration nötig, bewusst
  zurückgestellt um keine Daten zu zerstören).
- ⚪ SEC-2: `StrictHostKeyChecking=no` — akzeptiertes Risiko für Legacy-Switches,
  **pro Session abschaltbar** (Toggle vorhanden).
- 🔵 SEC-6: Verwaiste Temp-Key/Askpass-Dateien werden jetzt beim App-Start
  aufgeräumt (Crash-Resilienz).

---

### Aufgabe 3: Self-Contained App (keine externen Abhängigkeiten)

**Kern-Ziel erreicht:** SSH, SFTP, Telnet und Serial laufen vollständig ohne jede
Zusatzinstallation (System-`/usr/bin/ssh`, `/usr/bin/sftp`, Network.framework, IOKit).

| Abhängigkeit | Vorher | Jetzt |
|--------------|--------|-------|
| `sshpass` | — | ✅ War nie eingebunden |
| `/usr/bin/sftp` | System-Binary | ✅ Bleibt (ships mit macOS, kein Install) |
| **HTTP-Server** (`python3 -m http.server`) | ⚠️ python3 fehlt auf frischem macOS! | ✅ **Native Swift-Implementierung** (`NativeHTTPServer`, Network.framework) |
| **FTP-Server** (`pyftpdlib`) | ⚠️ pip-Install nötig | 🚫 **Deaktiviert** (ausgegraut, „folgt") |
| **TFTP-Server** (`/usr/libexec/tftpd`) | System-Binary | ✅ Bleibt (ships mit macOS; Port 69 braucht root — Warnung vorhanden) |

**Native HTTP-Server** (`NativeHTTPServer.swift`):
- GET/HEAD, statisches File-Serving, Directory-Listing, `index.html`
- **Path-Traversal-Schutz** (kein Ausbruch aus dem Root-Verzeichnis) — getestet
- MIME-Type-Erkennung, korrekte HTTP/1.1-Header
- Tests: `NativeHTTPServerTests` (Port-Validierung, End-to-End-Serving, Traversal-Block)

### Aufgabe 4: RDP — ehrliche Evaluierung → **deaktiviert**

**Recherche-Ergebnis:** Es existiert **keine** brauchbare native, einbettbare
Swift/Objective-C RDP-Bibliothek. Die einzige realistische Option (FreeRDP) benötigt
**XQuartz/X11 + Homebrew** — das widerspricht dem Self-Contained-Ziel fundamental.
Eine eigene RDP-Implementierung (Protokoll-Stack, Grafik, Input) wäre ein
**Monats-Projekt**, kein Wochen-Task.

**Entscheidung (gemäß Vorgabe „lieber sauber deaktivieren"):**
- `ConnectionType.rdp.isAvailable = false` → RDP **nicht mehr als Session-Typ wählbar**
  (aus dem Protokoll-Picker gefiltert).
- Der gesamte **FreeRDP-Code wurde entfernt** (kein `xfreerdp`-Aufruf, keine
  XQuartz-Abhängigkeit mehr im Release).
- Bestehende RDP-Sessions (falls vorhanden) zeigen einen klaren Hinweis
  „RDP folgt in einer kommenden Version" statt einen Prozess zu starten.

**Empfohlener Weg für später:** Eigene RDP-Engine auf Basis eines reinen
Swift-Netzwerk-Stacks (NWConnection) mit Anbindung an eine plattform-native
Rendering-Fläche — substanzielles eigenes Projekt, separat zu planen.

---

## Bewusst zurückgestellt / deaktiviert

| Punkt | Grund | Empfehlung |
|-------|-------|-----------|
| **RDP** | Keine native einbettbare Lib; FreeRDP braucht XQuartz | Eigene Engine, separates Projekt |
| **FTP-Server** | `pyftpdlib` ist kein System-Binary (pip-Install) | Nativer FTP-Server (Control+Data-Channel) als eigenes Feature |
| **SEC-1: HKDF → PBKDF2** | Format-Migration nötig, Daten-Verlust-Risiko mitten in der Woche | Versioniertes Format + transparente Migration beim nächsten Save |
| **Aufgabe 2: Session-Editor-Redesign (MobaXterm-Stil)** | Großer UI-Umbau; Priorität lag auf Stabilität/Sicherheit/Self-Contained | Siehe unten |

---

## Was der User nächste Woche zuerst testen sollte

_(wird am Ende finalisiert)_
