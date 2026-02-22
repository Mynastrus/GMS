# GMS Internal Release Notes

Dieses Dokument ist die interne Sammelstelle fuer alle Aenderungen seit dem letzten echten Release.
Eintraege aus `Unreleased` werden erst bei einem echten Release in `Core/Changelog.lua` uebernommen.

## Workflow

1. Waehrend der Entwicklung nur hier eintragen.
2. Bei echtem Release:
   - Eintraege kuratieren und zusammenfassen.
   - EN/DE Release-Notes in `Core/Changelog.lua` (`RELEASES`) eintragen.
   - `## Version` in `GMS/GMS.toc` erhoehen.
   - `Unreleased` leeren.

## Unreleased

### Added
- [x] Raw-profile fallback fuer changelog seen-state added (reads/writes in `GMS_DB.profiles.<Profile>.modules.CHANGELOG`).
  Files: `GMS/Core/Changelog.lua`
- [x] Raw SavedVariables mirroring for account/twink tracking added (`GMS_DB.global.accountLinks`, `GMS_DB.global.twinks`, `GMS_DB.global.twinkMeta`).
  Files: `GMS/Core/Database.lua`

### Changed
- [x] Changelog seen-version resolution now uses robust multi-source fallback (profile options, raw profile store, `GMS_UIDB` fallback).
  Files: `GMS/Core/Changelog.lua`
- [x] DB tracking keeps AceDB writes and now mirrors to raw `GMS_DB` for persistent DB inspector visibility.
  Files: `GMS/Core/Database.lua`

### Fixed
- [x] Repeated Release Notes auto-open on reload mitigated when option-layer seen-version is unstable.
  Files: `GMS/Core/Changelog.lua`
- [x] `twinks/links` are no longer runtime-only in this path; data is explicitly mirrored to SavedVariables.
  Files: `GMS/Core/Database.lua`

### Rules/Infra
- [ ] (noch keine Eintraege)

## Last Release Snapshot

- Version: `1.5.1`
- Date: `2026-02-22`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
