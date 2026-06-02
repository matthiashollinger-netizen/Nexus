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

### Task 1-Folge: Keychain-Popup bei SSH-Verbindung entfernt
- `NexusSSHTerminalView.startSSH()` injiziert das Passwort jetzt über ein
  temporäres Askpass-Script (wie SFTP), statt es im Keychain abzulegen.
- Der Keychain-basierte Pfad in `NexusAskPassService` entfällt → **kein
  Sicherheits-Popup** mehr beim Verbinden.
- Das Temp-Script wird mit `0700` geschrieben und nach Prozess-Ende garantiert
  gelöscht (auch im Fehlerfall).

---

## Bewusst zurückgestellt / deaktiviert

_(wird am Ende finalisiert)_

---

## Was der User nächste Woche zuerst testen sollte

_(wird am Ende finalisiert)_
