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
- [x] Scope-Roots fuer `CHAR`/`GUILD` auf die bestehende direkte Datenstruktur korrigiert (`global.characters[charKey].<MODULE>` / `global.guilds[guildKey].<MODULE>`), damit Modulwerte sichtbar und konsistent persistieren.
- [x] Modul-Optionen nutzen jetzt kanonische Modulkeys (uppercase), damit unterschiedliche Schreibweisen (`Equipment` vs `EQUIPMENT`) nicht zu getrennten Speicherpfaden fuehren.
- [x] `GUILD`-Scope wird erst angelegt, wenn ein echter Guild-Key verfuegbar ist; fruehe Fallback-Bindings auf instabile Keys wurden entfernt.
- [x] Modulregistrierungen werden jetzt auch dann dauerhaft vorgemerkt, wenn der Scope-Root beim fruehen Start noch nicht verfuegbar ist (deferred bind statt verlorener Registrierung).
- [x] Guild-Key-Fallback ergaenzt: bei genau einem vorhandenen Guild-Bucket in `global.guilds` wird dieser Key wiederverwendet, falls API-Key noch nicht aufgeloest ist.
- [x] GuildLog erzwungen auf `GuildRoster`-Refresh bei `GUILD_ROSTER_UPDATE`, damit Notiz-/Roster-Aenderungen schneller und zuverlaessiger erkannt werden.
- [x] GuildLog-Persistenz auf direkten Guild-DB-Pfad umgestellt (`GMS.db.global.guilds[guildKey].GUILDLOG`), um Registrierungs-/Timing-Races in der Optionskette zu umgehen.
- [x] Laufzeitfehler behoben: `GetNumGuildMembers()` in `GuildLog` auf ersten Rueckgabewert begrenzt (`select(1, ...)`), damit `tonumber` keinen invaliden Base-Parameter erhaelt.
- [x] GuildLog rebinding fix: RAM-Fallback-Optionen werden nach spaeter verfuegbarem Guild-Key in die persistente Tabelle gemerged; damit gehen Eintraege nach `/reload` nicht mehr verloren.
- [x] GuildLog-Hard-Persist-Mirror hinzugefuegt: Eintraege werden zusaetzlich explizit in den aktuellen Guild-Bucket geschrieben, um Referenz-/Timing-Ambiguitaeten zu eliminieren.
- [x] GuildLog-UI bindet jetzt beim Rendern/Toggle immer aktiv an die persistente Guild-Optionstabelle; historische Eintraege und `chatEcho`-Status bleiben damit nach Reload sichtbar.
- [x] GuildLog-UI rendert bei jedem Oeffnen vollstaendig neu (kein Cache-Stale), inklusive Statuszeile mit aktivem DB-Key, Entry-Count, History-Count und ChatEcho-Status.
- [x] GuildLog-UI zeigt bei fehlenden Legacy-Entries jetzt eine rekonstruierte Historienansicht aus `memberHistory` (Join/Leave/Rejoin-Zaehler), damit Altstaende sichtbar bleiben.

### Rules/Infra
- [x] Versionsupdates fuer geaenderte Dateien gemaess Projektregeln (`Database`, `Comm`, `GuildLog`).

## Last Release Snapshot

- Version: `1.4.0`
- Date: `2026-02-14`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
