# 🧩 GMS – Guild Management Suite

**GMS** ist ein modular aufgebautes **World of Warcraft Addon** auf Basis von **Ace3**,  
entwickelt mit Fokus auf **saubere Architektur**, **Erweiterbarkeit** und **stabile UI-Integration**.

Das Projekt dient als **zentrale Plattform** für Gilden-bezogene Tools wie Roster-Übersichten, Charakter-Infos, interne Utilities und zukünftige Management-Features.

---

## ✨ Features

- 🔌 **Modulares Ace3-Addon**
  - Klare Trennung zwischen Core, UI und Modulen
  - Saubere Registrierung über AceAddon Registry

- 🖥️ **Eigenes UI-Framework**
  - Blizzard `ButtonFrameTemplate`
  - Integrierte AceGUI-Pages
  - Rechtes Dock mit Icons & Navigation
  - Persistente Fensterposition & Größe (AceDB)

- 🧱 **Stabile Core-Architektur**
  - Zentrales Logging-Bootstrap
  - Einheitliche Print / Printf-APIs
  - Klare Init- und Lifecycle-Phasen

- 🧩 **Erweiterbar**
  - Module registrieren eigene Pages & UI-Elemente
  - Lose Kopplung zwischen Modulen
  - Keine Abhängigkeit von globalem `addonTable`

---

## 📁 Projektstruktur

```text
GMS/
├─ GMS.lua                # Core Entry (AceAddon Bootstrap)
├─ GMS.toc
│
├─ Core/
│  ├─ UI.lua              # UI Shell & Page Handling
│  ├─ Modules.lua         # Modul-Registry & Loader
│  ├─ Logging.lua         # Logging Bootstrap
│  └─ SlashCommands.lua   # /gms Command & Subcommands
│
├─ Modules/
│  ├─ Roster.lua          # Beispielmodul (Roster)
│  └─ CharInfo.lua        # Beispielmodul (Character Info)
│
├─ Libs/
│  └─ Ace3/               # Eingebettete Ace3 Libraries
│
└─ README.md
