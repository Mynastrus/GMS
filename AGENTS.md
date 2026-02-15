# Release Rules

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
