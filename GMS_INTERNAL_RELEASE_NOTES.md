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
- Hard cutover to `EQUIPMENT_V2` completed: `GMS/Modules/Equipment.lua` now persists only `global.characters[guid].EQUIPMENT_V2`; `GMS/Modules/Roster.lua` and `GMS/Modules/CharInfo.lua` no longer read legacy `EQUIPMENT` buckets/snapshots.
- Canonical schema updated in `GMS_DB_SCHEMA.md`: equipment domain key is `EQUIPMENT_V2` only; legacy `EQUIPMENT` is explicitly removed.
- `GMS/Modules/Equipment.lua` options scope moved from `CHAR` to `PROFILE` and now purges legacy `global.characters[guid].EQUIPMENT` nodes to prevent old option payload reappearing after DB reset.
- Canonical naming aligned with runtime intent: `global.chars` renamed to `global.accountChars` (local account GUIDs only), and guild member table renamed from `global.guilds[guildClubId].players` to `global.guilds[guildClubId].roster` (hard cut, no migration).
- UI/Dock behavior updated: `GUILDLOG` and `PERMISSIONS` sidedock icons are now hidden by default; RightDock reflow/hide calls are deferred during combat lockdown and resumed on `PLAYER_REGEN_ENABLED` to prevent blocked Blizzard actions.
- Roster UX updated: added slash subcommand `/gms roster` (alias `/gms ro`) to open the roster page directly.
- Localization coverage expanded across all locale files (`enUS`, `deDE`, `frFR`, `esES`, `itIT`, `ptBR`, `ruRU`, `koKR`, `zhCN`, `zhTW`) for newly introduced UI/chat strings (ChatLinks, Changelog, Core/DB/Raids options, CharInfo portal tooltips, Roster tooltip labels/formatting) with full key parity against `enUS`.

### Fixed`r`n- Lua syntax error in `GMS/Modules/MythicPlus.lua` fixed: replaced invalid `}` with `end` in `_PublishMythicToGuild` payload loop; module `METADATA.VERSION` bumped to `1.1.8`.`r`n- DB wipe/reset in `GMS/Core/Database.lua` now performs a hard reset of `GMS_DB`, `GMS_Logging_DB`, and `GMS_UIDB` roots and clears runtime DB handles to avoid stale AceDB proxy data after reset.
- CHARINFO local bootstrap in `GMS/Modules/CharInfo.lua` now persists local version metadata through canonical `global.characters[guid].CHARINFO = { data, meta }`.
- DB Inspector serialization in `GMS/Core/Database.lua` now shows raw item strings (e.g. `item:...`) instead of UI-resolved item hyperlinks.
- Guild storage normalization in `GMS/Core/Database.lua` now enforces numeric `guildClubId` keys only, migrates legacy string buckets (e.g. `Realm|Faction|Guild`) into the active club-id bucket, and removes deprecated string-key buckets.
- Guild root metadata hydration added in `GMS/Core/Database.lua`: `global.guilds[guildClubId].meta` is now auto-populated (`guildClubId`, `name`, `realm`, `faction`, `displayKey`, `updatedAt`) and no longer remains empty after initialization.
- Guild root metadata in `GMS/Core/Database.lua` now also persists `updatedAtTs` alongside `updatedAt`.
- Character/guild indexing is now consistent across read/receive/save paths: `global.characters[guid]` is auto-created for known guild/player GUIDs, and `global.guilds[guildClubId].players[guid]` is upserted centrally via `GMS:UpsertGuildPlayer(...)` from DB/Comm/Roster/GuildLog flows.
- Roster ingest in `GMS/Modules/Roster.lua` now ensures `global.characters[guid]` directly and no longer writes remote guild GUIDs into `global.accountChars`.
- CharInfo Mythic+ rendering in `GMS/Modules/CharInfo.lua` was stabilized after reloads, migrated to split V/T columns, centered total score display, and Blizzard-style score coloring for totals and key-level colors.
- RAIDS_V2 sync payload in `GMS/Modules/Raids.lua` now publishes compact one-line `data[raidId]` entries consistently, while `GMS/Modules/Roster.lua` accepts both legacy and compact RAIDS_V2 payload formats.
- RAIDS lockout timing now uses absolute server time in `GMS/Modules/Raids.lua` (`resetAt = GetServerTime() + resetSeconds`) with legacy-safe cleanup logic for older runtime-time entries.
- CharInfo raid lockout rendering in `GMS/Modules/CharInfo.lua` now filters expired lockouts reliably and supports both compact `c<diff>=k/t/l/e/r` and extended `c<diff>=k/t/l/e/r/bossCsv` RAIDS_V2 formats.
- Mojibake/encoding corruption in `ruRU.lua`, `koKR.lua`, `zhCN.lua`, and `zhTW.lua` was repaired to valid UTF-8 readable native text; all locale files now validate as UTF-8 and expose complete key sets.

### Rules/Infra
- DB schema policy hardened in `GMS_DB_SCHEMA.md`: hard cutover only, no migration layer, and mandatory sync block for older GMS versions.

## Last Release Snapshot

- Version: `1.5.2`
- Date: `2026-02-23`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`

