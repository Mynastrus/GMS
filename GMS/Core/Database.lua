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
	VERSION      = "1.1.0",
}

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G           = _G
local GetTime      = GetTime
local IsInGuild    = IsInGuild
local GetGuildInfo = GetGuildInfo
local GetRealmName = GetRealmName
local UnitFactionGroup = UnitFactionGroup
local UnitGUID = UnitGUID
local UnitName = UnitName
local C_GuildInfo = C_GuildInfo
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

	if self.db and self.logging_db and not force then
		return true
	end

	-- Initialize Standard DBs
	self.db = self.db or AceDB:New("GMS_DB", DB_DEFAULTS, true)
	self.logging_db = self.logging_db or AceDB:New("GMS_Logging_DB", LOGGING_DEFAULTS, true)

	-- Keep legacy variable allocated (compat only); no longer source of truth.
	if type(_G.GMS_Guild_DB) ~= "table" then
		---@diagnostic disable-next-line: inject-field
		_G.GMS_Guild_DB = {}
	end
	self.guild_db = _G.GMS_Guild_DB

	local global = self.db.global
	if type(global) ~= "table" then
		self.db.global = {}
		global = self.db.global
	end
	global.version = tonumber(global.version) or 2
	global.modules = type(global.modules) == "table" and global.modules or {}
	global.characters = type(global.characters) == "table" and global.characters or {}
	global.guilds = type(global.guilds) == "table" and global.guilds or {}

	LOCAL_LOG("INFO", "Standard databases initialized", "schema=2")
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

function GMS:GetCharacterGUID()
	local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
	if type(guid) == "string" and guid ~= "" then
		return guid
	end
	local name = type(UnitName) == "function" and UnitName("player") or "Unknown"
	local realm = type(GetRealmName) == "function" and GetRealmName() or "Unknown"
	return string.format("%s-%s", tostring(name or "Unknown"), tostring(realm or "Unknown"))
end

function GMS:GetGuildStorageKey()
	local g = self:GetGuildGUID()
	if type(g) == "string" and g ~= "" then return g end
	return "NO_GUILD"
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

local function ApplyDefaults(target, defaults)
	if type(target) ~= "table" or type(defaults) ~= "table" then return end
	for k, v in pairs(defaults) do
		if type(v) == "table" and v.default ~= nil then
			if target[k] == nil then target[k] = v.default end
		elseif target[k] == nil then
			target[k] = v
		end
	end
end

local function GetScopeRoot(self, scope)
	if type(self.InitializeStandardDatabases) == "function" then
		self:InitializeStandardDatabases(false)
	end
	if not self.db then return nil end

	local profile = self.db.profile
	local global = self.db.global
	if type(global) ~= "table" then return nil end

	if scope == "PROFILE" then
		profile = type(profile) == "table" and profile or {}
		self.db.profile = profile
		profile.modules = type(profile.modules) == "table" and profile.modules or {}
		return profile.modules
	elseif scope == "GLOBAL" then
		global.modules = type(global.modules) == "table" and global.modules or {}
		return global.modules
	elseif scope == "CHAR" then
		global.characters = type(global.characters) == "table" and global.characters or {}
		local cKey = self:GetCharacterGUID()
		global.characters[cKey] = type(global.characters[cKey]) == "table" and global.characters[cKey] or {}
		global.characters[cKey].modules = type(global.characters[cKey].modules) == "table" and global.characters[cKey].modules or {}
		return global.characters[cKey].modules
	elseif scope == "GUILD" then
		global.guilds = type(global.guilds) == "table" and global.guilds or {}
		local gKey = self:GetGuildStorageKey()
		global.guilds[gKey] = type(global.guilds[gKey]) == "table" and global.guilds[gKey] or {}
		global.guilds[gKey].modules = type(global.guilds[gKey].modules) == "table" and global.guilds[gKey].modules or {}
		return global.guilds[gKey].modules
	end
	return nil
end

--- Registers options for a module with a specific scope.
-- @param moduleName string: The internal name of the module (e.g., "Roster")
-- @param defaults table: The default values (flat table)
-- @param scope string: "PROFILE", "GLOBAL", "CHAR", "GUILD"
function GMS:RegisterModuleOptions(moduleName, defaults, scope)
	if not moduleName then return nil end
	scope = string.upper(tostring(scope or "PROFILE"))

	local root = GetScopeRoot(self, scope)
	if type(root) ~= "table" then return nil end

	root[moduleName] = type(root[moduleName]) == "table" and root[moduleName] or {}
	ApplyDefaults(root[moduleName], defaults)

	-- Store registration meta
	GMS.DB._registrations[moduleName] = {
		name = moduleName,
		defaults = defaults,
		scope = scope,
		namespace = nil,
	}

	LOCAL_LOG("DEBUG", "Registered options", moduleName, scope)
	return root[moduleName]
end

--- Retrieves the option table for a module, respecting its scope.
function GMS:GetModuleOptions(moduleName)
	local reg = GMS.DB._registrations[moduleName]
	if not reg then return nil end

	local root = GetScopeRoot(self, reg.scope)
	if type(root) ~= "table" then return nil end
	root[moduleName] = type(root[moduleName]) == "table" and root[moduleName] or {}
	ApplyDefaults(root[moduleName], reg.defaults)
	return root[moduleName]
end

--- Resets all databases to defaults.
function GMS:Database_ResetAll()
	LOCAL_LOG("WARN", "Database RESET requested")

	if self.db then
		self.db:ResetProfile()
		if type(self.db.global) == "table" then
			wipe(self.db.global)
			self.db.global.version = 2
			self.db.global.modules = {}
			self.db.global.characters = {}
			self.db.global.guilds = {}
		end
	end

	if self.logging_db then
		-- Reset logging db - char logs and profile
		self.logging_db.char.logs = {}
		self.logging_db.profile.ingestPos = 0
	end

	if type(_G.GMS_Guild_DB) == "table" then wipe(_G.GMS_Guild_DB) end

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
