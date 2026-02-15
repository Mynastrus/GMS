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
- [ ] (leer)

### Fixed
- [x] Raids-EJ-Readiness korrigiert: `ejApiPresent()` validiert jetzt die tatsaechlich verwendeten `EJ_*`-Funktionen statt nur `C_EncounterJournal`; zusaetzlich Rebind der EJ-API-Referenzen nach `LoadAddOn`, um `nil`-Upvalue-Calls wie bei `EJ_GetNumEncounters` zu verhindern (`GMS/Modules/Raids.lua`).
- [x] Permissions-UI stabilisiert: Tab-Rendering auf `Fill`-Layout verankert, gueltige Tab-Selektion erzwungen und Tab-Inhalt ueber `SelectTab`/Callback initialisiert; Scroll-Container im Tab-Content auf `List` umgestellt, damit Inhalte nicht gequetscht dargestellt werden (`GMS/Core/Permissions.lua`).
- [x] Logs-UI Initial-Layout stabilisiert: erste Render-Pass nutzt jetzt zusaetzlich Root-Breite als Fallback und fuehrt einen verzoegerten Reflow/Re-Render nach dem Seitenaufbau aus, damit die Spaltenbreiten bereits ohne manuelles Resize korrekt sind (`GMS/Core/Logs.lua`).

### Rules/Infra
- [ ] (leer)

## Last Release Snapshot

- Version: `1.4.4`
- Date: `2026-02-15`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
