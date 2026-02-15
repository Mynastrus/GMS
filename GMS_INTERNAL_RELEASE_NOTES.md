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
- [x] Neuer Slash-Subcommand für Hard-Reset: `/gms dbwipe` (Alias: `dbreset`, `resetdb`, `wipe`).

### Changed
- [x] `Database_ResetAll` erweitert: leert jetzt zusätzlich `GMS_UIDB` und `GMS_Changelog_DB` für wirklich sauberen Reset.
- [x] One-Time-Release-Reset in `Core/Database.lua` ergänzt (versionsgesteuert über `ONE_TIME_RESET_TARGET_VERSION`, aktuell `1.4.6`).
- [x] One-Time-Reset hinterlegt Marker in `GMS_DB.global` (`oneTimeHardResetAppliedVersion`, `oneTimeHardResetAppliedAt`) zur sicheren Einmal-Ausführung.

### Fixed
- [x] Lua-Diagnostics (`undefined-field`) in `Core/Database.lua` beseitigt, indem `_G`-Zugriffe auf optionale SVs via `rawget(_G, "...")` erfolgen.

### Rules/Infra
- [ ] (leer)

## Last Release Snapshot

- Version: `1.4.5`
- Date: `2026-02-15`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
