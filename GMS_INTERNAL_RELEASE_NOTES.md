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
- `CURSEFORGE_STARTPAGE.md` komplett neu ausgearbeitet: detaillierte DE/EN-Startseite mit strukturierten Abschnitten, Moduluebersichten, Quick-Start, Command-Tabelle und verbesserten Formatierungen fuer CurseForge.
- `GMS/Core/RaidIds.lua` an den aktuellen Live-Stand angepasst: Midnight-Raids in Journal-/Map-/Boss-Mappings aufgenommen und Retail-Raid-Aliase erweitert.

### Fixed
- `GMS/Core/Changelog.lua`: Auto-Open der Release Notes auf einen einmaligen Session-Start begrenzt, damit sich das Hauptfenster nach `PLAYER_ENTERING_WORLD`-Folgen wie Ladescreens nicht erneut selbst oeffnet.
- `GMS/Modules/CharInfo.lua`: Dungeon-Portal-Handling auf Retail-First-Spellbook-Erkennung und `SecureActionButtonTemplate` umgestellt, damit Mythic+-Teleports auf Live wieder klickbar/castbar sind.

### Rules/Infra
- `GMS_PROJECT_RULES.md` um eine verbindliche Vor-Release-Regel erweitert: Vor jedem echten Release muessen alle Locale-Dateien auf Vollstaendigkeit geprueft und fehlende Keys in der jeweiligen Sprache ergaenzt werden.

## Last Release Snapshot

- Version: `2.0.0`
- Date: `2026-02-26`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
