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
- [x] Neuer Slash-Subcommand für Hard-Reset: `/gms dbwipe` (Alias: `dbreset`, `resetdb`, `wipe`).

### Changed
- [x] `Database_ResetAll` erweitert: leert jetzt zusätzlich `GMS_UIDB` und `GMS_Changelog_DB` für wirklich sauberen Reset.
- [x] One-Time-Release-Reset in `Core/Database.lua` ergänzt (versionsgesteuert über `ONE_TIME_RESET_TARGET_VERSION`, aktuell `1.4.6`).
- [x] One-Time-Reset hinterlegt Marker in `GMS_DB.global` (`oneTimeHardResetAppliedVersion`, `oneTimeHardResetAppliedAt`) zur sicheren Einmal-Ausführung.
- [x] CharInfo-Seite auf kartenbasiertes Grid-Layout umgebaut: feste 2-Spalten-Verteilung (links Raid/M+/PvP, rechts Equipment/Talente) plus freie Karten darunter.
- [x] CharInfo nutzt jetzt ScrollFrame, dynamische Breiten und Auto-Refresh bei Datenänderungen (Ticker mit Signaturvergleich).
- [x] Equipment-Liste in CharInfo zeigt anklickbare Itemlinks mit Tooltip (`InteractiveLabel`, `GameTooltip:SetHyperlink`, `HandleModifiedItemClick`).
- [x] CharInfo-Datenbindung erweitert: klare No-Data-Hinweise, Placeholder für PvP/Talente/Account-Charaktere und vorbereitete `cardOrder`-Basis für spätere individuelle Anordnung.
- [x] CharInfo-Layout weiter verfeinert: Header-Meta in kompakter 2-Spalten-Darstellung, Top-Alignment der Hauptspalten, resize-stabile Breitenaktualisierung ohne automatisches Zurücksetzen der Fenstergröße, sowie robuster Equipment-Fallback direkt nach Reload.
- [x] CharInfo-Header erweitert: rechter Aktions-Button (WoW-Icon) mit Kontextmenü für Standardaktionen (Anflüstern, Name kopieren, Gruppe einladen, Anvisieren per Slash).
- [x] CharInfo-Layoutbreiten für die obere 2-Spalten-Sektion auf relative Breiten umgestellt, damit rechte Spalte bündig zu Full-Width-Karten endet.
- [x] Fraktionsanzeige in CharInfo lokalisiert (z. B. `Alliance` -> `Allianz` unter `deDE`).
- [x] CharInfo-Header und Seitenlayout weiter bereinigt: Aktions-/Kontext-Buttons in der Content-Fläche entfernt, Header-Metadaten verdichtet (nur Werte), Header-Aktionsmenü gestrafft.
- [x] Raids-Modul auf robusten Fallback-Betrieb für 12.x/API-Änderungen erweitert: SavedInstances-first Ingest auch ohne vollständige EJ-Verfügbarkeit, inkl. Name-/Encounter-Fallback-Mapping und Difficulty-Fallback aus `difficultyName`.
- [x] Neuer Slash-Befehl `/gms raids scan` ergänzt, um Scans manuell sofort auszulösen (optional `/gms raids rebuild`).

### Fixed
- [x] Lua-Diagnostics (`undefined-field`) in `Core/Database.lua` beseitigt, indem `_G`-Zugriffe auf optionale SVs via `rawget(_G, "...")` erfolgen.
- [x] `ADDON_ACTION_FORBIDDEN` beim CharInfo-Menüpunkt "Anvisieren" behoben (kein direkter Protected-Call mehr aus Dropdown-Callback).
- [x] `.toc`-Ladefehler korrigiert (`Couldn't open GMS/23`) durch Entfernen einer fehlerhaften Eintragszeile in `GMS/GMS.toc`.
- [x] Syntaxfehler in `Modules/Raids.lua` behoben (`Unexpected symbol 'end'`).

### Rules/Infra
- [ ] (leer)

## Last Release Snapshot

- Version: `1.4.5`
- Date: `2026-02-15`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
