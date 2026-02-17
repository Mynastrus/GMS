# Release Rules

## Global Project Rules (Mandatory)
- Always read and follow `GMS_PROJECT_RULES.md` for every task in this repository.
- If any instruction conflicts appears, treat `GMS_PROJECT_RULES.md` and this `AGENTS.md` as mandatory project policy and ask the user for clarification before proceeding.

## Command Gating (Mandatory)
- `commit` only on explicit user command.
- `release` only on explicit user command.

## Definitions (Project-Specific)
- `commit`: uploads the current project state to GitHub.
- `release`: creates/releases the current GitHub version.

## Commit Documentation Rules (Mandatory)
- Every commit must include at least one new entry in `GMS_INTERNAL_RELEASE_NOTES.md` under `## Unreleased`.
- A commit is not complete until the notes entry is present.

## Release Content Rules (When Release Is Commanded)
- Use the current interface version from `GMS/GMS.toc` as the release baseline.
- Provide a clear, polished changelog in both English and German.
- Post release announcements to Discord webhooks:
  - German post (with CurseForge link): use secret `DISCORD_WEBHOOK_RELEASE_DE`
  - English post (with CurseForge link): use secret `DISCORD_WEBHOOK_RELEASE_EN`
  - Never store raw webhook URLs in repository files.
