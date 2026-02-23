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
- Canonical DB schema document added in `GMS_DB_SCHEMA.md` (3-tree model: `global.chars`, `global.guilds`, `global.characters`, plus local `char.*.chars`).
- Mandatory per-domain metadata documented (`data` + `meta` with `sourceGuid`, `sourceName`, `updatedAt`).

### Changed
- [ ] (noch keine Eintraege)

### Fixed
- [ ] (noch keine Eintraege)

### Rules/Infra
- DB schema policy hardened in `GMS_DB_SCHEMA.md`: hard cutover only, no migration layer, and mandatory sync block for older GMS versions.

## Last Release Snapshot

- Version: `1.5.2`
- Date: `2026-02-23`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
