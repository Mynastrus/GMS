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
- (none)

### Changed
- Updated Retail compatibility for Midnight 12.1 / Curse of Ula'tek: TOC interface version, Retail-first addon enumeration, current Midnight raid selection, and the prepared bilingual 2.0.2 release entry (`GMS/GMS.toc`, `GMS/Core/UI.lua`, `GMS/Modules/CharInfo.lua`, `GMS/Core/Changelog.lua`).

### Fixed
- Restored guild member counts, online counts, MOTD, and guild-info text on the current Retail `C_GuildInfo` API (`GMS/Modules/GuildInfo.lua`).

### Rules/Infra
- Post-release baseline reset after `2.0.1`; next iteration starts here.

## Last Release Snapshot

- Version: `2.0.1`
- Date: `2026-06-12`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
