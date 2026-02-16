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
- [x] Roster erweitert um globale Account-Char-Erfassung (`db.global.accountLinks.chars`) und gildenverifizierte Aufloesung gleicher Account-Chars ueber GUID/GuildKey. (Datei: `GMS/Modules/Roster.lua`)
- [x] CharInfo-Accountkarte auf neue Roster-Account-Link-API umgestellt; Eintraege zeigen Name-Realm, Klassenfarbe, Level/Status und sind klickbar zum direkten Oeffnen der jeweiligen CharInfo. (Datei: `GMS/Modules/CharInfo.lua`)
- [x] Raids-Difficulty-Erkennung vereinheitlicht; Abkuerzungen bleiben `LFR`, `N`, `H`, `M` und zusaetzlich wird deutsches `Mytisch` als Alias fuer Mythic/Mythisch erkannt. (Datei: `GMS/Modules/Raids.lua`)
- [x] Release-Workflow erweitert: nach erfolgreichem CurseForge-Upload werden automatisch DE/EN Discord-Announcements ueber Secrets (`DISCORD_WEBHOOK_RELEASE_DE`, `DISCORD_WEBHOOK_RELEASE_EN`) mit CurseForge-Link gepostet. (Datei: `.github/workflows/upload-to-curseforge.yml`)
- [x] Raids-Statistik-Anreicherung (Best aus Charakterstatistiken) wird beim Login/Entering-World nicht mehr synchron ausgefuehrt, sondern verzoegert geplant und mit Cooldown begrenzt. (Datei: `GMS/Modules/Raids.lua`)
- [x] CharInfo-Raidkarte erweitert: lokaler Spieler nutzt jetzt Fallback-Kette fuer `Best` (`Local RAIDS` -> `Synced RAIDS_V1` -> `roster_meta`/Roster-Cache inkl. `best_in_raid`), damit Best-Werte auch ohne frische Detailzeilen sichtbar sind. (Datei: `GMS/Modules/CharInfo.lua`)

### Fixed
- [x] CharInfo liest Equipment-Daten jetzt auch aus dem lokalen Memory-Buffer (`equip._mem.snapshot`), wenn der Char-Store noch nicht verfuegbar ist. (Datei: `GMS/Modules/CharInfo.lua`)
- [x] Equipment-Buffer wird bei fehlendem Store automatisch gepollt und spaeter in den Char-Store geflusht. (Datei: `GMS/Modules/Equipment.lua`)
- [x] One-Time-Reset gegen Reload-Wipe-Loops abgesichert: wenn Schema bereits migriert ist, wird der Hard-Reset nicht erneut ausgefuehrt und der Marker nur nachgezogen. (Datei: `GMS/Core/Database.lua`)
- [x] Lua-Fehler in `Raids` behoben: Achievement-Kategorie-Handling fuer `GetCategoryList()` robuster gemacht und `GetCategoryNumAchievements` nur mit gueltiger Signatur aufgerufen. (Datei: `GMS/Modules/Raids.lua`)
- [x] Login-Freeze reduziert: schweres Raid-Statusauslesen aus Charakterstatistiken wird in der Startphase ausgelassen und spaeter nachgeholt. (Datei: `GMS/Modules/Raids.lua`)
- [x] CharInfo zeigt bei vorhandenem Raid-`Best` keine irrefuehrende "No raid progress data"-Warnung mehr, wenn nur Detailzeilen fehlen. (Datei: `GMS/Modules/CharInfo.lua`)

### Rules/Infra
- [x] Unreleased-Abschnitt nach Release `1.4.6` fuer die naechste Iteration zurueckgesetzt.
- [x] METADATA-Patchversionen gemaess Project Rules erhoeht: `Equipment 1.3.8`, `CharInfo 1.0.11`, `Raids 1.2.8`. (Dateien: `GMS/Modules/Equipment.lua`, `GMS/Modules/CharInfo.lua`, `GMS/Modules/Raids.lua`)
- [x] METADATA-Patchversionen gemaess Project Rules erhoeht: `ModuleStates 1.1.3`, `Logs 1.1.21`. (Dateien: `GMS/Core/ModuleStates.lua`, `GMS/Core/Logs.lua`)
- [x] METADATA-Patchversion gemaess Project Rules erhoeht: `Database 1.1.6`. (Datei: `GMS/Core/Database.lua`)
- [x] METADATA-Patchversion gemaess Project Rules erhoeht: `Raids 1.2.9`. (Datei: `GMS/Modules/Raids.lua`)
- [x] METADATA-Patchversion gemaess Project Rules erhoeht: `Roster 1.0.24`. (Datei: `GMS/Modules/Roster.lua`)
- [x] METADATA-Patchversion gemaess Project Rules erhoeht: `Raids 1.2.10`. (Datei: `GMS/Modules/Raids.lua`)
- [x] METADATA-Patchversionen gemaess Project Rules erhoeht: `Roster 1.0.25`, `CharInfo 1.0.12`. (Dateien: `GMS/Modules/Roster.lua`, `GMS/Modules/CharInfo.lua`)
- [x] Release-Regeln erweitert: verpflichtende Discord-Release-Posts auf separaten DE/EN-Webhooks, jeweils mit CurseForge-Link. (Dateien: `AGENTS.md`, `GMS_PROJECT_RULES.md`)
- [x] Sicherheitsanpassung: Klartext-Discord-Webhooks aus Regeln entfernt und durch Secret-Namen (`DISCORD_WEBHOOK_RELEASE_DE`, `DISCORD_WEBHOOK_RELEASE_EN`) ersetzt. (Dateien: `AGENTS.md`, `GMS_PROJECT_RULES.md`)
- [x] METADATA-Patchversion gemaess Project Rules erhoeht: `Raids 1.2.11`. (Datei: `GMS/Modules/Raids.lua`)
- [x] METADATA-Patchversion gemaess Project Rules erhoeht: `Raids 1.2.12`. (Datei: `GMS/Modules/Raids.lua`)
- [x] METADATA-Patchversion gemaess Project Rules erhoeht: `CharInfo 1.0.13`. (Datei: `GMS/Modules/CharInfo.lua`)

## Last Release Snapshot

- Version: `1.4.6`
- Date: `2026-02-15`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
