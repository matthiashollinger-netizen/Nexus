# Nexus v3.0 — UI-Rework & Feature-Ausbau

_Durchgeführt: 2026-06-12 · Version 3.0.0 (Beta) · blueprint-getrieben_

## Auftrag

„Überarbeite das komplette Programm, mach ein Rework. Füge alle Features hinzu, die
bis jetzt nicht umgesetzt werden konnten. Schau dir die UI-Design-Features im Detail
an und verbessere sie … mach ein Meisterprogramm daraus."

## Ansatz (und eine bewusste Entscheidung)

**Aufwertung statt Neuschreiben.** Der Kern (SSH/Telnet/Serial, native TFTP/FTP/HTTP-
Server, verschlüsselter Credential-Store, die toleranten Decoder) funktioniert und
hält **36 echte Sessions**. Ein „from scratch"-Rewrite hätte genau das riskiert. Das
„Meisterprogramm" entsteht stattdessen aus (1) einem echten Design-System, (2) der
Neugestaltung der wichtigsten Flächen darauf und (3) den machbaren, bisher fehlenden
Features — ohne den funktionierenden Kern anzufassen.

Vorgehen in Phasen (verstehen → entwerfen → umsetzen → prüfen), jede Phase mit einem
Multi-Agent-Workflow vorbereitet:
1. **Verstehen:** 8 Agenten haben jede UI-Fläche im Detail auditiert. Ergebnis,
   einstimmig: **es gab kein Design-System** — 8 verschiedene Eckenradien, ~149
   Ad-hoc-`.font()`-Aufrufe, verstreute Paddings, hartkodierte `.green/.red/.black`,
   schwache/leere Empty-States, keine Status-Indikatoren, keine Befehlspalette.
2. **Entwerfen:** 3 unabhängige Designer-Vorschläge + Jury → ein verbindlicher
   Blueprint (`docs/v3_design_blueprint.json`).
3. **Umsetzen:** Fundament zuerst, dann Fläche für Fläche, nach jedem Schritt gebaut.
4. **Prüfen:** adversariale Review (Regressions, Concurrency, Datenverlust, i18n).

## Was neu ist

### Design-System (`Nexus/DesignSystem/`)
- **`DS`-Token-Namespace:** `DS.Space` (4-pt-Raster), `DS.Radius`, `DS.Font`
  (semantische Typo-Leiter mit tabellarischem Monospace), `DS.Color` (system-/
  material-basiert → Hell/Dunkel + Akzent + „Kontrast erhöhen" gratis), `DS.Icon`,
  `DS.Motion`.
- **Eine Quelle der Wahrheit für Verbindungsstatus:** `extension ConnectionState`
  liefert `tint`/`symbol`/`label` — jeder Status sieht überall identisch aus, ist
  farbenblind-sicher (Farbe **und** Symbol) und kennt keine hartkodierten Farben mehr.
- **Wiederverwendbare Bausteine:** StatusDot (atmend bei „verbindet"), StateBadge,
  NexusCard, EmptyStateView, SectionHeader, KeyHint, MonoText, IconBadge,
  QuickActionTile, InfoCard.

### Dashboard (`Views/Dashboard/DashboardView.swift`)
Ersetzt den faden zentrierten „Willkommen"-Screen durch einen Launchpad:
zeitabhängige Begrüßung, **Schnell-Verbinden-Leiste (⌘K)**, Schnellaktionen-Grid,
Statistik (Sessions/Ordner/aktive Server), **zuletzt verwendete** und **favorisierte**
Verbindungen, **Live-Status der eingebetteten Server**. Erscheint nur, solange kein
Tab offen ist — der funktionierende Terminal-Pfad bleibt unangetastet.

### Befehlspalette ⌘K (`Views/CommandPalette/CommandPalette.swift`)
Spotlight-artige Fuzzy-Suche über Sessions, offene Tabs, Ordner und Aktionen.
Vollständige Tastatur-Navigation (↑/↓/⏎/esc, ⌥⏎ = verbinden & offen lassen) über einen
schlanken `NSTextField`-Wrapper (zuverlässiger als reines SwiftUI für Pfeiltasten),
Live-Hervorhebung der Treffer, eigener `@Observable`-Model → testbar. ⌘K kollidiert
nicht mit ⌘⇧K (Passwort-Manager).

### Seitenleiste, Tabs & Co.
- Live-**Status-Punkte** pro Session (nur wenn ein Tab offen ist → die Liste liest
  sich als vertikaler „Gesundheits-Rhythmus").
- **Hover-Aktionen** (Verbinden/Bearbeiten) direkt in der Zeile.
- **Favoriten** (Stern) + Kontextmenü.
- Echter **Empty-State** statt leerer Liste.
- Tab-Bar: gemeinsamer Status-Punkt statt „…/✕"-Emoji, Hover-Schließen-Button.
- Reconnect-Overlay: System-Material (Hell/Dunkel), „Schließen" (esc) neben
  „Neu verbinden" (⏎).

### Bisher fehlende Features (jetzt umgesetzt)
- **Snippets:** wiederverwendbare Befehle pro Session, per Menü mit einem Klick ins
  laufende Terminal (SSH/Telnet/Serial). **Nebenfix:** SSH hatte zuvor keinen
  Sende-Kanal — dadurch erreichten auch **Makros** nie SSH-Sessions; jetzt behoben.
- **Mitteilungen** (native macOS) bei unerwartetem Verbindungsabbruch — abschaltbar,
  reguläres Schließen löst nichts aus.
- **nexus:// Deep-Links** (`open/<id>`, `connect?host=…&type=ssh|telnet|serial`).

## Datensicherheit

Alle neuen Modellfelder (`isFavorite`, `snippets`, `recentSessionIds`,
`sidebarCompact`, `notifyOnDisconnect`) sind in den **toleranten Decodern** ergänzt
(`decodeIfPresent(...) ?? default`) — alte JSON-Dateien laden unverändert. Der v2.2-
Datenverlust kann sich nicht wiederholen.

## Verifikation

- **Build (Debug):** ✅ fehlerfrei (nach jedem Schritt neu gebaut).
- **App-Start mit echten Daten:** ✅ läuft, kein Crash, kein Crash-Report;
  Dashboard/Palette/Seitenleiste rendern mit den echten Sessions.
- **Unit-Tests:** ✅ `** TEST SUCCEEDED **`, 0 Fehler — die bestehende Suite läuft
  mit den additiven Modell-Änderungen unverändert grün.
- **Adversariale Multi-Agent-Review** (8 Agenten über 5 Dimensionen, jede
  Erkenntnis gegen-geprüft): 3 echte Befunde gefunden **und behoben**:
  1. _Reconnect-Race_ — beim erneuten Verbinden wurde die alte Session jetzt
     vollständig „verwaist" (Sende-Handler/View-Referenz genullt), bevor die neue
     entsteht — kein verirrtes Makro/Snippet/Callback ans alte Terminal.
  2. _Falsche Mitteilung bei sofortigem SSH-Fehlschlag_ — der Status wird nicht mehr
     vorschnell auf „verbunden" gesetzt, sondern erst beim ersten Byte vom Server;
     ein sofort beendeter SSH-Prozess löst damit keine „Verbindung verloren"-
     Mitteilung mehr aus (zusätzlich nur noch ein wirklich etablierter `.connected`
     löst überhaupt eine Abbruch-Mitteilung aus). Nebeneffekt: der Status-Punkt
     stimmt jetzt genauer.
  3. _Retain-Cycle-Risiko in der Palette_ — Aktions-Closures fassen `vm` jetzt
     schwach (`[weak vm]`), konsistent mit den übrigen.
  Die Dimensionen Lokalisierung (642/642 Schlüssel in de+en), Persistenz (tolerante
  Decoder) und Concurrency kamen ohne bestätigte Befunde zurück.

## Ehrlich offen / nicht machbar

- **RDP:** weiterhin nicht einbettbar (keine native Bibliothek; FreeRDP bräuchte
  XQuartz/Homebrew → widerspricht dem self-contained-Ziel).
- **SFTP-/Telnet-Server:** bräuchten einen vollen SSH-Server bzw. eine
  unauthentifizierte Shell — bewusst nicht ausgeliefert. TFTP/FTP decken
  Geräte-Uploads ab.
- **Voller Token-Sweep** über die restlichen Fenster (Einstellungen, Server-Manager,
  Hilfe, Onboarding, Passwort-Manager, SFTP-Browser, Editor): die **zentralen**
  Flächen (Seitenleiste, Tabs, Dashboard, Palette, Reconnect) sind umgestellt; der
  Rest folgt als separater, risikoarmer Schritt.
- **PBKDF2-KDF-Migration** (SEC-1): bleibt als eigener, sicherheitsfokussierter
  Schritt zurückgestellt.

## Das kann nur ein Mensch beurteilen

Ich konnte die laufende App **nicht** per Screenshot ansehen (Bildschirmaufnahme-
Recht für die Shell fehlt, der Computer-Use-Zugriff lief in einen Timeout). Verifiziert
ist daher „baut & startet ohne Crash", **nicht** „sieht im Detail gut aus". Bitte
visuell prüfen: Dashboard-Layout & Begrüßung, die ⌘K-Palette (Eingabe-Fokus,
Pfeiltasten, Treffer-Hervorhebung), die atmenden Status-Punkte, Hover-Verhalten in der
Seitenleiste, sowie Hell-/Dunkel-Modus.
