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
- [x] Added loose stored-link fallback for account character resolution when strict roster verification paths return no rows.
  Files: `GMS/Modules/AccountInfo.lua`

### Changed
- [x] Changelog seen-version resolution now uses robust multi-source fallback (profile options, raw profile store, `GMS_UIDB` fallback).
  Files: `GMS/Core/Changelog.lua`
- [x] DB tracking keeps AceDB writes and now mirrors to raw `GMS_DB` for persistent DB inspector visibility.
  Files: `GMS/Core/Database.lua`
- [x] Main-character persistence now prefers previously stored/fallback GUIDs and avoids unintended auto-switch to the currently logged character.
  Files: `GMS/Modules/AccountInfo.lua`
- [x] Roster tooltip now renders linked account characters whenever rows are available, independent of strict `hasData` flags.
  Files: `GMS/Modules/Roster.lua`
- [x] Roster GUID lookup now prefers module cache and roster build path (including offline entries) before legacy API fallback.
  Files: `GMS/Modules/Roster.lua`
- [x] AccountInfo store loading now merges raw persisted `GMS_DB.global` link/twink data into AceDB runtime tables to stabilize main-character dropdown options across sessions.
  Files: `GMS/Modules/AccountInfo.lua`
- [x] Roster linked-character handling now normalizes legacy string rows and degrades gracefully when AccountInfo returns rows-only signatures.
  Files: `GMS/Modules/Roster.lua`
- [x] CharInfo account card now omits source/click-hint helper lines for a cleaner linked-character section.
  Files: `GMS/Modules/CharInfo.lua`
- [x] CharInfo raid rows are now limited to current Retail raids and ordered newest-first (`Manaschmiede Omega`, `Befreiung von Lorenhall`, `Palast der Nerub'ar`).
  Files: `GMS/Modules/CharInfo.lua`
- [x] Roster raid status now uses active-raid priority fallback, greys non-top-priority fallback results, and stores raid name/priority metadata for tooltip context.
  Files: `GMS/Modules/Roster.lua`

### Fixed
- [x] Repeated Release Notes auto-open on reload mitigated when option-layer seen-version is unstable.
  Files: `GMS/Core/Changelog.lua`
- [x] `twinks/links` are no longer runtime-only in this path; data is explicitly mirrored to SavedVariables.
  Files: `GMS/Core/Database.lua`
- [x] Linked account character detection no longer fails for offline guild members due strict live-only GUID resolution.
  Files: `GMS/Modules/Roster.lua`
- [x] Roster tooltip no longer renders an empty linked-character section when linked rows are string-based (legacy payload shape).
  Files: `GMS/Modules/Roster.lua`
- [x] Roster tooltip now shows the fallback best-attempt raid line including raid instance name when progression comes from lower-priority active raids.
  Files: `GMS/Modules/Roster.lua`, `GMS/Locales/enUS.lua`, `GMS/Locales/deDE.lua`

### Rules/Infra
- [ ] (noch keine Eintraege)

## Last Release Snapshot

- Version: `1.5.1`
- Date: `2026-02-22`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
