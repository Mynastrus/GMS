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
├─ GMS.toc
│
├─ Core/
│  ├─ Core.lua            # Core Entry (AceAddon Bootstrap)
│  ├─ ChatLinks.lua       # ChatLinks functions
│  ├─ UI.lua              # UI Shell & Page Handling
│  ├─ Database.lua        # Database functions
│  ├─ Logs.lua            # Logging Bootstrap
│  └─ SlashCommands.lua   # /gms Command & Subcommands
│
├─ Modules/
│  ├─ Roster.lua          # Gildenroster
│  └─ CharInfo.lua        # Character Overview
│
├─ Libs/
│  └─ Ace3/               # Eingebettete Ace3 Libraries
│  └─ LibDeflate/         # LibDeflate
│
└─ README.md
