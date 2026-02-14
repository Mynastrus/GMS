# GMS Internal Release Notes

Dieses Dokument ist die interne Sammelstelle für alle Änderungen seit dem letzten echten Release.
Einträge aus `Unreleased` werden erst bei einem echten Release in `Core/Changelog.lua` übernommen.

## Workflow

1. Während der Entwicklung nur hier eintragen.
2. Bei echtem Release:
   - Einträge kuratieren und zusammenfassen.
   - EN/DE Release-Notes in `Core/Changelog.lua` (`RELEASES`) eintragen.
   - `## Version` in `GMS/GMS.toc` erhöhen.
   - `Unreleased` leeren.

## Unreleased

### Added
- [ ] (aktuell keine neuen Features seit letztem Release)

### Changed
- [ ] (aktuell keine Änderungen seit letztem Release)
- [ ] Roster um Spalten `Zuletzt online` (Guild-API LastOnline) und `GMS` erweitert (`GMS/Modules/Roster.lua`, uncommitted)
- [ ] Roster tauscht GMS-Versionen jetzt per Comm-Heartbeat (`ROSTER_META`) aus und zeigt bekannte Versionen pro Mitglied an (`GMS/Modules/Roster.lua`, uncommitted)
- [ ] Roster-Header wieder untereinander strukturiert (Titel oben, Meta darunter), Titel leicht verkleinert/höher ausgerichtet und Suchzeile ergänzt (`GMS/Modules/Roster.lua`, uncommitted)
- [ ] Roster-Volltextsuche über alle Member-Felder integriert (inkl. Online/Offline-Filterkombination) (`GMS/Modules/Roster.lua`, uncommitted)
- [ ] Mitgliederzählung aus dem Roster-Header in die Statusleiste verlagert; Status zeigt dynamisch `Mitglieder` bzw. `angezeigt X von Y` (inkl. Suche) (`GMS/Modules/Roster.lua`, uncommitted)
- [ ] Presence-Indikator auf FriendsFrame-Statusicons umgestellt (Online/Offline/Away/Busy) und Fraktions-Icon-Spalte mit Tooltip in der Rosterliste ergaenzt (`GMS/Modules/Roster.lua`, uncommitted)

### Fixed
- [ ] (aktuell keine separaten Bugfix-Only Einträge seit letztem Release)

### Rules/Infra
- [ ] (aktuell keine Rules/Infra-Änderungen seit letztem Release)

## Last Release Snapshot

- Version: `1.3.22`
- Date: `2026-02-14`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
