# 🧩 GMS – Guild Management Suite

**GMS** is a modular **World of Warcraft Addon** built on the **Ace3 framework**, designed with a focus on **clean architecture**, **extensibility**, and **seamless UI integration**.

---

## 🇺🇸 English Documentation

### ✨ Features

- 🔌 **Modular Ace3 Architecture**
  - Strict separation of Core, UI, and Modules.
  - Standardized metadata (`CORE`, `EXT`, `MOD`).
  - Decoupled logic using AceEvent signals.

- 🖥️ **Custom UI Shell**
  - Based on Blizzard's `ButtonFrameTemplate`.
  - Integrated AceGUI pages and navigation dock.
  - Persistent window states (size/position) via AceDB.

- 📊 **Current Modules**
  - 👥 **Roster**: Advanced guild member overview with customizable columns.
  - 🏰 **Raids**: Encounter Journal integration with progression tracking (Current/Best).
  - ⚔️ **Mythic Plus**: Personal score and dungeon best tracking.
  - 🎒 **Equipment**: Item level analysis and character gear snapshots.
  - 💬 **ChatLinks**: Clickable chat prefixes and enhanced item tooltips.
  - 📜 **Logging Console**: Real-time debug UI with buffered logging system.

- ⚙️ **Centralized Settings**
  - One unified UI for all module and extension configurations.

### 📁 Project Structure

```text
GMS/
├─ Core/
│  ├─ Core.lua            # Addon Entry (CORE)
│  ├─ Database.lua        # Data persistence (EXT)
│  ├─ UI.lua              # UI Framework (EXT)
│  └─ Logs.lua            # Debugging system (EXT)
├─ Modules/
│  ├─ Roster.lua          # Guild management (MOD)
│  ├─ Raids.lua           # Raid progression (MOD)
│  └─ Equipment.lua       # Gear analysis (MOD)
└─ GMS_PROJECT_RULES.md   # Coding standards
```

### ⌨️ Commands

- `/gms` - Open the main user interface.
- `/gms config` - Jump directly to the settings.
- `/gms log` - Open the real-time logging console.

---

## 🇩🇪 Deutsche Dokumentation

### ✨ Features

- 🔌 **Modulare Ace3 Architektur**
  - Strikte Trennung von Core, UI und Modulen.
  - Standardisierte Metadaten (`CORE`, `EXT`, `MOD`).
  - Lose Kopplung durch AceEvent Signale.

- 🖥️ **Eigene UI-Shell**
  - Basierend auf Blizzards `ButtonFrameTemplate`.
  - Integrierte AceGUI-Seiten und Navigations-Dock.
  - Persistente Fensterzustände (Größe/Position) via AceDB.

- 📊 **Aktuelle Module**
  - 👥 **Roster**: Erweiterte Gildenübersicht mit anpassbaren Spalten.
  - 🏰 **Raids**: Encounter Journal Integration mit Fortschritts-Tracking.
  - ⚔️ **Mythic Plus**: Anzeige von Score und besten Dungeon-Runs.
  - 🎒 **Equipment**: Analyse des Item-Levels und Ausrüstungs-Snapshots.
  - 💬 **ChatLinks**: Klickbare Chat-Präfixe und verbesserte Item-Tooltips.
  - 📜 **Logging Console**: Echtzeit-Debug UI mit gepuffertem Log-System.

- ⚙️ **Zentrale Einstellungen**
  - Ein einheitliches Menü für alle Modul- und Erweiterungskonfigurationen.

### ⌨️ Befehle

- `/gms` - Öffnet die Hauptoberfläche.
- `/gms config` - Springt direkt in die Einstellungen.
- `/gms log` - Öffnet die Logging-Konsole.

---

## 📜 Development Standards

This project follows strict coding rules defined in [GMS_PROJECT_RULES.md](GMS_PROJECT_RULES.md).
Any contribution must adhere to the defined `METADATA` and `LOCAL_LOG` standards.
