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
	VERSION      = "1.1.6",
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

-- One-time hard reset baseline for the next release.
-- Set this to the release version that should trigger the reset once.
local ONE_TIME_RESET_TARGET_VERSION = "1.4.6"
local ONE_TIME_RESET_MARKER_KEY = "oneTimeHardResetAppliedVersion"
local ONE_TIME_RESET_MARKER_AT_KEY = "oneTimeHardResetAppliedAt"

local function ParseVersionParts(v)
	local out = {}
	for n in tostring(v or ""):gmatch("%d+") do
		out[#out + 1] = tonumber(n) or 0
	end
	return out
end

local function IsVersionAtLeast(current, target)
	local a = ParseVersionParts(current)
	local b = ParseVersionParts(target)
	local maxLen = (#a > #b) and #a or #b
	for i = 1, maxLen do
		local av = a[i] or 0
		local bv = b[i] or 0
		if av > bv then return true end
		if av < bv then return false end
	end
	return true
end

-- ###########################################################################
-- #	STANDARD DATABASE INIT
-- ###########################################################################

local GUILD_DB_DEFAULTS = {
	global = {}, -- Global fallback
	faction = {}, -- Faction specific
	realm = {}, -- Realm specific
	profile = {}, -- Profile specific (rarely used for guilds, but good practice)
}

local function HardResetAllSavedVariablesNoReload(self)
	if self.db then
		self.db:ResetProfile()
		if type(self.db.global) == "table" then
			wipe(self.db.global)
		else
			self.db.global = {}
		end
		self.db.global.version = 2
		self.db.global.characters = {}
		self.db.global.guilds = {}
	end

	if self.logging_db then
		self.logging_db.char = type(self.logging_db.char) == "table" and self.logging_db.char or {}
		self.logging_db.profile = type(self.logging_db.profile) == "table" and self.logging_db.profile or {}
		self.logging_db.char.logs = {}
		self.logging_db.profile.ingestPos = 0
	end

	if type(_G.GMS_Guild_DB) == "table" then wipe(_G.GMS_Guild_DB) end
	local uiDB = rawget(_G, "GMS_UIDB")
	if type(uiDB) == "table" then wipe(uiDB) end
	local changelogDB = rawget(_G, "GMS_Changelog_DB")
	if type(changelogDB) == "table" then wipe(changelogDB) end
end

local function ApplyOneTimeReleaseResetIfNeeded(self)
	local target = tostring(ONE_TIME_RESET_TARGET_VERSION or "")
	if target == "" then return false end
	if not self or not self.db then return false end

	local global = self.db.global
	if type(global) ~= "table" then
		self.db.global = {}
		global = self.db.global
	end

	local alreadyApplied = tostring(global[ONE_TIME_RESET_MARKER_KEY] or "")
	if alreadyApplied == target then
		return false
	end

	-- Prevent repeated wipe loops on reload if marker is missing but schema is already migrated.
	local schemaVersion = tonumber(global.version) or 0
	if schemaVersion >= 2 then
		global[ONE_TIME_RESET_MARKER_KEY] = target
		global[ONE_TIME_RESET_MARKER_AT_KEY] = tonumber(global[ONE_TIME_RESET_MARKER_AT_KEY]) or (now() or 0)
		LOCAL_LOG("INFO", "One-time hard reset skipped (already migrated)", "target=" .. target, "schema=" .. tostring(schemaVersion))
		return false
	end

	local currentVersion = tostring(self.VERSION or "")
	if currentVersion == "" or not IsVersionAtLeast(currentVersion, target) then
		return false
	end

	HardResetAllSavedVariablesNoReload(self)

	self.db.global[ONE_TIME_RESET_MARKER_KEY] = target
	self.db.global[ONE_TIME_RESET_MARKER_AT_KEY] = now() or 0
	LOCAL_LOG("WARN", "One-time hard reset applied", "target=" .. target, "current=" .. currentVersion)
	return true
end

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

	ApplyOneTimeReleaseResetIfNeeded(self)

	local global = self.db.global
	if type(global) ~= "table" then
		self.db.global = {}
		global = self.db.global
	end
	global.version = tonumber(global.version) or 2
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
	local function normalize(s)
		return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
	end

	local function getCanonicalKey()
		if not IsInGuild or not IsInGuild() then return nil end
		local guildName = nil
		if type(GetGuildInfo) == "function" then
			local n = select(1, GetGuildInfo("player"))
			if type(n) == "string" and n ~= "" then guildName = n end
		end
		if (not guildName or guildName == "") and type(C_GuildInfo) == "table" and type(C_GuildInfo.GetGuildInfo) == "function" then
			local ok, n = pcall(C_GuildInfo.GetGuildInfo, "player")
			if ok and type(n) == "string" and n ~= "" then guildName = n end
		end
		guildName = normalize(guildName)
		if guildName == "" then return nil end
		local realm = normalize((type(GetRealmName) == "function" and GetRealmName()) or "Unknown")
		local faction = normalize((type(UnitFactionGroup) == "function" and UnitFactionGroup("player")) or "Unknown")
		if realm == "" then realm = "Unknown" end
		if faction == "" then faction = "Unknown" end
		return string.format("%s|%s|%s", realm, faction, guildName), guildName, faction
	end

	local canonical, guildName, faction = getCanonicalKey()
	local guidKey = self:GetGuildGUID()

	-- Fallback: if exactly one guild bucket exists, reuse it.
	if self.db and type(self.db.global) == "table" and type(self.db.global.guilds) == "table" then
		local buckets = self.db.global.guilds

		if type(canonical) == "string" and canonical ~= "" and type(buckets[canonical]) == "table" then
			return canonical
		end
		if type(guidKey) == "string" and guidKey ~= "" and type(buckets[guidKey]) == "table" then
			return guidKey
		end

		-- Legacy key recovery: find unique key by guild/faction suffix.
		local suffixMatch = nil
		local suffixCount = 0
		local preferredByData = nil
		if guildName and guildName ~= "" then
			local suffix = "|" .. tostring(guildName)
			local factionNeedle = "|" .. tostring(faction or "")
			for k, v in pairs(buckets) do
				if type(k) == "string" and type(v) == "table" and k:sub(-#suffix) == suffix then
					if faction == "" or k:find(factionNeedle, 1, true) then
						suffixCount = suffixCount + 1
						if not suffixMatch then suffixMatch = k end
						if type(v.GUILDLOG) == "table" and type(v.GUILDLOG.entries) == "table" and #v.GUILDLOG.entries > 0 then
							preferredByData = k
						end
					end
				end
			end
		end
		if preferredByData then
			return preferredByData
		end
		if suffixCount == 1 and suffixMatch then
			return suffixMatch
		end

		local first = nil
		local count = 0
		for k in pairs(buckets) do
			if type(k) == "string" and k ~= "" then
				count = count + 1
				if not first then first = k end
				if count > 1 then break end
			end
		end
		if count == 1 and first then
			return first
		end
	end

	if type(canonical) == "string" and canonical ~= "" then return canonical end
	if type(guidKey) == "string" and guidKey ~= "" then return guidKey end
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

local function ApplyDefaults(target, defaults)
	if type(target) ~= "table" or type(defaults) ~= "table" then return end

	local function CloneValue(value)
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for k, v in pairs(value) do
			out[k] = CloneValue(v)
		end
		return out
	end

	for k, v in pairs(defaults) do
		if type(v) == "table" and v.default ~= nil then
			if target[k] == nil then target[k] = CloneValue(v.default) end
		elseif target[k] == nil then
			target[k] = CloneValue(v)
		end
	end
end

local function NormalizeModuleKey(moduleName)
	local key = tostring(moduleName or "")
	key = key:gsub("^%s+", ""):gsub("%s+$", "")
	if key == "" then return nil end
	return string.upper(key)
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
		return global
	elseif scope == "CHAR" then
		global.characters = type(global.characters) == "table" and global.characters or {}
		local cKey = type(UnitGUID) == "function" and UnitGUID("player") or nil
		if type(cKey) ~= "string" or cKey == "" then
			return nil
		end
		global.characters[cKey] = type(global.characters[cKey]) == "table" and global.characters[cKey] or {}
		return global.characters[cKey]
	elseif scope == "GUILD" then
		global.guilds = type(global.guilds) == "table" and global.guilds or {}
		local gKey = self:GetGuildStorageKey()
		if type(gKey) ~= "string" or gKey == "" then
			return nil
		end
		global.guilds[gKey] = type(global.guilds[gKey]) == "table" and global.guilds[gKey] or {}
		return global.guilds[gKey]
	end
	return nil
end

--- Registers options for a module with a specific scope.
-- @param moduleName string: The internal name of the module (e.g., "Roster")
-- @param defaults table: The default values (flat table)
-- @param scope string: "PROFILE", "GLOBAL", "CHAR", "GUILD"
function GMS:RegisterModuleOptions(moduleName, defaults, scope)
	local moduleKey = NormalizeModuleKey(moduleName)
	if not moduleKey then return nil end
	scope = string.upper(tostring(scope or "PROFILE"))

	-- Always persist registration metadata, even when scope root is not ready yet
	-- (e.g. early boot before guild key becomes available).
	GMS.DB._registrations[moduleKey] = {
		name = moduleKey,
		defaults = defaults,
		scope = scope,
		namespace = nil,
	}

	local root = GetScopeRoot(self, scope)
	if type(root) ~= "table" then
		LOCAL_LOG("DEBUG", "Registered options deferred (scope root unavailable)", moduleKey, scope)
		return nil
	end

	root[moduleKey] = type(root[moduleKey]) == "table" and root[moduleKey] or {}
	ApplyDefaults(root[moduleKey], defaults)

	LOCAL_LOG("DEBUG", "Registered options", moduleKey, scope)
	return root[moduleKey]
end

--- Retrieves the option table for a module, respecting its scope.
function GMS:GetModuleOptions(moduleName)
	local moduleKey = NormalizeModuleKey(moduleName)
	if not moduleKey then return nil end
	local reg = GMS.DB._registrations[moduleKey]
	if not reg then return nil end

	local root = GetScopeRoot(self, reg.scope)
	if type(root) ~= "table" then return nil end
	root[moduleKey] = type(root[moduleKey]) == "table" and root[moduleKey] or {}
	ApplyDefaults(root[moduleKey], reg.defaults)
	return root[moduleKey]
end

--- Resets all databases to defaults.
function GMS:Database_ResetAll()
	LOCAL_LOG("WARN", "Database RESET requested")

	if self.db then
		self.db:ResetProfile()
		if type(self.db.global) == "table" then
			wipe(self.db.global)
			self.db.global.version = 2
			self.db.global.characters = {}
			self.db.global.guilds = {}
		end
	end

	if self.logging_db then
		-- Reset logging db - char logs and profile
		self.logging_db.char = type(self.logging_db.char) == "table" and self.logging_db.char or {}
		self.logging_db.profile = type(self.logging_db.profile) == "table" and self.logging_db.profile or {}
		self.logging_db.char.logs = {}
		self.logging_db.profile.ingestPos = 0
	end

	if type(_G.GMS_Guild_DB) == "table" then wipe(_G.GMS_Guild_DB) end
	local uiDB = rawget(_G, "GMS_UIDB")
	if type(uiDB) == "table" then wipe(uiDB) end
	local changelogDB = rawget(_G, "GMS_Changelog_DB")
	if type(changelogDB) == "table" then wipe(changelogDB) end

	LOCAL_LOG("INFO", "All databases reset to defaults")

	if type(ReloadUI) == "function" then
		ReloadUI()
	end
end

local function RegisterDatabaseSlashCommand()
	if type(GMS.Slash_RegisterSubCommand) ~= "function" then
		return false
	end

	GMS:Slash_RegisterSubCommand("dbwipe", function()
		GMS:Database_ResetAll()
	end, {
		helpKey = "DB_SLASH_WIPE_HELP",
		helpFallback = "/gms dbwipe - hard reset all GMS saved variables and reload UI",
		alias = { "dbreset", "resetdb", "wipe" },
		owner = "DB",
	})
	return true
end

-- ###########################################################################
-- #	OPTIONS
-- ###########################################################################

GMS:RegisterModuleOptions("DB", {
	reset = { type = "execute", func = function() GMS:Database_ResetAll() end, name = "Datenbank zurücksetzen" }
}, "PROFILE")

if type(GMS.OnReady) == "function" then
	GMS:OnReady("EXT:SLASH", function()
		RegisterDatabaseSlashCommand()
	end)
else
	pcall(RegisterDatabaseSlashCommand)
end

-- ###########################################################################
-- #	READY
-- ###########################################################################

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)

LOCAL_LOG("INFO", "Database extension loaded")
