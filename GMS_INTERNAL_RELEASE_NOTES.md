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
- Core DB helpers added in `GMS/Core/Database.lua` for canonical writes: server-time stamps, guild ID resolution via `C_Club.GetGuildClubId()`, GUID registry (`global.chars`), and character domain storage (`global.characters[guid][domain]` with `data/meta`).

### Changed
- Sync protocol rules moved/refined in `GMS_PLAYER_SYNC_BASELINE.md` (strict version gate, `*_V2` domain namespace, minimal `ANN/REQ/PUSH` flow, ANN header contract).
- `GMS_DB_SCHEMA.md` adjusted to reference sync protocol ownership in `GMS_PLAYER_SYNC_BASELINE.md`.
- Sync transport hardened in `GMS/Core/Comm.lua`: switched to `__SYNC_V2`, strict addon-version gate, V2 domain allowlist, ANN header contract alignment, and canonical character-domain persistence on receive.
- Modules switched to V2 sync domains: `GMS/Modules/Equipment.lua`, `GMS/Modules/Raids.lua`, `GMS/Modules/MythicPlus.lua`, `GMS/Modules/AccountInfo.lua`, `GMS/Modules/Roster.lua`, `GMS/Modules/CharInfo.lua`.
- Account link storage moved to local char tree in `GMS/Modules/AccountInfo.lua` (`char.*.chars.links`) as source of truth.
- Roster/CharInfo adjusted to roster-first hydration and V2 domain handling in `GMS/Modules/Roster.lua` and `GMS/Modules/CharInfo.lua`.
- Equipment persistence compacted in `GMS/Modules/Equipment.lua`: snapshot slots now store raw item links only (including full hyperlink when available), while DB character domain write remains canonical `data/meta`.
- CharInfo equipment rendering in `GMS/Modules/CharInfo.lua` now resolves names, icons, ilvl, VZ (enchants/sockets), and TSET from compact raw links with API fallback.
- Roster fallback readers/writers in `GMS/Modules/Roster.lua` aligned to canonical character domain nodes (`CHARINFO`, `EQUIPMENT`) with legacy-read fallback only.
- Equipment V2 wire payload in `GMS/Modules/Equipment.lua` switched to compact slot-map only (`EQUIPMENT_V2.data` now directly contains slot entries, no wrapper fields like `module/reason/snapshot/version`).
- Equipment domain fallback readers in `GMS/Modules/Roster.lua` and `GMS/Modules/CharInfo.lua` now accept both canonical compact slot-map and legacy wrapped snapshot payloads.

### Fixed
- DB wipe/reset in `GMS/Core/Database.lua` now performs a hard reset of `GMS_DB`, `GMS_Logging_DB`, and `GMS_UIDB` roots and clears runtime DB handles to avoid stale AceDB proxy data after reset.
- CHARINFO local bootstrap in `GMS/Modules/CharInfo.lua` now persists local version metadata through canonical `global.characters[guid].CHARINFO = { data, meta }`.
- DB Inspector serialization in `GMS/Core/Database.lua` now shows raw item strings (e.g. `item:...`) instead of UI-resolved item hyperlinks.

### Rules/Infra
- DB schema policy hardened in `GMS_DB_SCHEMA.md`: hard cutover only, no migration layer, and mandatory sync block for older GMS versions.

## Last Release Snapshot

- Version: `1.5.2`
- Date: `2026-02-23`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
