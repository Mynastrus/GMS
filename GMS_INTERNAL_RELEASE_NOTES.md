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
- [x] Neues einheitliches Persistenzschema in `GMS_DB.global` (`modules`, `characters`, `guilds`) als zentrale Source of Truth fuer alle Scopes.

### Changed
- [x] `Database.lua` auf neue Scope-Roots umgestellt: `PROFILE`, `GLOBAL`, `CHAR`, `GUILD` laufen jetzt konsistent ueber dieselbe DB-Struktur.
- [x] `RegisterModuleOptions`/`GetModuleOptions` verwenden keine AceDB-Namespaces mehr, sondern die neuen zentralen Scope-Tabellen.
- [x] `Comm.lua` speichert `COMM_SYNC` jetzt ueber die neue `GUILD`-Scope-Optionstabelle statt ueber `GMS_Guild_DB`.
- [x] `GuildLog.lua` verwendet ausschliesslich die neue DB-Version (kein Legacy-/Migrationspfad mehr).

### Fixed
- [x] Persistenz-Inkonsistenzen zwischen Modulen reduziert, da alle Moduloptionen jetzt aus derselben strukturierten Datenbasis aufgeloest werden.

### Rules/Infra
- [x] Versionsupdates fuer geaenderte Dateien gemaess Projektregeln (`Database`, `Comm`, `GuildLog`).

## Last Release Snapshot

- Version: `1.4.0`
- Date: `2026-02-14`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
