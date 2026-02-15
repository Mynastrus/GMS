# Release Rules

## Command Gating (Mandatory)
- `commit` only on explicit user command.
- `release` only on explicit user command.
- `publish` only on explicit user command.

## Definitions (Project-Specific)
- `commit`: uploads the current project state to GitHub.
- `release`: creates/releases the current GitHub version.
- `publish`: sends the addon files to CurseForge.

## Release Content Rules (When Release/Publish Is Commanded)
- Use the current interface version from `GMS/GMS.toc` as the release baseline.
- Provide a clear, polished changelog in both English and German.
