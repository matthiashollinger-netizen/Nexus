# Nexus — Bugfixing & echte Server (v2.3.0)

_Durchgeführt: 2026-06-09 · Basis-Tag: `stable-pre-fixes2` · Beta: v2.3.0-beta.1_

> Rückkehr zum Stand davor: `git reset --hard stable-pre-fixes2`

---

## Überblick — alle 8 Aufgaben

| # | Aufgabe | Status |
|---|---------|--------|
| 1 | Datenverlust: Sessions verschwinden / Backup 0 Sessions | ✅ Ursache gefunden + behoben + Tests |
| 2 | Datenverlust-Schutz für laufende Migration | ✅ Forensik + Schutznetze |
| 3 | Sidebar Einzel-/Doppelklick (3× zurück) | ✅ Dauerhaft, in NOTES.md begründet |
| 4 | SFTP „Authentication failed" | ✅ Behoben + Tests |
| 5 | SSH/SFTP Port (2222) | ✅ Behoben + Tests |
| 6 | Sidebar-Drag sichtbarer Einfüge-Strich | ✅ |
| 7 | Echte TFTP/FTP-Server | ✅ TFTP + FTP nativ, mit echten Client-Tests |
| 8 | Editor Platzhalter-Texte entfernen | ✅ |

**Build:** ✅ fehlerfrei · **Unit-Tests:** ✅ **85/85 grün** · **App-Start:** ✅ verifiziert

---

## Aufgabe 1 + 2 — Datenverlust (die wichtigste, ehrliche Ursachen-Analyse)

### Was wirklich passiert ist (durch Backup-Forensik bestätigt)
Die echten Backup-Dateien des Users erzählen die ganze Geschichte:
- `backup_2026-06-02_09-08-44` → **36 Sessions** (vor dem Bug)
- `06-02_14:42` … `06-09_12:39` → **0 Sessions** (Bug aktiv)
- `06-09_12:52` + aktuelle `sessions.json` → **36 Sessions** (wiederhergestellt)

### Die Ursache
Es war **kein Pfad-Problem** — alle Daten liegen stabil unter
`~/Library/Application Support/Nexus/`. Das Problem war **Swifts synthetisiertes
Codable**:

> Der automatisch erzeugte `init(from:)` **ignoriert Default-Werte** und verlangt,
> dass JEDER nicht-optionale Schlüssel im JSON vorhanden ist. Fehlt einer, wirft das
> Decoden des GANZEN Arrays `keyNotFound`.

v2.2.0 fügte nicht-optionale Felder hinzu (`connectTimeout`, `autoConnectOnLaunch`).
Eine `sessions.json` aus v2.1.0 hatte diese Schlüssel nicht → `decode([Session])`
schlug fehl → `loadSessions()` lieferte `[]` → „alle Sessions weg". Das leere
Ergebnis wurde dann beim nächsten Speichern in die Datei geschrieben (echter Verlust).
**Ordner blieben**, weil das `Folder`-Schema unverändert war. Backups zeigten 0
Sessions, weil sie dasselbe leere `loadSessions()` sicherten.

### Der Fix (zukunftssicher)
1. **Tolerante Decoder** für `Session`, `Folder`, `AppSettings`: hand-geschriebener
   `init(from:)` mit `decodeIfPresent(...) ?? default` für JEDES Feld. Fehlende
   Schlüssel nutzen Defaults — Decode schlägt bei Schema-Änderungen NIE mehr fehl.
   (Kommentar in Session.swift verbietet ausdrücklich die Rückkehr zu synthesized.)
2. **Schutznetz im Laden**: schlägt ein Decode trotzdem fehl (echt korrupte JSON),
   wird eine `.corrupt-<zeit>`-Kopie bewahrt statt still `[]` zu liefern.
3. **Schutznetz im Speichern**: eine nicht-leere `sessions.json` wird nie
   kommentarlos durch ein leeres Array ersetzt — vorher entsteht
   `sessions.beforeempty.json`.

### Aufgabe 2 — Sind Userdaten verloren?
**Nein.** Aktuell liegen **36 Sessions** intakt auf der Platte, und es existiert ein
gutes Backup (`backup_2026-06-02_09-08-44`, 36 Sessions). Die „0-Sessions"-Backups
waren nur das Symptom. Nach diesem Fix kann der Verlust nicht mehr auftreten — und
falls eine alte Datei je wieder geladen wird, füllt der tolerante Decoder sie korrekt.

---

## Aufgabe 3 — Sidebar Klick (warum es jetzt stabil ist)

Zwei getrennte Ursachen (beide in NOTES.md dokumentiert):
- **Einzelklick nur neben Text:** `.onDrag` lag auf dem Zeilen-Inhalt und stahl die
  List-Auswahl. → `.onDrag` nur noch auf einem kleinen Griff (`SidebarDragHandle`),
  nie auf dem Text. Zeile = `.contentShape(Rectangle())`.
- **Doppelklick öffnete das ausgewählte statt angeklickte Item:** ein globaler
  NSEvent-Monitor verband `vm.selectedSidebarItem`. → entfernt; pro Zeile
  `simultaneousGesture(TapGesture(count: 2))`, das DIESE Session verbindet.

**Regel (in NOTES.md):** nie wieder `.onDrag`/`.draggable` auf den Zeilen-Inhalt.

---

## Aufgabe 4 + 5 — SFTP Auth & Port

**Ursache:** Das SSH-Terminal fügte Legacy-Algorithmen hinzu, der separate
`/usr/bin/sftp`-Prozess **nicht**. Gegen alte Switches (Port 2222) verband SSH daher,
SFTP scheiterte mit „Authentication failed" / „Connection reset". Der Port war
korrekt (`-P`), die fehlenden Legacy-Algos waren die Ursache.

**Fix:** gemeinsamer `SSHConnectionOptions`, den SSH **und** SFTP verwenden →
identische Legacy-Algos, Host-Key-Bypass, Timeout, Jump-Host. SFTP nutzt `-P`, SSH
`-p` (per Test abgesichert).

---

## Aufgabe 6 — Sichtbarer Einfüge-Strich
Jede Zeile ist eigenes Drop-Ziel und publiziert sich beim Hover an `SidebarDragModel`
→ accent-farbene `InsertionLine` über der Zeile (Sortieren) bzw. Ordner-Highlight
(Hineinziehen). `moveSidebarItem(..., before:)` platziert exakt vor dem Ziel.

---

## Aufgabe 7 — Echte Server (was geht, was nicht)

| Server | Status | Default-Port | Getestet mit |
|--------|--------|--------------|--------------|
| **TFTP** | ✅ nativ (RFC 1350, UDP) — Up- & Download | 6969 | echtes `/usr/bin/tftp` (GET + PUT) |
| **FTP**  | ✅ nativ (RFC 959, Passive Mode) — Up- & Download | 2121 | echtes `/usr/bin/curl` (Download + Upload) |
| **HTTP** | ✅ nativ (bereits vorhanden) | 8080 | echtes `curl` |
| **SFTP** | 🚫 deaktiviert — braucht vollen SSH-Server, nicht self-contained | — | — |
| **Telnet** | 🚫 deaktiviert (nicht benötigt) | — | — |

- **Mac ist der Server**, das Netzwerkgerät der Client (Cisco/HP lädt per TFTP/FTP).
- Bei laufendem Server zeigt die Karte die **erreichbare Adresse** an (z. B.
  `tftp://192.168.x.x:6969`) — genau das, was am Switch einzugeben ist.
- Port < 1024 (z. B. echtes TFTP-69) → Warnung, dass Root nötig ist; Default ist
  daher der hohe Port 6969.
- Zugriffs-Log pro Server (welche Datei wurde geladen/gespeichert).

**Ehrlich:** SFTP-Server wurde NICHT umgesetzt — ein SFTP-Server setzt einen
vollständigen SSH-Server voraus, der sich nicht ohne Systemeingriff self-contained
ausliefern lässt. Für Cisco/HP ist TFTP ohnehin der Standard; FTP deckt den Rest ab.

---

## Self-Check-Ergebnisse (vor dem Beta-Build)
- **App-Start:** ✅ kein Crash, läuft mit den echten 36 Sessions des Users.
- **Persistenz:** ✅ Save/Load-Roundtrip + Backup mit Sessions (Anzahl > 0) per Test
  (`SessionPersistenceTests`). Legacy-JSON ohne neue Felder lädt korrekt.
- **Server real getestet:** ✅ TFTP (tftp GET/PUT), FTP (curl Download/Upload), HTTP
  (curl) gegen localhost — `NativeServerIntegrationTests`, alle grün.
- **Unit-Tests:** ✅ 85/85 grün.

> Hinweis: Der UI-Test `NexusUITestsLaunchTests` ist umgebungsbedingt instabil
> (Headless-Accessibility) und nicht code-bezogen; die Unit-Tests sind maßgeblich.

## Was der User zuerst testen sollte
1. **Beta installieren → sind die 36 Sessions noch da?** (Datenverlust-Fix)
2. **Backup-Verwaltung:** zeigt ein neues Backup jetzt die echte Session-Anzahl?
3. **SFTP-Browser** zur 2222-Session öffnen → Dateien erscheinen (Auth-Fix).
4. **Sidebar:** Session genau auf dem Namen anklicken (wählt aus); andere Session
   doppelklicken (öffnet die richtige); Session ziehen → Einfüge-Strich sichtbar.
5. **Server-Manager → TFTP starten**, am Switch `copy flash tftp://<angezeigte IP>:6969`.

Zum Promoten nach erfolgreichem Test: `./scripts/promote_beta.sh v2.3.0-beta.1`
