# GMS Database Schema (Canonical)

Status: binding target schema for upcoming refactor/migration.

## 1) Top-level model

```lua
GMS_DB = {
  global = {
    chars = { "Player-...", "Player-..." },
    guilds = { ["<guildClubId>"] = { ... } },
    characters = { ["Player-..."] = { ... } },
  },
  char = {
    ["<CharName> - <Realm>"] = {
      chars = { ... }, -- local account tree of active client only
    },
  },
}
```

## 2) Responsibilities per tree

- `global.chars`
  - Purpose: list of all known GUIDs only.
  - No domain payload here.

- `global.guilds`
  - Purpose: guild-scoped data per guild.
  - Key: `guildClubId` from `C_Club.GetGuildClubId()` converted to string.
  - Contains guild-specific player data (for example notes, points, rank, future guild-only metrics).

- `global.characters`
  - Purpose: general character data per GUID (synced, parsed, self-related).
  - Domain payload lives here (`identity`, `equipment`, `raids`, `mythicplus`, etc.).
  - Every domain submenu must include data origin + last update metadata.

- `char["<CharName> - <Realm>"].chars`
  - Purpose: local account tree of the current client only.
  - Never treated as cross-client sync source.
  - Holds local profile/settings/links.

## 3) Guild structure

```lua
global.guilds[guildId] = {
  meta = {
    guildClubId = guildId,
    name = "Holy Storm",
    realm = "Norgannon",
    faction = "Alliance",
    displayKey = "Norgannon|Alliance|Holy Storm", -- from guild context
    updatedAt = "2026-02-23 21:14:05",
  },
  players = {
    ["Player-1408-0A5D1356"] = {
      note = "Core Raider",
      points = 120,
      rank = "Raider",
      updatedAt = "2026-02-23 21:14:05",
    },
  },
}
```

## 4) Character domain structure

Every submenu under `global.characters[guid]` must use this shape:

```lua
global.characters[guid].<domain> = {
  data = { ... },
  meta = {
    sourceGuid = "Player-1408-0A5D1356",
    sourceName = "Ritschy-Norgannon",
    updatedAt = "2026-02-23 21:14:05",
    -- optional: updatedAtTs = 1771881245
  },
}
```

## 5) Time and date rules (mandatory)

- `updatedAt` must keep this exact format:
  - `YYYY-MM-DD HH:MM:SS`
- `updatedAt` is always server time.
- Optional `updatedAtTs` may be stored for sorting/comparison only.
- UI/default display must rely on `updatedAt` format above.

## 6) Identity rules

- Guild primary key:
  - `guildId = tostring(C_Club.GetGuildClubId())`
- `displayKey` (`realm|faction|guildName`) must come from guild context, not from character ownership assumptions.
- Character primary key:
  - `guid` in `Player-<realmId>-<hex>` shape.

## 7) Local links example (`char.*.chars.links`)

```lua
links = {
  mainToTwinks = {
    ["Player-1408-0A5D1356"] = {
      "Player-1408-0A54F355",
      "Player-1408-0AD02B65",
    },
  },
  twinkToMain = {
    ["Player-1408-0A54F355"] = "Player-1408-0A5D1356",
    ["Player-1408-0AD02B65"] = "Player-1408-0A5D1356",
  },
  preferredByRole = {
    tank = "Player-1618-0B9746B7",
    heal = "Player-1408-0A54F355",
    dps = "Player-1408-0AD02B65",
  },
  aliases = {
    ["Player-1408-0A5D1356"] = "Ritschy Main",
  },
  meta = {
    updatedAt = "2026-02-23 21:14:05",
    source = "manual",
    version = 1,
  },
}
```

## 8) Migration intent

- Existing DB paths may coexist during migration.
- Target writes must move to this schema.
- Read compatibility layers are allowed until all modules are switched.
