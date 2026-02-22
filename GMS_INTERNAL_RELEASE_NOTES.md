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
- [ ] (noch keine Eintraege)

### Changed
- [x] CharInfo auf gestaffeltes UI-Rendering umgestellt (frameweise Card-Build, Build-Token-Abbruch) zur Reduktion von UI-Spikes beim Seitenaufbau.  
  Dateien: `GMS/Modules/CharInfo.lua`
- [x] Logs-UI auf inkrementelles Update umgestellt: neue Einträge werden oben angefügt statt Voll-Rebuild bei jeder Änderung; Voll-Render bleibt für Filter/Resize/Initial.  
  Dateien: `GMS/Core/Logs.lua`
- [x] UI-Footer um Live-Metrik erweitert und auf GMS-spezifische Anzeige reduziert (`GMS MB` + Prozentanteil am gesamten Addon-Speicher).  
  Dateien: `GMS/Core/UI.lua`, `GMS/Locales/enUS.lua`, `GMS/Locales/deDE.lua`
- [x] Comm/Roster-Dispatch entkoppelt (asynchrone Listener-/Chunk-Verarbeitung, batchweise Hydrierung) und Missing-Domain-Fetches weiter gestaffelt.  
  Dateien: `GMS/Core/Comm.lua`, `GMS/Modules/Roster.lua`
- [x] Dashboard-Statusanzeige bereinigt und Footer-Metrik-Textlayout/Typografie auf einheitliche Darstellung mit lokalisierbaren Label-Keys umgestellt.  
  Dateien: `GMS/Core/Dashboard.lua`, `GMS/Core/UI.lua`, `GMS/Locales/enUS.lua`, `GMS/Locales/deDE.lua`

### Fixed
- [x] CharInfo-Context-Sync reduziert auf einmaligen Bootstrap-Request pro Ziel/Öffnung, um Request-Bursts und Whisper-Spam zu vermeiden.  
  Dateien: `GMS/Modules/CharInfo.lua`
- [x] Mythic+-Portalprüfung in CharInfo auf feste mapId->spellId-Mappings + tatsächliche Spellbook/Known-Checks umgestellt; Name-/Spellbook-Fallback entfernt.  
  Dateien: `GMS/Modules/CharInfo.lua`
- [x] Equipment-Lag bei Gear-Wechsel reduziert: slotbasierter Teilsync statt Vollscan pro Event, plus sanftere Scan-Batches.  
  Dateien: `GMS/Modules/Equipment.lua`
- [x] UI-Footer-Metrik robust gemacht (kein Nil-Call mehr auf Gesamt-AddOn-Memory-Berechnung im Laufzeitpfad).  
  Dateien: `GMS/Core/UI.lua`
- [x] CharInfo rendert wieder vollständig (kein Hängen auf nur einer Karte/Feld durch verzögerten Build-Pfad); Deferred-Rendering standardmäßig deaktiviert.  
  Dateien: `GMS/Modules/CharInfo.lua`
- [x] UI-CPU-Metrikpfad auf Retail-kompatible API-Reihenfolge erweitert (`C_AddOns.*` bevorzugt, Legacy-Fallback) und Footer-CPU-Berechnung/Fallbacks für stabile Anzeige nachgeschärft.  
  Dateien: `GMS/Core/UI.lua`

### Rules/Infra
- [x] Projektregeln erweitert: Retail-First-API-Pflicht (`C_*` bevorzugt, Legacy nur Fallback) sowie verbindliche Beachtung von `GMS_INTERNAL_RELEASE_NOTES.md` und `GMS_PLAYER_SYNC_BASELINE.md`.  
  Dateien: `GMS_PROJECT_RULES.md`

## Last Release Snapshot

- Version: `1.5.0`
- Date: `2026-02-18`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
