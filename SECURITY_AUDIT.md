# Nexus — Security Audit

_Durchgeführt: 2026-06-02 · Version 2.1.0 · Scope: aktueller Code-Stand (keine Git-History)_

Schweregrade: 🔴 Kritisch · 🟠 Hoch · 🟡 Mittel · 🔵 Niedrig · ⚪ Informativ / Akzeptiert

---

## Zusammenfassung

Es wurden **keine kritischen oder hohen aktiven Schwachstellen** im Code gefunden.
Die Krypto basiert vollständig auf CryptoKit (keine Eigenbau-Krypto), Prozess-
Aufrufe verwenden durchgängig Argument-Arrays (kein Shell-Injection-Vektor), und
es gibt keine hardcodierten Secrets, kein Passwort-Logging und keine Speicherung
von Secrets in UserDefaults.

Zwei Punkte sind **bewusst akzeptierte Risiken** (für den Legacy-Switch-Use-Case
nötig) und ein Punkt ist eine **Härtungs-Empfehlung** für später (Migration nötig).

---

## Findings

### 🟡 SEC-1 — Schlüsselableitung nutzt HKDF statt eines Passwort-KDF
**Fundstelle:** `DatabaseService.deriveKey(password:salt:)`
**Beobachtung:** Der AES-256-GCM-Schlüssel für `credentials.enc` wird via
`HKDF<SHA256>` aus dem Master-Passwort abgeleitet. HKDF ist für **hochentropische**
Eingaben (z.B. zufällige Keys) konzipiert und hat **keinen Work-Factor**. Bei einem
schwachen Master-Passwort ist Brute-Forcing damit deutlich billiger als mit einem
dedizierten Passwort-KDF.
**Risiko:** Mittel — greift nur, wenn ein Angreifer bereits die verschlüsselte Datei
besitzt UND das Master-Passwort schwach ist.
**Empfehlung:** Auf **PBKDF2-SHA256 (≥ 210.000 Iterationen)** oder scrypt/Argon2id
umstellen. **Bewusst nicht in diesem Durchgang umgesetzt**, weil es das Dateiformat
ändert und eine Migration bestehender `credentials.enc`-Dateien erfordert — das wäre
ein Daten-Verlust-Risiko mitten in der Woche. Empfohlener Weg: Format-Version-Byte
voranstellen, beim Laden alte (HKDF) und neue (PBKDF2) Dateien erkennen, beim
nächsten Speichern transparent auf PBKDF2 migrieren.
**Status:** Dokumentiert, Migration für ein eigenes Release vorgesehen.

### ⚪ SEC-2 — `StrictHostKeyChecking=no` (known_hosts-Bypass) — akzeptiertes Risiko
**Fundstelle:** `SSHArgumentBuilder.build()` (`-o StrictHostKeyChecking=no`,
`-o UserKnownHostsFile=/dev/null`)
**Beobachtung:** Standardmäßig wird die Host-Key-Prüfung umgangen. Das öffnet
theoretisch ein **MITM-Fenster**.
**Warum akzeptiert:** Nexus ist primär für **Lab-/Legacy-Netzwerk-Equipment**
gebaut, bei dem mehrere Geräte dieselbe IP teilen (Konsolen-Server, frisch
geflashte Switches) und sich Host-Keys ständig ändern. Strikte Prüfung würde den
Kern-Workflow unbrauchbar machen.
**Mitigation bereits vorhanden:** Das Verhalten ist **pro Session abschaltbar** —
`Session.sshStrictHostKeyChecking` (Toggle in der Session-Bearbeitung,
„Strikte Host-Key-Prüfung"). Für sicherheitskritische Verbindungen kann der User
die Prüfung also aktivieren.
**Empfehlung für später:** Den Default für **neu angelegte** Sessions optional auf
„an" stellen und beim ersten Verbindungsaufbau einen TOFU-Dialog
(Trust-On-First-Use) anbieten. Aktuell bewusst „aus" als sinnvoller Default für
die Zielhardware.
**Status:** Akzeptiertes Risiko, dokumentiert, pro Session umstellbar.

### 🔵 SEC-3 — Passwort temporär in Askpass-Script (0600)
**Fundstelle:** `NexusAskPassService.prepare()`, `SFTPService.createAskPassScript()`
**Beobachtung:** Zur Passwort-Übergabe an `/usr/bin/ssh` / `/usr/bin/sftp` wird ein
kurzlebiges Shell-Script geschrieben, das das Passwort via `printf`/`echo` ausgibt.
**Risiko:** Niedrig — die Datei liegt im User-eigenen Temp-Verzeichnis.
**Mitigation:** Datei wird mit **0700/0600** angelegt und **unmittelbar nach
Prozess-Ende gelöscht** (lock-geschützte Map bzw. `terminationHandler`). Das Passwort
landet **nicht** in der Prozess-Argumentliste (wäre via `ps` sichtbar) — das war der
Grund, diesen Weg statt `-p`/Klartext-Arg zu wählen.
**Bewertung:** Bewusster Trade-off, der das frühere Keychain-Popup ersetzt (siehe
WEEK_REPORT.md, Aufgabe 1). Akzeptabel.

### 🔵 SEC-4 — Passwort-Escaping im Askpass-Script
**Fundstelle:** `NexusAskPassService.prepare()`, `SFTPService.createAskPassScript()`
**Beobachtung:** Das Passwort wird in einen doppelt-gequoteten Shell-String
eingebettet; escaped werden `\`, `"`, `$`, Backtick.
**Risiko:** Niedrig — eine unvollständige Maskierung könnte zu Shell-Injection führen,
**aber nur mit dem eigenen Passwort des Users** (kein fremd-kontrollierter Input).
Self-Injection ist kein praktisch relevanter Angriff.
**Empfehlung (optional):** Mittelfristig das Passwort über einen FIFO/Pipe statt über
ein Script-Echo übergeben, dann entfällt jede String-Maskierung.
**Status:** Niedrig, dokumentiert.

### ⚪ SEC-5 — Kein App-Sandbox, kein Entitlements-File
**Fundstelle:** Build-Settings (`ENABLE_APP_SANDBOX = NO`,
`ENABLE_HARDENED_RUNTIME = YES`), kein `.entitlements`.
**Beobachtung:** Die App läuft **ohne Sandbox**.
**Warum akzeptiert:** Als Entwickler-/Netzwerk-Tool braucht Nexus unbeschränkten
Zugriff (Serial/IOKit, beliebige Netzwerkziele, PTY-Erzeugung). Das ist in NOTES.md
als bewusste Architektur-Entscheidung dokumentiert. **Hardened Runtime ist aktiv**,
was die wichtigste Härtung (Code-Injection-Schutz) liefert.
**Status:** Akzeptiert, dokumentiert.

---

## Geprüft & in Ordnung (keine Findings)

| Bereich | Ergebnis |
|---------|----------|
| Hardcodierte Secrets/Tokens im Code | ✅ Keine (`grep ghp_` leer) |
| `github_token.txt`, `sparkle_private_key.txt` in `.gitignore` | ✅ Beide ignoriert |
| Passwort/Secret in Logs (`print`/`os_log`/`NSLog`) | ✅ Keine Treffer |
| Master-Passwort in UserDefaults | ✅ Keine UserDefaults-Nutzung |
| AES-256-GCM: zufällige 12-Byte-Nonce (CryptoKit), 32-Byte Random-Salt | ✅ Korrekt, Salt wird mit gespeichert, nie wiederverwendet |
| Auth-Tag-Handling (16 Byte) | ✅ Korrekt, GCM open schlägt bei Manipulation fehl |
| Command Injection (Process) | ✅ Alle `process.arguments` sind Arrays, kein `sh -c` mit User-Input |
| Keychain Access-Level | ✅ `kSecAttrAccessibleWhenUnlocked` (nicht `…Always`) |
| Sparkle Update-Verifikation | ✅ `SUPublicEDKey` gesetzt, `SUFeedURL` über HTTPS → EdDSA aktiv |
| Private-Key Temp-Dateien | ✅ 0600, Löschung via `disconnect()` (siehe SEC-6 unten) |
| Force-Unwrap-Crashes (UTType/URL/UUID) | ✅ In Aufgabe 5 alle entfernt/abgesichert |

### 🔵 SEC-6 — Temp-Private-Key-Löschung nur bei sauberem Disconnect
**Fundstelle:** `ConnectionSession.setupSSH()` schreibt den Key via
`SSHArgumentBuilder.writeTempPrivateKey()` (0600), `disconnect()` löscht ihn.
**Beobachtung:** Bei einem **App-Crash** vor `disconnect()` bliebe die Temp-Key-Datei
liegen.
**Mitigation-Empfehlung:** Beim App-Start verwaiste `nexus_key_*`-Dateien im
Temp-Verzeichnis aufräumen. **Umgesetzt in diesem Durchgang** (siehe WEEK_REPORT.md).
**Status:** Behoben.

---

## Dependency-Check

| Dependency | Version | Bewertung |
|------------|---------|-----------|
| SwiftTerm | 1.0.0+ (SPM) | Aktiv gepflegt, keine bekannten kritischen CVEs |
| Sparkle | 2.0.0+ (SPM, aktuell 2.9.2 gebundlet) | Aktuell, EdDSA-Signatur korrekt verifiziert |

Keine weiteren externen Dependencies. `sshpass`, `FreeRDP`, `pyftpdlib` etc. sind
**nicht** eingebunden (siehe WEEK_REPORT.md, Aufgabe 3).
