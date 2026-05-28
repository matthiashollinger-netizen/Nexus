# Nexus Bug Fix Workflow

## Übersicht

```
User meldet Bug in App
       ↓
GitHub Issue erscheint mit Label bug-open
       ↓
GitHub Actions: Auto-Kommentar + Label → fix-pending
       ↓
Claude Code: Bug analysieren, fixen, build_beta.sh
       ↓
Issue-Label → test-ready, Download-Link im Issue
       ↓
User testet Beta
       ↓
👍 → promote_beta.sh → Stable Release → Issue geschlossen
👎 → Claude iteriert
```

---

## Schritt 1 — Bug Report empfangen

Ein neues GitHub Issue erscheint automatisch sobald ein User in der App auf
**Hilfe → Bug melden…** (⌘⇧B) tippt.

GitHub sendet dir eine E-Mail-Benachrichtigung (sofern unter
[github.com/settings/notifications](https://github.com/settings/notifications)
aktiviert).

**Push-Notifications via Claude Mobile:**
Claude Code kann via Dispatch eine Nachricht senden wenn Beta bereit ist.
Installiere die Claude Mobile App und aktiviere Dispatch-Notifications.

---

## Schritt 2 — Bug fixen mit Claude Code

Starte Claude Code und verwende folgenden Prompt:

```
Analysiere GitHub Issue #{nummer} im Repo matthiashollinger-netizen/Nexus.
Token: lies aus ~/XCode Projects/Nexus/github_token.txt

Gehe so vor:
1. Lies das Issue komplett (Beschreibung, Logs, Umgebung, Schweregrad)
2. Identifiziere die betroffene Datei und den wahrscheinlichen Grund
3. Analysiere den relevanten Code
4. Erstelle einen Git-Branch: fix/issue-{nummer}-{kurzbeschreibung}
5. Behebe den Bug — minimal, gezielt, keine unrelevanten Änderungen
6. Baue die App: xcodebuild build (0 Errors erforderlich)
7. Führe ./scripts/build_beta.sh {aktuelle_version} aus
8. Setze Issue-Label auf test-ready (ersetze fix-pending)
9. Poste Kommentar auf GitHub Issue:
   "✅ Fix implementiert in Branch fix/issue-{nummer}
    Beta-Download: {link}
    Bitte testen und mit 👍 (funktioniert) oder 👎 (Problem bleibt) reagieren."
10. Warte auf User-Feedback
```

---

## Schritt 3a — User gibt 👍

```bash
# Beta promoten, Branch mergen, Issue schließen
./scripts/promote_beta.sh v{VERSION}-beta.{N} {issue_nummer}

# Branch mergen
git checkout main
git merge fix/issue-{nummer}-{kurzbeschreibung}
git push
```

Das Script:
- Lädt das Beta-DMG von GitHub herunter
- Erstellt einen neuen Stable-Release auf GitHub
- Updated `appcast.xml` → alle User bekommen das Update via Sparkle
- Schließt das Issue mit Kommentar und Label `verified`

---

## Schritt 3b — User gibt 👎

```
Lies den Kommentar auf Issue #{nummer} und analysiere erneut.
Der User sagt: "{user_kommentar}"
Iteriere den Fix.
```

---

## Feature Requests

Feature Requests landen via **Hilfe → Feature wünschen…** auf GitHub mit
Label `feature-request`. Der GitHub Actions Workflow postet automatisch einen
Bestätigungs-Kommentar.

Feature Requests werden **manuell** entschieden — kein automatischer Fix.

Wenn ein Feature Request umgesetzt werden soll:
```
Implementiere Feature Request #{nummer} im Repo matthiashollinger-netizen/Nexus.
Token: lies aus ~/XCode Projects/Nexus/github_token.txt
[Beschreibe Scope, Aufwand und was du erwartest]
```

---

## Beta-Release manuell starten

```bash
# Neue Beta für 1.3.0
./scripts/build_beta.sh 1.3.0

# Konkrete Beta-Nummer angeben
./scripts/build_beta.sh 1.3.0 2
```

---

## Stable Release (kein Beta-Cycle nötig)

```bash
./scripts/build_release.sh {VERSION}
```

---

## GitHub Labels — Bedeutung

| Label | Bedeutung |
|-------|-----------|
| `bug-open` | Neuer Bug, noch nicht bearbeitet |
| `fix-pending` | Claude Code arbeitet daran |
| `test-ready` | Beta-Build bereit zum Testen |
| `verified` | Vom User bestätigt behoben |
| `wont-fix` | Wird nicht behoben |
| `feature-request` | Feature-Wunsch, wartet auf Entscheidung |

---

## Project Board

[github.com/users/matthiashollinger-netizen/projects/1](https://github.com/users/matthiashollinger-netizen/projects/1)

Issues werden manuell auf das Board gezogen oder via API bewegt.
Das Board spiegelt den aktuellen Status aller Bugs und Feature Requests.

---

## Benachrichtigungen einrichten

1. **GitHub E-Mail**: [github.com/settings/notifications](https://github.com/settings/notifications) → Issues & Releases aktivieren
2. **GitHub Mobile App**: iOS/Android App installieren für Push-Notifications
3. **Claude Mobile**: App installieren, Dispatch aktivieren → Claude Code sendet Push wenn Beta fertig ist

---

## Scripts Übersicht

| Script | Verwendung |
|--------|-----------|
| `./scripts/build_release.sh {VERSION}` | Stable Release (direkt, kein Beta) |
| `./scripts/build_beta.sh {VERSION} [N]` | Beta Pre-Release erstellen |
| `./scripts/promote_beta.sh {BETA_TAG} [ISSUE]` | Beta → Stable promoten |
