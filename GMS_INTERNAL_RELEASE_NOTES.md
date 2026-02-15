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
- [x] Equipment-Parsing erweitert: Ausruestungs-Slots werden jetzt als strukturierte Item-Daten (itemString/itemId/enchant/gems/bonusIds/itemLevel) erfasst und deterministisch geordnet gespeichert (`GMS/Modules/Equipment.lua`).
- [x] Raids-Scan stabilisiert: Lifecycle/Event-Registrierung vervollstaendigt (Login/EnteringWorld/Encounter/BossKill) und Store-Zugriffe im Ingest-Pfad gehaertet (`GMS/Modules/Raids.lua`).
- [x] MythicPlus-Scan normalisiert: API-Fallbacks und Run-Normalisierung fuer intime/overtime eingebaut, inklusive stabiler Sortierung der Dungeonliste (`GMS/Modules/MythicPlus.lua`).
- [x] Roster-Metaquellen erweitert: Roster nutzt fuer lokale Meta-Broadcasts bevorzugt gespeicherte Modul-Daten aus Equipment/MythicPlus/Raids statt nur Live-API-Fallbacks (`GMS/Modules/Roster.lua`).

### Fixed
- [x] Equipment-Persistenz/Verteilung korrigiert: Snapshot-Digest mit Change-Detection eingefuehrt und Guild-Sync via Comm (`EQUIPMENT_V1`) nur bei echten Aenderungen aktiviert; Memory-Buffer-Flush bei spaeter Options-Initialisierung ergaenzt (`GMS/Modules/Equipment.lua`).
- [x] Raids-Guild-Sync korrigiert: Digest-basierte Aenderungserkennung und Comm-Publish (`RAIDS_V1`) fuer neue Lockout-/Progress-Daten hinzugefuegt (`GMS/Modules/Raids.lua`).
- [x] MythicPlus-Guild-Sync korrigiert: Digest-basierte Aenderungserkennung und Comm-Publish (`MYTHICPLUS_V1`) fuer aktualisierte Score-/Dungeon-Daten hinzugefuegt (`GMS/Modules/MythicPlus.lua`).
- [x] Roster-Online-Broadcast gehaertet: Beim eigenen Online-Wechsel/Enter-World/Guild-Update wird die aktuelle GMS-Meta aktiv in die Gilde gesendet, damit Versionsanzeige im Roster schneller aktuell ist (`GMS/Modules/Roster.lua`).
- [x] Roster-Datenintegration erweitert: Comm-Record-Listener fuer `EQUIPMENT_V1`, `MYTHICPLUS_V1` und `RAIDS_V1` mappen gespeicherte ItemLevel/Mythic+/Raid-Infos direkt in die Roster-Metadaten pro GUID (`GMS/Modules/Roster.lua`).

### Rules/Infra
- [ ] (leer)

## Last Release Snapshot

- Version: `1.4.3`
- Date: `2026-02-15`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
