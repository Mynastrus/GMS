# GMS - Guild Management System

## Deutsch

GMS ist ein modulares Guild-Management-Addon fuer World of Warcraft.
Es kombiniert zentrale Verwaltungsfunktionen mit einer eigenen UI, synchronisierten Gildendaten und klar getrennten Modulen.

### Warum GMS?

- Modulare Architektur (`CORE`, `EXT`, `MOD`) fuer saubere Erweiterbarkeit
- Eigene UI mit Seiten, Dock-Icons und integriertem Dashboard
- Gildenfokus: Roster, Charakterdaten, Raid- und Mythic+-Uebersichten
- Lokale Daten + Guild-Sync, damit wichtige Infos fuer die Gilde verfuegbar sind
- Integriertes Logging, Changelog und Slash-Command-System

### Hauptfunktionen

- **Roster**
  - Gildenmitglieder mit Filtern, Sortierung und Zusatzdaten
  - Kontextaktionen (z. B. Whisper/Invite)
  - Account-Verknuepfungen und Tooltip-Erweiterungen

- **CharInfo**
  - Kompakte Charakteransicht mit Kartenlayout
  - Mythic+, Raids, Equipment, Talente, PvP
  - Klickbare Elemente (z. B. Adventure Guide bei passenden Inhalten)

- **AccountInfo**
  - Freiwillige Profilangaben (Name, Geburtstag, Geschlecht)
  - Main-Charakter-Auswahl innerhalb der Gilde
  - Austausch der Daten innerhalb der Gilde

- **Raids / MythicPlus / Equipment**
  - Snapshot-Erfassung pro Charakter
  - Synchronisierung relevanter Daten ueber die Gilde
  - Stabiler Fallback fuer verfuegbare API-/Datenquellen

### Bedienung

- `/gms` -> Hauptfenster oeffnen
- `/gms ?` -> Hilfe anzeigen
- `/gms changelog` -> Release Notes anzeigen

### Installation

1. Addon installieren (CurseForge App oder manuell).
2. Sicherstellen, dass der Ordner `GMS` in `Interface/AddOns` liegt.
3. Im Spiel mit `/reload` neu laden.

### Kompatibilitaet und Daten

- Aktive Interface-Version siehe `GMS/GMS.toc`.
- Daten werden ueber SavedVariables gespeichert.
- Bestimmte Modulinfos koennen innerhalb der Gilde synchronisiert werden.
- AccountInfo-Felder sind freiwillig und werden nur fuer Gildenfunktionen genutzt.

### Community / Support

Wenn du Hilfe brauchst, Feedback geben willst oder Ideen hast, komm auf unseren Discord:

**Discord:** https://discord.gg/4CGEtqayvT

---

## English

GMS is a modular guild management addon for World of Warcraft.
It combines core management workflows with a dedicated UI, synchronized guild data, and cleanly separated modules.

### Why GMS?

- Modular architecture (`CORE`, `EXT`, `MOD`) for clean extensibility
- Dedicated UI with pages, dock icons, and an integrated dashboard
- Guild-focused workflows: roster, character data, raid and Mythic+ overviews
- Local data plus guild sync so important information is available across the guild
- Built-in logging, changelog, and slash command system

### Core Features

- **Roster**
  - Guild member overview with filters, sorting, and extended data
  - Context actions (e.g. whisper/invite)
  - Account-link handling and enhanced tooltips

- **CharInfo**
  - Compact character view with card-based layout
  - Mythic+, raids, equipment, talents, PvP
  - Clickable interactions (e.g. Adventure Guide for supported content)

- **AccountInfo**
  - Optional profile data (name, birthday, gender)
  - Main-character selection within the guild
  - Guild-shared profile data exchange

- **Raids / MythicPlus / Equipment**
  - Per-character snapshot collection
  - Synchronization of relevant data across guild members
  - Stable fallback behavior for available API/data sources

### Commands

- `/gms` -> open main window
- `/gms ?` -> show help
- `/gms changelog` -> open release notes

### Installation

1. Install the addon (CurseForge App or manually).
2. Ensure the `GMS` folder is placed in `Interface/AddOns`.
3. Reload the UI in-game with `/reload`.

### Compatibility and Data

- Active interface version is defined in `GMS/GMS.toc`.
- Data is stored via SavedVariables.
- Selected module data can be synchronized within the guild.
- AccountInfo fields are optional and used for guild features only.

### Community / Support

Need help, want to share feedback, or have ideas?
Join our Discord:

**Discord:** https://discord.gg/4CGEtqayvT

