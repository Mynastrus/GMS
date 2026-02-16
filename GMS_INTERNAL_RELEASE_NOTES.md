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
- [ ] (leer)

### Changed
- [x] Equipment-Initialscan robust gemacht: Fallback-Trigger in `OnEnable`, damit Login-Scan auch nach Reload/late enable ausgefuehrt wird. (Datei: `GMS/Modules/Equipment.lua`)
- [x] Raids-Scan robust gemacht: Fallback-Trigger in `OnEnable` sowie Store-Readiness-Polling mit Retry eingebaut. (Datei: `GMS/Modules/Raids.lua`)
- [x] Logs-Source-Aufloesung erweitert: Registry-Matching beruecksichtigt jetzt auch `shortName`, damit die blaue Source-Spalte konsistent auf `DISPLAY_NAME` aufgeloest wird. (Datei: `GMS/Core/Logs.lua`)
- [x] Raids-Scan erweitert: `best`-Progress kann jetzt aus Charakterstatistiken (Boss-Statistikzeilen je Schwierigkeit/Raid) angereichert werden. (Datei: `GMS/Modules/Raids.lua`)
- [x] Roster-Meta erweitert: `best_in_raid` wird als Alias zu `raid` mitgesendet/gespeichert und beim Empfang als Fallback gelesen. (Datei: `GMS/Modules/Roster.lua`)

### Fixed
- [x] CharInfo liest Equipment-Daten jetzt auch aus dem lokalen Memory-Buffer (`equip._mem.snapshot`), wenn der Char-Store noch nicht verfuegbar ist. (Datei: `GMS/Modules/CharInfo.lua`)
- [x] Equipment-Buffer wird bei fehlendem Store automatisch gepollt und spaeter in den Char-Store geflusht. (Datei: `GMS/Modules/Equipment.lua`)
- [x] One-Time-Reset gegen Reload-Wipe-Loops abgesichert: wenn Schema bereits migriert ist, wird der Hard-Reset nicht erneut ausgefuehrt und der Marker nur nachgezogen. (Datei: `GMS/Core/Database.lua`)

### Rules/Infra
- [x] Unreleased-Abschnitt nach Release `1.4.6` fuer die naechste Iteration zurueckgesetzt.
- [x] METADATA-Patchversionen gemaess Project Rules erhoeht: `Equipment 1.3.8`, `CharInfo 1.0.11`, `Raids 1.2.8`. (Dateien: `GMS/Modules/Equipment.lua`, `GMS/Modules/CharInfo.lua`, `GMS/Modules/Raids.lua`)
- [x] METADATA-Patchversionen gemaess Project Rules erhoeht: `ModuleStates 1.1.3`, `Logs 1.1.21`. (Dateien: `GMS/Core/ModuleStates.lua`, `GMS/Core/Logs.lua`)
- [x] METADATA-Patchversion gemaess Project Rules erhoeht: `Database 1.1.6`. (Datei: `GMS/Core/Database.lua`)
- [x] METADATA-Patchversion gemaess Project Rules erhoeht: `Raids 1.2.9`. (Datei: `GMS/Modules/Raids.lua`)
- [x] METADATA-Patchversion gemaess Project Rules erhoeht: `Roster 1.0.24`. (Datei: `GMS/Modules/Roster.lua`)

## Last Release Snapshot

- Version: `1.4.6`
- Date: `2026-02-15`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
