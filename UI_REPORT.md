# Nexus — UI-Überarbeitung & Bugfixing (v2.2.0)

_Durchgeführt: 2026-06-02 · Basis-Tag: `stable-pre-ui` · Beta: v2.2.0-beta.1_

> Rückkehr zum Stand vor diesem Durchgang jederzeit möglich:
> `git reset --hard stable-pre-ui`

---

## Überblick — alle 6 Aufgaben umgesetzt

| # | Aufgabe | Status |
|---|---------|--------|
| 1 | Session-Editor komplett neu (MobaXterm-Stil) | ✅ Vollständig |
| 2 | Server-Manager (Menüpunkt) | ✅ Vollständig |
| 3 | SFTP-Browser zeigt keine Dateien (Bug) | ✅ Behoben + Tests |
| 4 | Einzelklick nur neben Text (Regression) | ✅ Behoben |
| 5 | Sidebar-Drag wie Tabs (kein „+") | ✅ Verbessert (siehe Hinweis) |
| 6 | Syntax-Highlighting übereifrig bei Zahlen | ✅ Behoben + Tests |

**Build:** ✅ fehlerfrei · **Unit-Tests:** ✅ 66/66 grün · **App-Start:** ✅ verifiziert (kein Crash)

---

## Aufgabe 1 — Session-Editor (Hauptaufgabe)

Vollständiger Umbau von `AddSessionView` (ersetzt die alte Version auch fürs Bearbeiten):

- **Oben: horizontale Protokoll-Icon-Leiste** — große klickbare Buttons SSH / Telnet /
  Serial, RDP ausgegraut mit Tooltip „folgt". Aktives Protokoll mit Akzentfarbe +
  Hintergrund hervorgehoben. Kein Dropdown mehr.
- **Basis-Einstellungen** prominent, pro Protokoll passend (SSH: Host/Port/User/
  Credential; Telnet: Host/Port; Serial: Port-Dropdown/Baud).
- **Advanced als einzelne aufklappbare DisclosureGroups**, standardmäßig eingeklappt,
  Auto-Expand wenn schon Werte vorhanden, mit „aktiv"-Badge:
  - Verbindung & Sicherheit (Legacy-Algos, Strict-Host-Key, Timeout, Private Key)
  - Gateway & Tunneling (Jump Host, Port Forwardings, SOCKS5)
  - Serielle Parameter (Datenbits/Stoppbits/Parität/Flusssteuerung)
  - Terminal & Darstellung (Theme, Schriftgröße, Syntax-Regelset — **pro Session**)
  - Verhalten (Macro bei Verbindung, Auto-Connect beim Start)
- **Unten:** Name, Beschreibung, Ordner, Tags.
- **Live-Validierung:** leerer Host wird rot markiert, Speichern deaktiviert.
- Scrollbar, durchgehend macOS-nativer Look (bestehendes Farbsystem beibehalten).

**Neu hinzugekommen und vollständig verdrahtet** (nicht nur UI):
- Per-Session-Theme → wird im Terminal angewendet (TabContentView resolved pro Session)
- Per-Session-Schriftgröße → Terminal-Font
- Per-Session-Syntax-Regelset → eigener Highlighter pro Session
- Verbindungs-Timeout → SSH-Argumente
- Macro bei Verbindung → läuft verzögert nach PTY-Aufbau
- Auto-Connect → verbindet markierte Sessions beim Start

**Zu testen:** Neue SSH-Session anlegen → Protokoll-Icons klicken, Basis-Felder
ausfüllen, eine Advanced-Gruppe aufklappen. Eine Session mit eigenem Theme +
Auto-Connect anlegen und App neu starten.

---

## Aufgabe 2 — Server-Manager

- **Neues Menü „Werkzeuge" → „Server-Manager…"** (⌘⌥⇧S). Vorher war der HTTP-Server
  über gar kein Menü erreichbar.
- **Eine Karte pro Server-Typ:**
  - **HTTP** (nativ, kein python3): Start/Stop/Konfigurieren (Root-Ordner, Port),
    Status-Indikator, Port-Anzeige, aufklappbares Quick-Log.
  - **TFTP** (macOS-System-`tftpd`): wie HTTP; Hinweis dass Port 69 root braucht.
  - **SFTP**: Info-Karte „macOS-Systemdienst" mit Button zu den Freigabe-
    Einstellungen (Remoteanmeldung) — self-contained, kein Install.
  - **FTP** / **Telnet**: deaktivierte Karten mit klarer Begründung
    (FTP = externe Lib nötig; Telnet = würde unauth. Shell freigeben → bewusst nicht).

**Zu testen:** Werkzeuge → Server-Manager. HTTP-Server: Ordner wählen, Start,
`http://localhost:8080` im Browser öffnen. SFTP-Karte → „Freigabe-Einstellungen öffnen".

---

## Aufgabe 3 — SFTP-Browser leer (Bug behoben)

Ursache: Beim Verbinden wurde immer `/` gelistet, was auf vielen Servern/Geräten
leer oder eingeschränkt erscheint.

Fix: `SFTPService.listHome()` ermittelt per `pwd` das Home-Verzeichnis und listet
dieses. Leere Ordner zeigen jetzt einen klaren Hinweis statt still leer zu bleiben;
Listing-Fehler bleiben sichtbar. Parser-Tests für `pwd`-Ausgabe, Symlinks und
kombinierte `pwd`+`ls`-Ausgabe ergänzt.

**Zu testen:** Mit SSH-Session verbinden, SFTP-Panel öffnen → Home-Verzeichnis sollte
mit Dateien/Ordnern erscheinen. In Unterordner doppelklicken, Breadcrumb nutzen.

---

## Aufgabe 4 — Einzelklick auf Text (Regression behoben)

Ursache: `.draggable` auf den List-Zeilen (aus dem Drag&Drop-Feature) brach die
Einzelklick-Auswahl auf dem Zeilen-Inhalt — Klick auf den Text wählte nicht aus.

Fix: `.draggable` → `.onDrag`, plus `.contentShape(Rectangle())` auf die ganze Zeile.
Jetzt: Einzelklick = Auswählen (ganze Zeile inkl. Text/Icon), Doppelklick = Verbinden.

**Zu testen:** Eine Session in der Sidebar genau auf dem Namen anklicken → muss
sofort auswählen. Doppelklick → verbindet.

---

## Aufgabe 5 — Sidebar-Drag (verbessert)

Fix: `.dropDestination` → `.onDrop(delegate:)` das `DropProposal(.move)` zurückgibt.
Dadurch zeigt der Cursor jetzt **Verschieben** statt des grünen „+"-Kopier-Badges.
Sessions in Ordner, Ordner in Ordner und Drop auf die oberste Ebene funktionieren;
`.onMove` bleibt für die Sortierung innerhalb einer Ebene; ⌘Z-Undo weiterhin aktiv.

**Ehrlicher Hinweis:** Ein 1:1 „schwebender" Drag wie bei den Browser-Tabs würde
bedeuten, die native `List` durch eine selbstgebaute Scroll-/VStack-Struktur zu
ersetzen — das würde Auswahl, Mehrfachauswahl, Tastatur-Navigation und das native
Sidebar-Aussehen neu implementieren (hohes Regressionsrisiko). Der gewählte Weg
liefert das saubere **Move-Verhalten ohne „+"** innerhalb der robusten nativen List.
Falls der „schwebende" Look zwingend gewünscht ist, sollte das ein eigener,
fokussierter UI-Durchgang sein.

**Zu testen:** Eine Session auf einen Ordner ziehen → Cursor zeigt Move (kein „+"),
Ordner hebt sich hervor, Loslassen verschiebt. ⌘Z macht rückgängig.

---

## Aufgabe 6 — Syntax-Highlighting (Bug behoben)

Ursache: Die Regel „`:` + Portnummer" färbte jede Zahl nach einem Doppelpunkt — auch
Sekunden/Minuten in Uhrzeiten (`20:22:51` → `:22`).

Fix: Ports werden nur noch kontextsensitiv erkannt:
- direkt nach einer vollständigen IPv4 (`10.0.0.1:8080`)
- direkt nach einem Hostname-Zeichen (`localhost:22`)
- nach dem Wort „Port" (`Port 2222`)

Lookbehind-Regex schließt Uhrzeiten aus. 6 neue Tests (`TerminalHighlighterTests`).

**Zu testen:** Im Terminal eine Log-Zeile mit Timestamp ansehen (Netzwerk-Regelset
aktiv) → die Uhrzeit darf nicht eingefärbt sein; „host:22" / „Port 2222" schon.

---

## Tests
Neu hinzugekommen: `TerminalHighlighterTests` (6), SFTP-Parser um Home/Symlink/pwd
erweitert. Gesamt **66 Unit-Tests, alle grün**.

> Hinweis: Der UI-Test `NexusUITestsLaunchTests.testLaunch` schlägt umgebungsbedingt
> im Headless-Runner fehl („has not loaded accessibility") — nicht code-bezogen.
> Die Unit-Tests sind die maßgebliche Absicherung.

## Nächster Schritt
Wenn alles passt: `./scripts/promote_beta.sh v2.2.0-beta.1` (erst nach erfolgreichem
Test — **nicht** automatisch promotet).
