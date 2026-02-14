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
- [x] `683f870` Comm-Sync erweitert: Record-basierter Gildenabgleich mit Prioritätslogik (`seq` > `updatedAt`), Persistenz und Whisper-Fallback für große Datensätze.
- [x] `367bf31` Neues Modul `GuildLog` hinzugefügt: separates Gildenaktivitäts-Log mit eigener UI-Seite, Dock-Icon und Slash-Befehl (`/gms guildlog`).
- [x] `119e31d` Mitgliederhistorie im `GuildLog` ergänzt (Join/Leave/Rejoin-Erkennung, Historienfelder pro Mitglied).

### Changed
- [x] `367bf31` Lokalisierung für GuildLog-Texte in `enUS`/`deDE` erweitert.
- [x] `119e31d` Notiz-/Offiziersnotiz-Änderungen im GuildLog auf Detailausgabe (`alt -> neu`) umgestellt.
- [x] (uncommitted) `GuildLog` auf robustere Erkennung/Anzeige angepasst: Profilscope für Optionen, Fallback-Key bei fehlender GUID, Baseline-Eintrag beim Erstscan, Alias-Bereinigung (`glog`).
- [x] (uncommitted) `deDE`-Locale auf Umlaute/ß in relevanten Strings umgestellt.
- [x] (uncommitted) `GuildLog` um Volkswechsel-Tracking (`RACE_CHANGE`) erweitert inkl. `enUS`/`deDE`-Locale-Texten.
- [x] (uncommitted) `GuildLog`-Diff auf stabile Key-Auflösung erweitert (GUID/Name-Mapping + History-Migration), damit Key-Wechsel keine falschen Leave/Join-Paare erzeugen.
- [x] (uncommitted) `GuildLog`-Eventverarbeitung auf Scan-lokale Queue umgestellt und kurze Duplikat-Sperre für Event-Stürme ergänzt.
- [x] (uncommitted) `GuildLog` um Leveländerungs-Tracking (`LEVEL_CHANGE`) inkl. `enUS`/`deDE`-Locale-Texte erweitert.
- [x] (uncommitted) `GuildLog`-Optionen auf `GUILD`-Scope (`GMS_Guild_DB`) umgestellt und Legacy-Store-Migration ergänzt.
- [x] (uncommitted) `GuildLog` migriert In-Memory-Daten beim Rebind zuverlässig in den persistenten Guild-Scope.

### Fixed
- [x] (uncommitted) Fehlerbild „GuildLog zeigt nichts / speichert nichts“ adressiert durch persistente Optionsinitialisierung und stabileres Snapshot-Matching.
- [x] (uncommitted) Leere, temporäre Roster-Snapshots werden nicht mehr als Massen-Änderung verarbeitet (verhindert falsche/fehlende Folgeevents).
- [x] (uncommitted) Guild-Key-Fallback in `Database:GetGuildGUID()` robuster gemacht (Realm|Faction|GuildName), damit Guild-Scoped Daten zuverlässig persistieren.

### Rules/Infra
- [x] Commit-Abdeckung gemäß `GMS_PROJECT_RULES` Abschnitt 11.5 nachgezogen (alle Änderungen seit `v1.3.28` im Unreleased-Block erfasst).

## Last Release Snapshot

- Version: `1.3.28`
- Date: `2026-02-14`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
