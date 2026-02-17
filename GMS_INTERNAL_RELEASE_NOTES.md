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
- [x] Neues Modul `GMS/Modules/GuildInfo.lua` ergänzt und in `GMS/GMS.toc` registriert.
- [x] Raid-Card in `GMS/Modules/CharInfo.lua` um Icon, Raidbeschreibung-Tooltip, klickbares EJ-Opening und animierte Ladeanzeige erweitert.

### Changed
- [x] Startseiten-/Dashboard-Anzeige in `GMS/Core/Dashboard.lua` und `GMS/Core/Settings.lua` umgebaut.
- [x] Raid-Erkennung in `GMS/Modules/Raids.lua` auf ID-basierten Statistik-Fallback erweitert (u. a. `2657`, `2769`, `2810`) und weicher getaktet.

### Fixed
- [x] CHAR-Store-Bindung in `GMS/Core/Database.lua` stabilisiert (GUID-Wait statt frühem Fallback-Key).
- [x] SavedVariable-Optionen korrigiert (`GMS/Modules/Roster.lua`: `showOnline` wird nicht mehr bei Login hart resettet).
- [x] GuildLog-Initialanzeige korrigiert (`GMS/Modules/GuildLog.lua`: zuerst Sync, dann UI-Lesen).
- [x] Raidnamen/BEST-Darstellung in `GMS/Modules/CharInfo.lua` korrigiert (keine reinen IDs mehr, BEST-Farbformat robust).

### Rules/Infra
- [x] Unreleased-Abschnitt nach Release `1.4.7` fuer die naechste Iteration zurueckgesetzt.

## Last Release Snapshot

- Version: `1.4.7`
- Date: `2026-02-16`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
