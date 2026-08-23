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
- Reworked SavedVariables around schema 4: stable canonical character domains, one account character registry, seven-day migration backup, daily configurable cleanup, and canonical sync-domain handling replace parallel V1/V2 data paths (`GMS/Core/Database.lua`, `GMS/Core/Comm.lua`, `GMS/Modules/AccountInfo.lua`, `GMS/Modules/Equipment.lua`, `GMS/Modules/MythicPlus.lua`, `GMS/Modules/Raids.lua`, `GMS/Modules/Roster.lua`, `GMS/Modules/CharInfo.lua`).
- Updated Retail compatibility for Midnight 12.1 / Curse of Ula'tek: TOC interface version, Retail-first addon enumeration, current Midnight raid selection, and the prepared bilingual 2.0.2 release entry (`GMS/GMS.toc`, `GMS/Core/UI.lua`, `GMS/Modules/CharInfo.lua`, `GMS/Core/Changelog.lua`).
- Updated Character Info raid fallbacks with the current Midnight Season 1 and 2 raids, localized names, and correct boss totals (`GMS/Modules/CharInfo.lua`, `GMS/Locales/enUS.lua`, `GMS/Locales/deDE.lua`).
- Made the Roster Raid column report only each player's best progress in the current Midnight Season 2 raid, Der Giftige Abgrund / The Venomous Abyss (`GMS/Modules/Roster.lua`).

### Fixed
- Fixed a recursive sync-domain normalizer that could prevent AccountInfo, Roster, and MythicPlus from enabling after the schema migration (`GMS/Core/Comm.lua`).
- Included legacy `ACCOUNT_CHARS_V2` character records in same-account discovery, so characters saved before `ACCOUNTINFO_V1` are still shown when they are members of the current guild roster (`GMS/Modules/AccountInfo.lua`).
- Restored Account/Twink discovery across character switches by merging legacy per-character links and twink metadata with new GUID-indexed account records; guild-context comparisons now fall back to the current guild name when storage keys differ, while outbound sync includes only characters confirmed in the live guild roster (`GMS/Modules/AccountInfo.lua`).
- Made the Roster Raid column validate synchronized progress against the transmitted current raid instance ID; missing or older raid IDs now remain muted while the row tooltip shows the reported progress, raid, and ID (`GMS/Modules/Roster.lua`, `GMS/Locales/enUS.lua`, `GMS/Locales/deDE.lua`).
- Preserved the current raid instance ID and name when Roster reads progress from the live Raids module, so the enriched data reaches the guild-sync payload (`GMS/Modules/Roster.lua`).
- Preserved the current raid instance ID and name when Roster falls back to the stored RAIDS_V2 snapshot, ensuring the UI can validate locally cached progress as well (`GMS/Modules/Roster.lua`).
- Rebuilt the Character Info layout once after a settled panel resize, changed its primary card stacks to live weighted columns, and force-laid out the parent-to-scroll content chain before deferred cards render; this prevents stale opening widths from leaving a column partially rendered after opening, reloading, or resizing (`GMS/Modules/CharInfo.lua`).
- Force CurseForge uploads to the explicit Retail game version (`12.1.0`) so releases cannot be misclassified as Titan Reforged Classic (`.github/workflows/upload-to-curseforge.yml`).
- Restored guild member counts, online counts, MOTD, and guild-info text on the current Retail `C_GuildInfo` API (`GMS/Modules/GuildInfo.lua`).
- Prevented the Character Info panel from synchronously initializing the Encounter Journal, scanning the full spellbook for portal names, constructing protected Mythic+ portal/cooldown frames, or building all cards in the click handler; Journal tier scans and UI rendering are now bounded to avoid Retail client soft locks (`GMS/Modules/CharInfo.lua`, `GMS/Modules/Raids.lua`).
- Restored the complete deferred Character Info layout: the data-refresh ticker no longer cancels the newly created card-render queue (`GMS/Modules/CharInfo.lua`).
- Removed the Character Info layout-resize rebuild loop, which could repeatedly reopen the page while cards were being added and freeze the Retail client (`GMS/Modules/CharInfo.lua`).
- Restored safe raid and dungeon texture display and derive a raid's Best value from its current live lockout when Retail statistics are not available yet (`GMS/Modules/CharInfo.lua`).
- Resolve current Midnight raid artwork asynchronously and apply it to Character Info after the Encounter Journal is ready, avoiding synchronous Journal work on panel open (`GMS/Modules/Raids.lua`, `GMS/Modules/CharInfo.lua`).
- Preserve Encounter Journal texture paths as well as numeric file IDs so current raid artwork renders correctly in Character Info (`GMS/Modules/Raids.lua`, `GMS/Modules/CharInfo.lua`).
- Added a safe external-character fallback so an unavailable or malformed synced profile cannot leave the Character Info page blank (`GMS/Modules/CharInfo.lua`).
- Preserve basic guild-roster identity fields in the external-character fallback and include actionable build errors in the internal log (`GMS/Modules/CharInfo.lua`).
- Fixed external Character Info rendering by passing only the Mythic+ texture return value to `tonumber`, avoiding Retail's invalid-base error (`GMS/Modules/CharInfo.lua`).

### Rules/Infra
- Post-release baseline reset after `2.0.1`; next iteration starts here.

## Last Release Snapshot

- Version: `2.0.1`
- Date: `2026-06-12`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
