# GMS - Guild Management System

Organize your guild with a modular in-game control center:
roster intelligence, character profiles, raid and Mythic+ visibility, account links, logs, and release notes in one UI.

Discord: https://discord.gg/4CGEtqayvT

---

## DE - Deutsch

### Ueberblick

GMS ist ein modulares Guild-Management-Addon fuer World of Warcraft.
Es verbindet lokale Datenhaltung, gildenweite Synchronisierung und eine eigene Seiten-UI zu einer zentralen Arbeitsoberflaeche fuer Organisation und Uebersicht.

### Kernvorteile

- Modulare Architektur mit klaren Rollen (`CORE`, `EXT`, `MOD`)
- Eigene UI mit Navigation, Docks, Statuszeile und Dashboard
- Fokus auf echte Gildenablaeufe statt Einzel-Feature-Sammlung
- Lokale Persistenz plus kontrollierte Guild-Sync-Domaenen
- Integriertes Logging, Changelog und Slash-Command-Steuerung

### Module und Inhalte

| Bereich | Funktion |
|---|---|
| Dashboard | Systemstatus, Modul-/Extension-Readiness, zentraler Einstieg |
| Roster | Mitgliederuebersicht mit Filtern, Sortierung, Tooltips und Direktaktionen |
| CharInfo | Charakterprofil mit Equipment, Raids, Mythic+, Talenten und PvP |
| GuildInfo | Kompakter Gildenkontext direkt in der UI |
| GuildLog | Gildenbezogene Ereignisse und Aktivitaeten im Zugriff |
| AccountInfo | Freiwillige Profildaten und Main-/Twink-Beziehungen |
| Raids | Lockout- und Fortschrittsdarstellung fuer relevante Inhalte |
| MythicPlus | Schluessel-/Dungeon-Daten fuer schnelle Leistungsuebersicht |
| Changelog | Ingame-Releasehistorie (EN/DE) fuer transparente Updates |
| Logs | Technische und funktionale Nachvollziehbarkeit im Betrieb |

### Schnellstart

1. Addon installieren und Spiel neu starten.
2. Mit `/gms` die Hauptoberflaeche oeffnen.
3. Im Roster die ersten Charakterdaten pruefen.
4. Bei Bedarf mit Guildies synchronisieren lassen (module-/domain-abhaengig).
5. Release Notes unter `/gms changelog` einsehen.

### Wichtige Befehle

| Befehl | Zweck |
|---|---|
| `/gms` | Hauptfenster oeffnen |
| `/gms ?` | Kurzuebersicht der Befehle anzeigen |
| `/gms changelog` | Release Notes oeffnen |
| `/gms roster` | Roster direkt oeffnen |

### Daten, Sync und Hinweise

- Gespeichert wird ueber SavedVariables.
- Nicht jede Information wird zwingend gildenweit geteilt; Sync ist domain-/modulbasiert.
- AccountInfo-Felder sind freiwillig.
- Die gueltige Addon-Version steht in `GMS/GMS.toc`.
- Zielplattform ist WoW Retail.

---

## EN - English

### Overview

GMS is a modular guild management addon for World of Warcraft.
It combines local persistence, guild-wide synchronization, and a dedicated multi-page UI into one operational hub for guild leadership and members.

### Why GMS

- Modular architecture with explicit roles (`CORE`, `EXT`, `MOD`)
- Dedicated UI with navigation, dock icons, status text, and dashboard
- Built around real guild workflows, not isolated utility features
- Local storage plus controlled guild-sync domains
- Built-in logs, changelog, and slash command controls

### Modules and Scope

| Area | Purpose |
|---|---|
| Dashboard | System status and module/extension readiness overview |
| Roster | Guild member list with filters, sorting, tooltips, and direct actions |
| CharInfo | Character profile with equipment, raids, Mythic+, talents, and PvP |
| GuildInfo | Compact guild context inside the UI |
| GuildLog | Guild-related activity and event visibility |
| AccountInfo | Optional profile data and main/alt relationships |
| Raids | Lockout/progress visibility for relevant raid content |
| MythicPlus | Key and dungeon metrics for quick performance checks |
| Changelog | In-game EN/DE release history |
| Logs | Operational traceability and diagnostics |

### Quick Start

1. Install the addon and restart the game.
2. Open the main interface with `/gms`.
3. Review initial guild data in the roster page.
4. Let sync domains hydrate data from guild peers where available.
5. Open release notes with `/gms changelog`.

### Commands

| Command | Action |
|---|---|
| `/gms` | Open main window |
| `/gms ?` | Show command help |
| `/gms changelog` | Open release notes |
| `/gms roster` | Open roster directly |

### Data, Sync and Notes

- Data is stored via SavedVariables.
- Sync behavior depends on module/domain scope.
- AccountInfo fields are optional.
- Current addon version is defined in `GMS/GMS.toc`.
- Primary target platform is WoW Retail.
