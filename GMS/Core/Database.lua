-- ============================================================================
--	GMS/Core/Database.lua
--	Database EXTENSION
--	- Registers standard SavedVariables via AceDB-3.0
-- ============================================================================

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "DB",
	SHORT_NAME   = "DB",
	DISPLAY_NAME = "Database",
	VERSION      = "1.0.5",
}

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G           = _G
local GetTime      = GetTime
local IsInGuild    = IsInGuild
local GetGuildInfo = GetGuildInfo
local GetRealmName = GetRealmName
local UnitFactionGroup = UnitFactionGroup
local ReloadUI     = ReloadUI
local wipe         = wipe
---@diagnostic enable: undefined-global

-- ---------------------------------------------------------------------------
--	Guards
-- ---------------------------------------------------------------------------

local LibStub = LibStub
if not LibStub then return end

local AceDB = LibStub("AceDB-3.0", true)
if not AceDB then
	return
end

local AceAddon = LibStub("AceAddon-3.0", true)
local GMS = AceAddon and AceAddon:GetAddon("GMS", true) or nil
if not GMS then return end

-- ###########################################################################
-- #	LOG BUFFER + LOCAL LOGGER
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return GetTime and GetTime() or nil
end

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time = now(),
		level = tostring(level or "INFO"),
		type = METADATA.TYPE,
		source = METADATA.SHORT_NAME,
		msg = tostring(msg or ""),
	}

	local n = select("#", ...)
	if n > 0 then
		entry.data = {}
		for i = 1, n do
			entry.data[i] = select(i, ...)
		end
	end

	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		pcall(GMS._LOG_NOTIFY, entry, idx)
	end
end

-- ###########################################################################
-- #	Extension REGISTRATION
-- ###########################################################################

if type(GMS.RegisterExtension) == "function" then
	GMS:RegisterExtension({
		key = METADATA.SHORT_NAME,
		name = METADATA.INTERN_NAME,
		displayName = METADATA.DISPLAY_NAME,
		version = METADATA.VERSION,
		desc = "AceDB-based SavedVariables and module namespaces",
	})
end

-- ###########################################################################
-- #	DEFAULTS
-- ###########################################################################

local DB_DEFAULTS = GMS.DEFAULTS or {
	profile = { debug = false },
	global = { version = 1 },
}

local LOGGING_DEFAULTS = {
	char = {
		logs = {},
	},
	profile = {
		ingestPos = 0,
	},
	global = {},
}

-- ###########################################################################
-- #	STANDARD DATABASE INIT
-- ###########################################################################

local GUILD_DB_DEFAULTS = {
	global = {}, -- Global fallback
	faction = {}, -- Faction specific
	realm = {}, -- Realm specific
	profile = {}, -- Profile specific (rarely used for guilds, but good practice)
}

function GMS:InitializeStandardDatabases(force)
	if not AceDB then
		LOCAL_LOG("WARN", "AceDB-3.0 not available")
		return false
	end

	if self.db and self.guild_db and self.logging_db and not force then
		return true
	end

	-- Initialize Standard DBs
	self.db = self.db or AceDB:New("GMS_DB", DB_DEFAULTS, true)
	self.logging_db = self.logging_db or AceDB:New("GMS_Logging_DB", LOGGING_DEFAULTS, true)

	-- Initialize Manual Guild DB (Raw Table, manual keying by GuildGUID)
	if type(_G.GMS_Guild_DB) ~= "table" then
		---@diagnostic disable-next-line: inject-field
		_G.GMS_Guild_DB = {}
	end
	self.guild_db = _G.GMS_Guild_DB

	LOCAL_LOG("INFO", "Standard databases and Guild DB structure initialized")
	return true
end

--- Helper: Get current character's guild GUID (safe for all WoW versions)
-- @return string|nil: Guild GUID or nil if not in a guild
function GMS:GetGuildGUID()
	if not IsInGuild or not IsInGuild() then
		return nil
	end

	local guildName = nil
	local guildGUID = nil

	-- 1) Try classic/global API
	if GetGuildInfo then
		local n, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, g = GetGuildInfo("player")
		if type(n) == "string" and n ~= "" then
			guildName = n
		end
		if type(g) == "string" and g ~= "" then
			guildGUID = g
		end
	end

	-- 2) Try C_GuildInfo API variants
	if (not guildName or guildName == "") and type(C_GuildInfo) == "table" and type(C_GuildInfo.GetGuildInfo) == "function" then
		local ok, n = pcall(C_GuildInfo.GetGuildInfo, "player")
		if ok and type(n) == "string" and n ~= "" then
			guildName = n
		end
	end

	if (not guildGUID or guildGUID == "") and type(C_GuildInfo) == "table" and type(C_GuildInfo.GetGuildGUID) == "function" then
		local ok, g = pcall(C_GuildInfo.GetGuildGUID, "player")
		if ok and type(g) == "string" and g ~= "" then
			guildGUID = g
		end
	end

	if guildGUID and guildGUID ~= "" then
		return guildGUID
	end

	-- 3) Stable fallback key from Realm + Faction + GuildName
	if guildName and guildName ~= "" then
		local realmName = (GetRealmName and GetRealmName()) or "Unknown"
		local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Unknown"
		return string.format("%s|%s|%s", tostring(realmName), tostring(faction), tostring(guildName))
	end

	return nil
end

-- Early init attempt (harmless if Core runs it again later)
pcall(function()
	if type(GMS.InitializeStandardDatabases) == "function" then
		GMS:InitializeStandardDatabases(false)
	end
end)

-- ###########################################################################
-- #	GMS.DB HELPER API (Scoped Options)
-- ###########################################################################

GMS.DB = GMS.DB or {}
GMS.DB._parent = GMS
GMS.DB._registrations = {}

--- Registers options for a module with a specific scope.
-- @param moduleName string: The internal name of the module (e.g., "Roster")
-- @param defaults table: The default values (flat table)
-- @param scope string: "PROFILE", "GLOBAL", "CHAR", "GUILD"
function GMS:RegisterModuleOptions(moduleName, defaults, scope)
	if not moduleName then return nil end
	scope = string.upper(tostring(scope or "PROFILE"))

	if not self.db then
		self:InitializeStandardDatabases()
	end

	-- Normalize defaults wrapper based on scope logic
	-- NEW: Extract actual values if metadata tables are used
	local aceDefaults = {}
	if type(defaults) == "table" then
		for k, v in pairs(defaults) do
			if type(v) == "table" and v.default ~= nil then
				aceDefaults[k] = v.default
			else
				aceDefaults[k] = v
			end
		end
	end

	local dbDefaults = {}
	if scope == "PROFILE" then
		dbDefaults.profile = aceDefaults
	elseif scope == "GLOBAL" then
		dbDefaults.global = aceDefaults
	elseif scope == "CHAR" then
		dbDefaults.char = aceDefaults
	elseif scope == "GUILD" then
		-- Guild DB is manual, we store defaults for later application
	end

	-- For AceDB scopes (PROFILE, GLOBAL, CHAR), utilize Namespaces
	local namespace = nil
	if scope ~= "GUILD" then
		namespace = self.db:RegisterNamespace(moduleName, dbDefaults)
	end

	-- Store registration meta
	GMS.DB._registrations[moduleName] = {
		name = moduleName,
		defaults = defaults,
		scope = scope,
		namespace = namespace
	}

	LOCAL_LOG("DEBUG", "Registered options", moduleName, scope)
	return namespace -- Returns AceDB namespace or nil (for GUILD scope)
end

--- Retrieves the option table for a module, respecting its scope.
function GMS:GetModuleOptions(moduleName)
	local reg = GMS.DB._registrations[moduleName]
	if not reg then return nil end

	if reg.scope == "PROFILE" then
		return reg.namespace.profile
	elseif reg.scope == "GLOBAL" then
		return reg.namespace.global
	elseif reg.scope == "CHAR" then
		return reg.namespace.char
	elseif reg.scope == "GUILD" then
		local gGUID = self:GetGuildGUID()
		if not gGUID then return nil end -- No guild, no options

		-- Manual Guild DB management
		local gdb = self.guild_db
		gdb[gGUID] = gdb[gGUID] or {}
		gdb[gGUID][moduleName] = gdb[gGUID][moduleName] or {}

		-- Apply defaults (shallow copy if missing)
		local t = gdb[gGUID][moduleName]
		if reg.defaults then
			for k, v in pairs(reg.defaults) do
				if t[k] == nil then
					if type(v) == "table" and v.default ~= nil then
						t[k] = v.default
					else
						t[k] = v
					end
				end
			end
		end
		return t
	end

	return nil
end

--- Resets all databases to defaults.
function GMS:Database_ResetAll()
	LOCAL_LOG("WARN", "Database RESET requested")

	if self.db then
		self.db:ResetProfile()
	end

	if self.logging_db then
		-- Reset logging db - char logs and profile
		self.logging_db.char.logs = {}
		self.logging_db.profile.ingestPos = 0
	end

	if type(_G.GMS_Guild_DB) == "table" then
		wipe(_G.GMS_Guild_DB)
	end

	LOCAL_LOG("INFO", "All databases reset to defaults")

	if type(ReloadUI) == "function" then
		ReloadUI()
	end
end

-- ###########################################################################
-- #	OPTIONS
-- ###########################################################################

GMS:RegisterModuleOptions("DB", {
	reset = { type = "execute", func = function() GMS:Database_ResetAll() end, name = "Datenbank zurücksetzen" }
}, "PROFILE")

-- ###########################################################################
-- #	READY
-- ###########################################################################

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)

LOCAL_LOG("INFO", "Database extension loaded")
