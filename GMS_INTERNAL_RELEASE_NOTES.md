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
- [x] Roster/Comm: Baseline-Sync umgesetzt mit Login-Announce (`ANN`), Peer-Response (`RESP`), Domain-Nachforderung (`NEED`/`HAVE`) und gezieltem Peer-Fetch (Top-3 Quellen, 8s Timeout, 30s Request-Cooldown). (GMS/Modules/Roster.lua, GMS/Core/Comm.lua)
- [x] Sync-Baseline als Projektdokumentation ergänzt (`GMS_PLAYER_SYNC_BASELINE.md`). (GMS_PLAYER_SYNC_BASELINE.md)

### Changed
- [x] CharInfo: Kontextansicht nutzt jetzt persistierten Sync-Cache (`CHARINFO_SYNC`) mit Fallback auf lokale Char-Daten und aktiver Sync-Anforderung je Domain (`roster_meta`, `MYTHICPLUS_V1`, `RAIDS_V1`, `EQUIPMENT_V1`). (GMS/Modules/CharInfo.lua, GMS/Core/Comm.lua)
- [x] CharInfo: Responsive Karten-Layout und dynamische Breitenberechnung für kleine Fenster/Einspaltenansicht verbessert. (GMS/Modules/CharInfo.lua)
- [x] AccountInfo: Twink-/Accountanzeige nutzt neben `guild-verified` jetzt einen robusten `stored`-Fallback, damit gespeicherte Verknüpfungen auch ohne aktuellen Roster-Treffer angezeigt werden. (GMS/Modules/AccountInfo.lua, GMS/Modules/CharInfo.lua)

### Fixed
- [x] Comm: Checksum-Mismatch bei Sync-Paketen wird im Kompatibilitätsmodus akzeptiert und Warnungen werden throttled statt Spam. (GMS/Core/Comm.lua)
- [x] Logs: Humanisierung und Lokalisierung für neue Comm-Logmeldungen ergänzt (manuelle Sync-Requests, Checksum-Kompatibilitätsmeldungen). (GMS/Core/Logs.lua, GMS/Locales/enUS.lua, GMS/Locales/deDE.lua)
- [x] Logs: Layout-Edge-Cases bei Detail-Button/leerem Text sowie Reflow nach Render aktualisiert. (GMS/Core/Logs.lua)
- [x] CharInfo: Fehlende Lokalisierungs-Keys für statische Raidnamen/-beschreibungen ergänzt. (GMS/Locales/enUS.lua, GMS/Locales/deDE.lua, GMS/Modules/CharInfo.lua)
- [x] Logs/Comm: Sync-Record-Keys mit GUID werden in der Comm-Humanisierung als `Name-Realm` in Klassenfarbe aufgelöst (mit GUID-Fallback). (GMS/Core/Logs.lua)

### Rules/Infra
- [ ] (noch keine Eintraege)

## Last Release Snapshot

- Version: `1.4.9`
- Date: `2026-02-18`
- Source: `GMS/Core/Changelog.lua` -> `RELEASES[1]`
