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
	VERSION      = "1.1.15",
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
local UnitLevel = UnitLevel
local UnitClass = UnitClass
local UnitFullName = UnitFullName
local C_GuildInfo = C_GuildInfo
local C_Timer = C_Timer
local ReloadUI     = ReloadUI
local UIParent     = UIParent
local CreateFrame  = CreateFrame
local ChatFontNormal = ChatFontNormal
local tinsert      = tinsert
local tContains    = tContains
local UISpecialFrames = UISpecialFrames
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

local function DT(key, fallback, ...)
	if type(GMS.T) == "function" then
		local ok, out = pcall(GMS.T, GMS, key, ...)
		if ok and type(out) == "string" and out ~= "" and out ~= key then
			return out
		end
	end
	if select("#", ...) > 0 then
		local ok, rendered = pcall(string.format, tostring(fallback or key), ...)
		if ok then
			return rendered
		end
	end
	return tostring(fallback or key)
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

function GMS:InitializeStandardDatabases(force)
	if not AceDB then
		LOCAL_LOG("WARN", "AceDB-3.0 not available")
		return false
	end

	local function NormalizeGlobalSchema()
		local global = self.db and self.db.global
		if type(global) ~= "table" then
			self.db.global = {}
			global = self.db.global
		end
		global.version = tonumber(global.version) or 2
		global.characters = type(global.characters) == "table" and global.characters or {}
		global.guilds = type(global.guilds) == "table" and global.guilds or {}
		-- Cleanup deprecated changelog fallback fields (legacy)
		global.gmsChangelogLastSeenVersion = nil
		global.gmsChangelogLastSeenAt = nil

		-- Hard cleanup on raw SavedVariables root to avoid proxy/metatable leftovers.
		local rawDB = rawget(_G, "GMS_DB")
		if type(rawDB) == "table" and type(rawDB.global) == "table" then
			rawDB.global.gmsChangelogLastSeenVersion = nil
			rawDB.global.gmsChangelogLastSeenAt = nil
		end
	end

	if self.db and self.logging_db and not force then
		NormalizeGlobalSchema()
		return true
	end

	-- Initialize Standard DBs
	self.db = self.db or AceDB:New("GMS_DB", DB_DEFAULTS, true)
	self.logging_db = self.logging_db or AceDB:New("GMS_Logging_DB", LOGGING_DEFAULTS, true)

	NormalizeGlobalSchema()

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

local function BuildLocalIdentity()
	local guid = type(UnitGUID) == "function" and tostring(UnitGUID("player") or "") or ""
	if guid == "" then
		if type(GMS) == "table" and type(GMS.GetCharacterGUID) == "function" then
			guid = tostring(GMS:GetCharacterGUID() or "")
		end
		if guid == "" then
			return nil
		end
	end
	local name = ""
	local realm = ""
	if type(UnitFullName) == "function" then
		local n, r = UnitFullName("player")
		name = tostring(n or "")
		realm = tostring(r or "")
	end
	if name == "" and type(UnitName) == "function" then
		name = tostring(UnitName("player") or "")
	end
	if realm == "" and type(GetRealmName) == "function" then
		realm = tostring(GetRealmName() or "")
	end
	local nameFull = (name ~= "" and realm ~= "") and (name .. "-" .. realm) or name
	local className, classFile = "-", ""
	if type(UnitClass) == "function" then
		local cn, cf = UnitClass("player")
		className = tostring(cn or "-")
		classFile = tostring(cf or "")
	end
	local level = type(UnitLevel) == "function" and (tonumber(UnitLevel("player") or 0) or 0) or 0
	return {
		guid = guid,
		name = name,
		realm = realm,
		nameFull = (nameFull ~= "" and nameFull or guid),
		class = className,
		classFile = classFile,
		level = level,
	}
end

local function EnsureRawGlobalTables()
	local rawDB = rawget(_G, "GMS_DB")
	if type(rawDB) ~= "table" then return nil end
	rawDB.global = type(rawDB.global) == "table" and rawDB.global or {}
	local global = rawDB.global
	global.accountLinks = type(global.accountLinks) == "table" and global.accountLinks or {}
	global.accountLinks.chars = type(global.accountLinks.chars) == "table" and global.accountLinks.chars or {}
	global.twinks = type(global.twinks) == "table" and global.twinks or {}
	global.twinkMeta = type(global.twinkMeta) == "table" and global.twinkMeta or {}
	return global
end

function GMS:TrackCurrentCharacterInGlobalStores(reason)
	if type(self.InitializeStandardDatabases) == "function" then
		self:InitializeStandardDatabases(false)
	end
	if type(self.db) ~= "table" or type(self.db.global) ~= "table" then
		return false, "db-unavailable"
	end

	local id = BuildLocalIdentity()
	if type(id) ~= "table" then
		return false, "no-guid"
	end

	local global = self.db.global
	global.accountLinks = type(global.accountLinks) == "table" and global.accountLinks or {}
	global.accountLinks.chars = type(global.accountLinks.chars) == "table" and global.accountLinks.chars or {}
	global.twinks = type(global.twinks) == "table" and global.twinks or {}
	global.twinkMeta = type(global.twinkMeta) == "table" and global.twinkMeta or {}

	local guildKey = tostring(self:GetGuildStorageKey() or "")
	local guildName = ""
	if type(GetGuildInfo) == "function" then
		guildName = tostring(GetGuildInfo("player") or "")
	end
	local seenAt = type(now) == "function" and (tonumber(now() or 0) or 0) or 0

	local row = type(global.accountLinks.chars[id.guid]) == "table" and global.accountLinks.chars[id.guid] or {}
	global.accountLinks.chars[id.guid] = row
	row.guid = id.guid
	row.name = id.name
	row.realm = id.realm
	row.name_full = id.nameFull
	row.class = id.class
	row.classFile = id.classFile
	row.level = id.level
	row.guild = guildName
	row.guildKey = guildKey
	row.lastSeenAt = seenAt
	row.lastSeenReason = tostring(reason or "db-fallback")

	local hasTwink = false
	for i = 1, #global.twinks do
		if tostring(global.twinks[i] or "") == id.guid then
			hasTwink = true
			break
		end
	end
	if not hasTwink then
		global.twinks[#global.twinks + 1] = id.guid
	end

	local meta = type(global.twinkMeta[id.guid]) == "table" and global.twinkMeta[id.guid] or {}
	global.twinkMeta[id.guid] = meta
	meta.guid = id.guid
	meta.name = id.name
	meta.realm = id.realm
	meta.name_full = id.nameFull
	meta.class = id.class
	meta.classFile = id.classFile
	meta.level = id.level
	meta.guild = guildName
	meta.guildKey = guildKey
	meta.lastSeenAt = seenAt

	-- Mirror write into raw SavedVariables table so DB inspector and persistence stay in sync.
	local rawGlobal = EnsureRawGlobalTables()
	if type(rawGlobal) == "table" then
		rawGlobal.accountLinks.chars[id.guid] = rawGlobal.accountLinks.chars[id.guid] or {}
		local rawRow = rawGlobal.accountLinks.chars[id.guid]
		rawRow.guid = id.guid
		rawRow.name = id.name
		rawRow.realm = id.realm
		rawRow.name_full = id.nameFull
		rawRow.class = id.class
		rawRow.classFile = id.classFile
		rawRow.level = id.level
		rawRow.guild = guildName
		rawRow.guildKey = guildKey
		rawRow.lastSeenAt = seenAt
		rawRow.lastSeenReason = tostring(reason or "db-fallback")

		local rawHasTwink = false
		for i = 1, #rawGlobal.twinks do
			if tostring(rawGlobal.twinks[i] or "") == id.guid then
				rawHasTwink = true
				break
			end
		end
		if not rawHasTwink then
			rawGlobal.twinks[#rawGlobal.twinks + 1] = id.guid
		end

		rawGlobal.twinkMeta[id.guid] = rawGlobal.twinkMeta[id.guid] or {}
		local rawMeta = rawGlobal.twinkMeta[id.guid]
		rawMeta.guid = id.guid
		rawMeta.name = id.name
		rawMeta.realm = id.realm
		rawMeta.name_full = id.nameFull
		rawMeta.class = id.class
		rawMeta.classFile = id.classFile
		rawMeta.level = id.level
		rawMeta.guild = guildName
		rawMeta.guildKey = guildKey
		rawMeta.lastSeenAt = seenAt
	end

	return true
end

local function TryTrackCurrentCharacter(reason)
	if type(GMS.TrackCurrentCharacterInGlobalStores) ~= "function" then
		return false
	end
	local ok, tracked, why = pcall(GMS.TrackCurrentCharacterInGlobalStores, GMS, reason)
	if not ok then
		LOCAL_LOG("WARN", "TrackCurrentCharacterInGlobalStores failed", tostring(reason or "unknown"), tostring(tracked or "unknown"))
		return false
	end
	if tracked ~= true then
		LOCAL_LOG("DEBUG", "TrackCurrentCharacterInGlobalStores skipped", tostring(reason or "unknown"), tostring(why or "unknown"))
		return false
	end
	return true
end

-- Early init attempt (harmless if Core runs it again later)
pcall(function()
	if type(GMS.InitializeStandardDatabases) == "function" then
		GMS:InitializeStandardDatabases(false)
	end
	TryTrackCurrentCharacter("db-bootstrap")
	if C_Timer and type(C_Timer.After) == "function" then
		C_Timer.After(2.0, function() TryTrackCurrentCharacter("db-bootstrap-delay-2s") end)
		C_Timer.After(6.0, function() TryTrackCurrentCharacter("db-bootstrap-delay-6s") end)
	end
end)

local DB_TRACK_FRAME = nil
if type(CreateFrame) == "function" then
	DB_TRACK_FRAME = CreateFrame("Frame")
	DB_TRACK_FRAME:RegisterEvent("PLAYER_LOGIN")
	DB_TRACK_FRAME:RegisterEvent("PLAYER_ENTERING_WORLD")
	DB_TRACK_FRAME:RegisterEvent("GUILD_ROSTER_UPDATE")
	DB_TRACK_FRAME:SetScript("OnEvent", function(_, event)
		local tag = "db-event-" .. tostring(event or "unknown")
		TryTrackCurrentCharacter(tag)
		if C_Timer and type(C_Timer.After) == "function" then
			C_Timer.After(1.0, function() TryTrackCurrentCharacter(tag .. "-delay-1s") end)
		end
	end)
end

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

	local uiDB = rawget(_G, "GMS_UIDB")
	if type(uiDB) == "table" then wipe(uiDB) end

	LOCAL_LOG("INFO", "All databases reset to defaults")

	if type(ReloadUI) == "function" then
		ReloadUI()
	end
end

local DB_INSPECTOR = {
	frame = nil,
	title = nil,
	edit = nil,
	scope = "all",
	full = false,
}

local function NormalizeDbScope(raw)
	local s = tostring(raw or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then return "all" end
	if s == "all" or s == "a" then return "all" end
	if s == "gms" or s == "gms_db" or s == "db" then return "gms" end
	if s == "logging" or s == "log" or s == "gms_logging_db" then return "logging" end
	if s == "ui" or s == "uidb" or s == "gms_uidb" then return "ui" end
	return nil
end

local function ParseDbViewArgs(raw)
	local txt = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if txt == "" then
		return "all", false, nil
	end

	local scope = nil
	local full = false
	for token in txt:gmatch("%S+") do
		local t = tostring(token or ""):lower()
		local maybeScope = NormalizeDbScope(t)
		if maybeScope and not scope then
			scope = maybeScope
		elseif t == "full" then
			full = true
		elseif t == "compact" then
			full = false
		else
			return nil, nil, token
		end
	end

	if not scope then scope = "all" end
	return scope, full, nil
end

local function ScopeDisplayLabel(scope)
	if scope == "all" then return DT("DB_VIEW_SCOPE_ALL", "All DBs") end
	if scope == "gms" then return DT("DB_VIEW_SCOPE_GMS", "GMS_DB") end
	if scope == "logging" then return DT("DB_VIEW_SCOPE_LOGGING", "GMS_Logging_DB") end
	if scope == "ui" then return DT("DB_VIEW_SCOPE_UI", "GMS_UIDB") end
	return tostring(scope or "unknown")
end

local function GetScopeTable(scope)
	if scope == "gms" then return rawget(_G, "GMS_DB") end
	if scope == "logging" then return rawget(_G, "GMS_Logging_DB") end
	if scope == "ui" then return rawget(_G, "GMS_UIDB") end
	return nil
end

local function EscapeString(s)
	return string.format("%q", tostring(s or ""))
end

local function MakeSortKey(k)
	local t = type(k)
	if t == "number" then return "1:" .. string.format("%020.6f", k) end
	if t == "string" then return "2:" .. k end
	if t == "boolean" then return "3:" .. tostring(k) end
	return "9:" .. t .. ":" .. tostring(k)
end

local function SerializeTable(value, indent, visited, out, limits)
	indent = indent or 0
	visited = visited or {}
	out = out or {}
	limits = limits or { maxDepth = 8, maxItems = 15000, count = 0, maxChars = 900000, chars = 0, truncated = false }

	local function Push(line)
		if limits.truncated then return end
		line = tostring(line or "")
		limits.chars = limits.chars + #line + 1
		if limits.chars > limits.maxChars then
			limits.truncated = true
			out[#out + 1] = string.rep(" ", indent) .. "-- [TRUNCATED: max output size reached]"
			return
		end
		out[#out + 1] = line
	end

	local function FormatScalar(v)
		local tv = type(v)
		if tv == "string" then return EscapeString(v) end
		if tv == "number" or tv == "boolean" or tv == "nil" then return tostring(v) end
		return string.format("%q", "<" .. tv .. ">")
	end

	local function FormatKey(k)
		if type(k) == "string" then
			return "[" .. EscapeString(k) .. "]"
		end
		if type(k) == "number" then
			return "[" .. tostring(k) .. "]"
		end
		if type(k) == "boolean" then
			return "[" .. tostring(k) .. "]"
		end
		return "[" .. EscapeString("<" .. type(k) .. ":" .. tostring(k) .. ">") .. "]"
	end

	local function Walk(v, depth)
		if limits.truncated then
			return
		end
		local tv = type(v)
		if tv ~= "table" then
			Push(string.rep(" ", depth) .. FormatScalar(v))
			return
		end
		if visited[v] then
			Push(string.rep(" ", depth) .. string.format("%q", "<cycle>"))
			return
		end
		if depth / 2 >= limits.maxDepth then
			Push(string.rep(" ", depth) .. string.format("%q", "<max-depth>"))
			return
		end

		visited[v] = true
		Push(string.rep(" ", depth) .. "{")

		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b)
			return MakeSortKey(a) < MakeSortKey(b)
		end)

		for i = 1, #keys do
			local k = keys[i]
			local val = v[k]
			limits.count = limits.count + 1
			if limits.count > limits.maxItems then
				Push(string.rep(" ", depth + 2) .. "-- [TRUNCATED: max item count reached]")
				limits.truncated = true
				break
			end
			if type(val) == "table" then
				Push(string.rep(" ", depth + 2) .. FormatKey(k) .. " =")
				Walk(val, depth + 4)
				Push(string.rep(" ", depth + 2) .. ",")
			else
				Push(string.rep(" ", depth + 2) .. FormatKey(k) .. " = " .. FormatScalar(val) .. ",")
			end
			if limits.truncated then break end
		end

		Push(string.rep(" ", depth) .. "}")
		visited[v] = nil
	end

	Walk(value, indent)
	return table.concat(out, "\n")
end

local function NewSerializeLimits(fullDump)
	if fullDump then
		return {
			maxDepth = 64,
			maxItems = 250000,
			count = 0,
			maxChars = 5000000,
			chars = 0,
			truncated = false,
		}
	end
	return {
		maxDepth = 8,
		maxItems = 15000,
		count = 0,
		maxChars = 900000,
		chars = 0,
		truncated = false,
	}
end

function GMS:Database_BuildInspectorText(scope, fullDump)
	local normalized = NormalizeDbScope(scope) or "all"
	local isFull = (fullDump == true)
	local header = {}
	local nowTs = type(GetTime) == "function" and (tonumber(GetTime() or 0) or 0) or 0
	header[#header + 1] = ("-- GMS DB Inspector")
	header[#header + 1] = ("-- Scope: " .. ScopeDisplayLabel(normalized))
	header[#header + 1] = ("-- Mode: " .. (isFull and "full" or "compact"))
	header[#header + 1] = ("-- Time: " .. tostring(nowTs))
	header[#header + 1] = ("-- Tip: Click into the text and press CTRL+C")
	header[#header + 1] = ""
	local limits = NewSerializeLimits(isFull)

	if normalized == "all" then
		local payload = {
			GMS_DB = GetScopeTable("gms"),
			GMS_Logging_DB = GetScopeTable("logging"),
			GMS_UIDB = GetScopeTable("ui"),
		}
		return table.concat(header, "\n") .. SerializeTable(payload, 0, nil, nil, limits)
	end

	local tbl = GetScopeTable(normalized)
	if type(tbl) ~= "table" then
		return table.concat(header, "\n") .. string.format("%q", "<nil-or-non-table>")
	end
	return table.concat(header, "\n") .. SerializeTable(tbl, 0, nil, nil, limits)
end

function GMS:Database_InspectorRefresh()
	if not DB_INSPECTOR.frame or not DB_INSPECTOR.edit then
		return false
	end
	local text = self:Database_BuildInspectorText(DB_INSPECTOR.scope, DB_INSPECTOR.full)
	DB_INSPECTOR.edit:SetText(text or "")
	DB_INSPECTOR.edit:SetCursorPosition(0)
	return true
end

local function EnsureDbInspectorFrame()
	if DB_INSPECTOR.frame then
		return DB_INSPECTOR.frame
	end
	if type(CreateFrame) ~= "function" or not UIParent then
		return nil
	end

	local f = CreateFrame("Frame", "GMS_DBInspectorFrame", UIParent, "ButtonFrameTemplate")
	f:SetSize(920, 620)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(selfFrame) selfFrame:StartMoving() end)
	f:SetScript("OnDragStop", function(selfFrame) selfFrame:StopMovingOrSizing() end)

	if f.SetResizeBounds then
		f:SetResizable(true)
		f:SetResizeBounds(700, 420)
	end

	if f.TitleText and type(f.TitleText.SetText) == "function" then
		f.TitleText:SetText(DT("DB_VIEW_TITLE", "GMS Database Inspector"))
	end

	if UISpecialFrames and type(tContains) == "function" and type(tinsert) == "function" then
		if not tContains(UISpecialFrames, "GMS_DBInspectorFrame") then
			tinsert(UISpecialFrames, "GMS_DBInspectorFrame")
		end
	end

	local inset = f.Inset or f.inset
	local anchor = inset or f

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	hint:SetJustifyH("LEFT")
	hint:SetText(DT("DB_VIEW_HINT", "Live SavedVariables snapshot. Use Refresh before copying."))
	hint:SetPoint("TOPLEFT", anchor, "TOPLEFT", 8, -8)
	hint:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -8, -8)

	local scopeButtons = {}
	local function MakeScopeButton(scope, offsetX)
		local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		btn:SetSize(95, 20)
		btn:SetPoint("TOPLEFT", anchor, "TOPLEFT", offsetX, -28)
		btn:SetText(ScopeDisplayLabel(scope))
		btn:SetScript("OnClick", function()
			DB_INSPECTOR.scope = scope
			GMS:Database_InspectorRefresh()
			if DB_INSPECTOR.title then
				DB_INSPECTOR.title:SetText(DT("DB_VIEW_TITLE_FMT", "GMS Database Inspector - %s", ScopeDisplayLabel(scope)))
			end
		end)
		scopeButtons[#scopeButtons + 1] = btn
	end

	MakeScopeButton("all", 8)
	MakeScopeButton("gms", 108)
	MakeScopeButton("logging", 208)
	MakeScopeButton("ui", 308)

	local btnRefresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	btnRefresh:SetSize(95, 20)
	btnRefresh:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -106, -28)
	btnRefresh:SetText(DT("DB_VIEW_REFRESH", "Refresh"))
	btnRefresh:SetScript("OnClick", function()
		GMS:Database_InspectorRefresh()
	end)

	local btnSelect = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	btnSelect:SetSize(95, 20)
	btnSelect:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -8, -28)
	btnSelect:SetText(DT("DB_VIEW_SELECT_ALL", "Select All"))
	btnSelect:SetScript("OnClick", function()
		local eb = DB_INSPECTOR.edit
		if eb then
			eb:SetFocus()
			eb:HighlightText()
		end
	end)

	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", anchor, "TOPLEFT", 8, -54)
	scroll:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -30, 8)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetAutoFocus(false)
	edit:SetMultiLine(true)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(850)
	edit:SetScript("OnEscapePressed", function(selfEdit) selfEdit:ClearFocus() end)
	edit:SetScript("OnTextChanged", function(selfEdit)
		local w = scroll:GetWidth()
		if w and w > 0 then
			selfEdit:SetWidth(w - 12)
		end
	end)
	scroll:SetScrollChild(edit)

	scroll:HookScript("OnSizeChanged", function(selfScroll)
		local w = selfScroll:GetWidth()
		if w and w > 0 then
			edit:SetWidth(w - 12)
		end
	end)

	DB_INSPECTOR.frame = f
	DB_INSPECTOR.title = f.TitleText
	DB_INSPECTOR.edit = edit
	return f
end

function GMS:Database_OpenInspector(scope)
	local normalized, fullDump, invalidToken = ParseDbViewArgs(scope)
	if not normalized then
		if type(self.Print) == "function" then
			self:Print(DT("DB_VIEW_UNKNOWN_SCOPE_FMT", "Unknown DB scope: %s", tostring(invalidToken or scope or "")))
			self:Print(DT("DB_VIEW_USAGE", "Usage: /gms dbview [all|gms|logging|ui] [full]"))
		end
		return false
	end

	local frame = EnsureDbInspectorFrame()
	if not frame then
		LOCAL_LOG("WARN", "DB inspector frame unavailable")
		return false
	end

	DB_INSPECTOR.scope = normalized
	DB_INSPECTOR.full = (fullDump == true)
	if DB_INSPECTOR.title then
		DB_INSPECTOR.title:SetText(DT("DB_VIEW_TITLE_FMT", "GMS Database Inspector - %s", ScopeDisplayLabel(normalized)))
	end
	self:Database_InspectorRefresh()
	frame:Show()
	frame:Raise()

	if type(self.Print) == "function" then
		self:Print(DT("DB_VIEW_OPENED_FMT", "DB inspector opened (%s)", ScopeDisplayLabel(normalized)))
		self:Print(DT("DB_VIEW_MODE_FMT", "Inspector mode: %s", DB_INSPECTOR.full and "full" or "compact"))
	end
	return true
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

	GMS:Slash_RegisterSubCommand("dbview", function(rest)
		GMS:Database_OpenInspector(rest)
	end, {
		helpKey = "DB_SLASH_VIEW_HELP",
		helpFallback = "/gms dbview [all|gms|logging|ui] [full] - open live DB inspector",
		alias = { "dbinspect", "dbshow", "dbcopy" },
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
