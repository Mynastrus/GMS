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
- [x] Neue Core-Extension `GMS/Core/RaidIds.lua` hinzugefügt (JournalInstanceID->MapID, MapID->Boss-Stat-IDs, Validator-Helper).

### Changed
- [x] Startseiten-/Dashboard-Anzeige in `GMS/Core/Dashboard.lua` und `GMS/Core/Settings.lua` umgebaut.
- [x] Raid-Erkennung in `GMS/Modules/Raids.lua` auf ID-basierten Statistik-Fallback erweitert (u. a. `2657`, `2769`, `2810`) und weicher getaktet.
- [x] `GMS/Modules/Raids.lua` auf zentrale Raid-ID-Quelle (`GMS_RAIDIDS`) umgestellt; Slash-Ausgaben lokalisiert.
- [x] `GMS/Modules/CharInfo.lua` erweitert (Raid-Spinner in BEST, Tooltip-Status, Lokalisierungs-Lookups für Raid-UI).
- [x] Locale-Tabellen `GMS/Locales/enUS.lua` und `GMS/Locales/deDE.lua` um neue Keys für RAIDS/CHARINFO ergänzt.
- [x] Sprachumschaltung in den Einstellungen erweitert (inkl. on-the-fly Apply) und neue Locale-Keys in allen WoW-Sprachen nativ hinterlegt (`GMS/Core/Settings.lua`, `GMS/Locales/*.lua`).

### Fixed
- [x] CHAR-Store-Bindung in `GMS/Core/Database.lua` stabilisiert (GUID-Wait statt frühem Fallback-Key).
- [x] SavedVariable-Optionen korrigiert (`GMS/Modules/Roster.lua`: `showOnline` wird nicht mehr bei Login hart resettet).
- [x] GuildLog-Initialanzeige korrigiert (`GMS/Modules/GuildLog.lua`: zuerst Sync, dann UI-Lesen).
- [x] Raidnamen/BEST-Darstellung in `GMS/Modules/CharInfo.lua` korrigiert (keine reinen IDs mehr, BEST-Farbformat robust).
- [x] Crash im Raid-Spinner behoben (`labelWidget` nil-guard in `GMS/Modules/CharInfo.lua`).

### Rules/Infra
- [x] Unreleased-Abschnitt nach Release `1.4.7` fuer die naechste Iteration zurueckgesetzt.
- [x] `GMS_PROJECT_RULES.md` erweitert: neue Pflichtregel fuer lokalisierbare Chat-/UI-/Tooltip-/generierte Texte (Ausnahme Eigennamen, Verweis auf `GMS/Locales/`).

## Last Release Snapshot

- Version: `1.4.7`
- Date: `2026-02-16`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
