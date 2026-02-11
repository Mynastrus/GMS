# 🧩 GMS – Guild Management Suite

**GMS** is a modular **World of Warcraft Addon** built on the **Ace3 framework**, designed with a focus on **clean architecture**, **extensibility**, and **seamless UI integration**.

---

## 🇺🇸 English Documentation

### ✨ Features

- 🔌 **Modular Ace3 Architecture**
  - Strict separation of Core, Extensions (`EXT`), and Modules (`MOD`).
  - Standardized metadata and automated versioning.
  - Decoupled logic using AceEvent signals.

- 🖥️ **Custom UI Shell**
  - Based on Blizzard's `ButtonFrameTemplate`.
  - Integrated AceGUI pages and navigation dock.
  - Persistent window states (size/position) via AceDB.

- 📊 **Current Modules**
  - 👥 **Roster**: Advanced guild member overview with customizable columns.
  - 🏰 **Raids**: Encounter Journal integration with progression tracking.
  - ⚔️ **Mythic Plus**: Season score and dungeon best tracking.
  - 🎒 **Equipment**: Item level analysis and character gear snapshots.
  - 👤 **CharInfo**: Player snapshots and cross-module navigation context.

- 🛠️ **Integrated Extensions**
  - 💬 **ChatLinks**: Clickable chat prefixes and enhanced item tooltips.
  - 📜 **Logging Console**: Real-time debug UI with buffered logging system.
  - ⚙️ **Centralized Settings**: Unified UI for all configuration needs.

### 📁 Project Structure

```text
GMS/
├─ Core/
│  ├─ Core.lua            # Addon Entry (CORE)
│  ├─ Database.lua        # Data persistence (EXT)
│  ├─ UI.lua              # UI Framework (EXT)
│  ├─ Logs.lua            # Debugging system (EXT)
│  ├─ ChatLinks.lua       # Chat enhancements (EXT)
│  ├─ ModuleStates.lua    # Lifecycle & Registry (EXT)
│  ├─ Settings.lua        # Configuration UI (EXT)
│  └─ SlashCommands.lua   # Command handling (EXT)
├─ Modules/
│  ├─ Roster.lua          # Guild management (MOD)
│  ├─ Raids.lua           # Raid progression (MOD)
│  ├─ MythicPlus.lua      # Dungeon tracking (MOD)
│  ├─ Equipment.lua       # Gear analysis (MOD)
│  └─ CharInfo.lua        # Character snapshots (MOD)
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
  - Strikte Trennung von Core, Extensions (`EXT`) und Modulen (`MOD`).
  - Standardisierte Metadaten und automatische Versionierung.
  - Lose Kopplung durch AceEvent Signale.

- 🖥️ **Eigene UI-Shell**
  - Basierend auf Blizzards `ButtonFrameTemplate`.
  - Integrierte AceGUI-Seiten und Navigations-Dock.
  - Persistente Fensterzustände (Größe/Position) via AceDB.

- 📊 **Aktuelle Module**
  - 👥 **Roster**: Erweiterte Gildenübersicht mit anpassbaren Spalten.
  - 🏰 **Raids**: Encounter Journal Integration mit Fortschritts-Tracking.
  - ⚔️ **Mythic Plus**: Anzeige von Season-Score und besten Dungeon-Runs.
  - 🎒 **Equipment**: Analyse des Item-Levels und Ausrüstungs-Snapshots.
  - 👤 **CharInfo**: Charakter-Snapshots und modulübergreifender Navigations-Kontext.

- 🛠️ **Integrierte Erweiterungen (EXT)**
  - 💬 **ChatLinks**: Klickbare Chat-Präfixe und verbesserte Item-Tooltips.
  - 📜 **Logging Console**: Echtzeit-Debug UI mit gepuffertem Log-System.
  - ⚙️ **Zentrale Einstellungen**: Ein einheitliches Menü für alle Konfigurationen.

### 📁 Projektstruktur

```text
GMS/
├─ Core/
│  ├─ Core.lua            # Addon Einstiegspunkt (CORE)
│  ├─ Database.lua        # Datenpersistenz (EXT)
│  ├─ UI.lua              # UI Framework (EXT)
│  ├─ Logs.lua            # Logging System (EXT)
│  ├─ ChatLinks.lua       # Chat-Erweiterungen (EXT)
│  ├─ ModuleStates.lua    # Lifecycle & Registrierung (EXT)
│  ├─ Settings.lua        # Konfigurations-Oberfläche (EXT)
│  └─ SlashCommands.lua   # Befehlsverwaltung (EXT)
├─ Modules/
│  ├─ Roster.lua          # Gildenverwaltung (MOD)
│  ├─ Raids.lua           # Raid-Fortschritt (MOD)
│  ├─ MythicPlus.lua      # Dungeon-Tracking (MOD)
│  ├─ Equipment.lua       # Gear-Analyse (MOD)
│  └─ CharInfo.lua        # Charakter-Snapshots (MOD)
└─ GMS_PROJECT_RULES.md   # Kodierungsrichtlinien
```

### ⌨️ Befehle

- `/gms` - Öffnet die Hauptoberfläche.
- `/gms config` - Springt direkt in die Einstellungen.
- `/gms log` - Öffnet die Logging-Konsole.

---

## 📜 Development Standards

This project follows strict coding rules defined in [GMS_PROJECT_RULES.md](GMS_PROJECT_RULES.md).

### 🔑 Key Requirements:
- **METADATA**: Every file must contain a `METADATA` table.
- **Logging**: Mandatory use of `LOCAL_LOG` for buffered debugging.
- **Module Lifecycle**: Every module and extension must signal readiness via `GMS:SetReady` and `GMS:SetNotReady` during their lifecycle.
- **Versioning**: Consistent use of SemVer, updated with every change.
