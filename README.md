# GMS - Guild Management System

GMS is a modular World of Warcraft addon for guild-focused management workflows.
It is built on Ace3 and provides a custom UI shell with extensible modules and extensions.

## Highlights
- Modular architecture: `CORE`, `EXT`, `MOD` separation.
- Central UI shell with pages and right-side dock icons.
- Built-in logging console with live filtering.
- In-UI release notes (EN/DE) with version tracking.
- Slash command system with subcommand registry.

## Modules
- `Roster`: guild member overview, filters, sorting, context actions.
- `CharInfo`: player/context snapshot view.
- `Equipment`: character equipment snapshot and analysis.
- `Raids`: raid progression and lockout data.
- `MythicPlus`: M+ score and dungeon data.

## Core Extensions
- `Database`: persistent storage integration.
- `UI`, `UI_Pages`, `UI_Docks`: UI framework and navigation.
- `Logs`: buffered logging and log page.
- `Changelog`: release notes page and auto-open logic.
- `ChatLinks`: clickable chat entries and tooltip actions.
- `SlashCommands`: `/gms` command routing.
- `Comm`: guild comm transport and prefix-based handlers.
- `ModuleStates`, `Settings`, `Dashboard`, `Permissions`.

## Commands
- `/gms` -> open main UI.
- `/gms ?` -> show help/subcommands.
- `/gms changelog` -> open release notes.

## Installation
1. Download or clone this repository.
2. Place `GMS/` into your WoW addons folder:
   - `_retail_/Interface/AddOns/GMS`
3. Reload UI with `/reload`.

## Project Metadata
- CurseForge Project ID: `863660`
- TOC file: `GMS/GMS.toc`

## Development
Project conventions and required rules are documented in:
- `GMS_PROJECT_RULES.md`

Internal unreleased staging for release notes:
- `GMS_INTERNAL_RELEASE_NOTES.md`

---

## Kurzbeschreibung (DE)
GMS ist ein modulares Gildenverwaltungssystem fuer World of Warcraft mit eigener UI, Roster-Tools, Logs, Release Notes und erweiterbaren Modulen.

## Short Description (EN)
GMS is a modular guild management addon for World of Warcraft with a custom UI, roster tooling, logs, release notes, and extensible modules.
