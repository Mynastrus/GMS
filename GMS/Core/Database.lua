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
	VERSION      = "1.1.25",
}

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G           = _G
local GetTime      = GetTime
local time         = time
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
local C_Club = C_Club
local C_Timer = C_Timer
local GetServerTime = GetServerTime
local date = date
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

local HydrateGuildMeta
local EnsureGuidInGlobal
local EnsureAccountGuidInGlobal
local NormalizeGuid

-- ###########################################################################
-- #	STANDARD DATABASE INIT
-- ###########################################################################

function GMS:InitializeStandardDatabases(force)
	if not AceDB then
		LOCAL_LOG("WARN", "AceDB-3.0 not available")
		return false
	end

	local function NormalizeGlobalSchema()
		local function IsNumericGuildKey(v)
			local s = tostring(v or "")
			return s:match("^%d+$") ~= nil
		end

		local function MergeGuildBuckets(dst, src)
			if type(dst) ~= "table" or type(src) ~= "table" then return end
			for k, v in pairs(src) do
				if type(v) == "table" then
					dst[k] = type(dst[k]) == "table" and dst[k] or {}
					MergeGuildBuckets(dst[k], v)
				elseif dst[k] == nil then
					dst[k] = v
				end
			end
		end

		local global = self.db and self.db.global
		if type(global) ~= "table" then
			self.db.global = {}
			global = self.db.global
		end
		global.version = tonumber(global.version) or 3
		global.accountChars = type(global.accountChars) == "table" and global.accountChars or {}
		global.characters = type(global.characters) == "table" and global.characters or {}
		global.guilds = type(global.guilds) == "table" and global.guilds or {}
		-- Hard cutover cleanup for deprecated roots.
		global.accountLinks = nil
		global.twinks = nil
		global.twinkMeta = nil
		global.gmsChangelogLastSeenVersion = nil
		global.gmsChangelogLastSeenAt = nil

		-- Hard cleanup on raw SavedVariables root to avoid proxy/metatable leftovers.
		local rawDB = rawget(_G, "GMS_DB")
		if type(rawDB) ~= "table" then
			rawDB = {}
			_G.GMS_DB = rawDB
		end
		rawDB.global = type(rawDB.global) == "table" and rawDB.global or {}
		rawDB.global.accountChars = type(rawDB.global.accountChars) == "table" and rawDB.global.accountChars or {}
		rawDB.global.characters = type(rawDB.global.characters) == "table" and rawDB.global.characters or {}
		rawDB.global.guilds = type(rawDB.global.guilds) == "table" and rawDB.global.guilds or {}
		rawDB.global.chars = nil
		rawDB.global.accountLinks = nil
		rawDB.global.twinks = nil
		rawDB.global.twinkMeta = nil
		rawDB.global.gmsChangelogLastSeenVersion = nil
		rawDB.global.gmsChangelogLastSeenAt = nil

		rawDB.char = type(rawDB.char) == "table" and rawDB.char or {}
		rawDB.profileKeys = type(rawDB.profileKeys) == "table" and rawDB.profileKeys or {}
		rawDB.profiles = type(rawDB.profiles) == "table" and rawDB.profiles or {}

		if type(self.db) == "table" and type(self.db.global) == "table" then
			self.db.global.accountChars = rawDB.global.accountChars
			self.db.global.characters = rawDB.global.characters
			self.db.global.guilds = rawDB.global.guilds
		end

		-- Hard cutover: guild buckets are keyed by guildClubId only.
		local currentGuildId = self:GetCurrentGuildId()
		local guilds = rawDB.global.guilds
		if type(guilds) == "table" then
			if type(currentGuildId) == "string" and currentGuildId ~= "" then
				guilds[currentGuildId] = type(guilds[currentGuildId]) == "table" and guilds[currentGuildId] or {}
				HydrateGuildMeta(self, guilds[currentGuildId], currentGuildId)
			end
			for k, v in pairs(guilds) do
				if not IsNumericGuildKey(k) then
					if type(currentGuildId) == "string" and currentGuildId ~= "" and type(v) == "table" then
						MergeGuildBuckets(guilds[currentGuildId], v)
					end
					guilds[k] = nil
				end
			end
			-- Ensure guild roster GUIDs are always mirrored in global.characters.
			for _, gRoot in pairs(guilds) do
				if type(gRoot) == "table" then
					gRoot.players = nil
					gRoot.roster = type(gRoot.roster) == "table" and gRoot.roster or {}
					for pGuid, pRow in pairs(gRoot.roster) do
						local normalized = EnsureGuidInGlobal and EnsureGuidInGlobal(global, pGuid) or nil
						if type(normalized) == "string" and normalized ~= "" and normalized ~= pGuid then
							gRoot.roster[normalized] = type(gRoot.roster[normalized]) == "table" and gRoot.roster[normalized] or {}
							MergeGuildBuckets(gRoot.roster[normalized], pRow)
							gRoot.roster[pGuid] = nil
						end
					end
				end
			end
		end

		local charRoot = self.db and self.db.char
		if type(charRoot) ~= "table" then
			self.db.char = {}
			charRoot = self.db.char
		end
		charRoot.chars = type(charRoot.chars) == "table" and charRoot.chars or {}
	end

	if self.db and self.logging_db and not force then
		NormalizeGlobalSchema()
		return true
	end

	-- Initialize Standard DBs
	self.db = self.db or AceDB:New("GMS_DB", DB_DEFAULTS, true)
	self.logging_db = self.logging_db or AceDB:New("GMS_Logging_DB", LOGGING_DEFAULTS, true)

	NormalizeGlobalSchema()

	LOCAL_LOG("INFO", "Standard databases initialized", "schema=3")
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
	-- Hard cutover: storage key equals guildClubId.
	return self:GetCurrentGuildId()
end

NormalizeGuid = function(guid)
	local g = tostring(guid or "")
	if g == "" then return "" end
	if g:match("^Player%-%d+%-%x+$") then
		return g
	end
	return ""
end

EnsureGuidInGlobal = function(global, guid)
	if type(global) ~= "table" then return nil end
	local g = NormalizeGuid(guid)
	if g == "" then return nil end
	global.characters = type(global.characters) == "table" and global.characters or {}
	global.characters[g] = type(global.characters[g]) == "table" and global.characters[g] or {}
	return g
end

EnsureAccountGuidInGlobal = function(global, guid)
	if type(global) ~= "table" then return nil end
	local g = NormalizeGuid(guid)
	if g == "" then return nil end
	global.accountChars = type(global.accountChars) == "table" and global.accountChars or {}
	for i = 1, #global.accountChars do
		if tostring(global.accountChars[i] or "") == g then
			return g
		end
	end
	global.accountChars[#global.accountChars + 1] = g
	return g
end

function GMS:GetServerTimestamp()
	if type(GetServerTime) == "function" then
		local ts = tonumber(GetServerTime())
		if ts and ts > 0 then
			return math.floor(ts)
		end
	end
	local fallback = tonumber(time and time() or 0) or 0
	return math.floor(fallback)
end

function GMS:FormatServerTimestamp(ts)
	local n = tonumber(ts or 0) or 0
	if n <= 0 then
		n = self:GetServerTimestamp()
	end
	if type(date) == "function" then
		return tostring(date("%Y-%m-%d %H:%M:%S", n))
	end
	return "1970-01-01 00:00:00"
end

function GMS:GetServerStamp(ts)
	local n = tonumber(ts or 0) or 0
	if n <= 0 then
		n = self:GetServerTimestamp()
	end
	return self:FormatServerTimestamp(n), n
end

function GMS:GetCurrentGuildId()
	local id = nil
	if type(C_Club) == "table" and type(C_Club.GetGuildClubId) == "function" then
		local ok, clubId = pcall(C_Club.GetGuildClubId)
		if ok and clubId ~= nil then
			id = tostring(clubId)
		end
	end
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

HydrateGuildMeta = function(self, root, guildId)
	if type(root) ~= "table" then return end
	root.meta = type(root.meta) == "table" and root.meta or {}
	local meta = root.meta
	local gid = tostring(guildId or "")
	if gid ~= "" then
		meta.guildClubId = gid
	end

	local guildName = ""
	if type(GetGuildInfo) == "function" then
		guildName = tostring(select(1, GetGuildInfo("player")) or "")
	end
	if guildName == "" and type(C_GuildInfo) == "table" and type(C_GuildInfo.GetGuildInfo) == "function" then
		local ok, n = pcall(C_GuildInfo.GetGuildInfo, "player")
		if ok then guildName = tostring(n or "") end
	end

	local realm = tostring((type(GetRealmName) == "function" and GetRealmName()) or "")
	local faction = tostring((type(UnitFactionGroup) == "function" and UnitFactionGroup("player")) or "")
	if guildName ~= "" then meta.name = guildName end
	if realm ~= "" then meta.realm = realm end
	if faction ~= "" then meta.faction = faction end
	if guildName ~= "" and realm ~= "" and faction ~= "" then
		meta.displayKey = string.format("%s|%s|%s", realm, faction, guildName)
	end

	local ts = (type(self.GetServerTimestamp) == "function") and tonumber(self:GetServerTimestamp() or 0) or 0
	if ts and ts > 0 and type(self.FormatServerTimestamp) == "function" then
		meta.updatedAt = self:FormatServerTimestamp(ts)
		meta.updatedAtTs = ts
	end
end

function GMS:GetCurrentCharRoot()
	if type(self.InitializeStandardDatabases) == "function" then
		self:InitializeStandardDatabases(false)
	end
	if type(self.db) ~= "table" then return nil end
	self.db.char = type(self.db.char) == "table" and self.db.char or {}
	self.db.char.chars = type(self.db.char.chars) == "table" and self.db.char.chars or {}
	return self.db.char.chars
end

function GMS:RegisterKnownGuid(guid)
	local g = NormalizeGuid(guid)
	if g == "" then return false end
	if type(self.InitializeStandardDatabases) == "function" then
		self:InitializeStandardDatabases(false)
	end
	local global = self.db and self.db.global
	if type(global) ~= "table" then return false end
	return EnsureAccountGuidInGlobal(global, g) ~= nil
end

function GMS:EnsureGlobalCharacterRoot(guid)
	local g = NormalizeGuid(guid)
	if g == "" then return nil end
	if type(self.InitializeStandardDatabases) == "function" then
		self:InitializeStandardDatabases(false)
	end
	local global = self.db and self.db.global
	if type(global) ~= "table" then return nil end
	local normalized = EnsureGuidInGlobal(global, g)
	if type(normalized) ~= "string" or normalized == "" then return nil end
	return global.characters[normalized]
end

function GMS:SetCharacterDomainData(guid, domain, payload, meta)
	local g = NormalizeGuid(guid)
	local d = tostring(domain or "")
	if g == "" or d == "" or type(payload) ~= "table" then
		return false
	end
	local root = self:EnsureGlobalCharacterRoot(g)
	if type(root) ~= "table" then return false end
	local m = type(meta) == "table" and meta or {}
	local ts = tonumber(m.updatedAtTs or m.ts or 0) or 0
	-- Normalize non-unix timestamps (e.g. GetTime session seconds from sync metadata).
	if ts > 0 and ts < 1000000000 then
		ts = 0
	end
	if ts <= 0 then
		ts = self:GetServerTimestamp()
	end
	local updatedAt = tostring(m.updatedAt or "")
	if updatedAt == "" then
		updatedAt = self:FormatServerTimestamp(ts)
	end
	root[d] = {
		data = payload,
		meta = {
			sourceGuid = NormalizeGuid(m.sourceGuid) ~= "" and NormalizeGuid(m.sourceGuid) or NormalizeGuid(m.senderGuid) or "",
			sourceName = tostring(m.sourceName or m.senderName or ""),
			updatedAt = updatedAt,
			updatedAtTs = ts,
		},
	}
	return true
end

function GMS:GetCharacterDomainData(guid, domain)
	local g = NormalizeGuid(guid)
	local d = tostring(domain or "")
	if g == "" or d == "" then return nil end
	local global = self.db and self.db.global
	if type(global) ~= "table" or type(global.characters) ~= "table" then
		return nil
	end
	local charNode = global.characters[g]
	if type(charNode) ~= "table" then return nil end
	local dom = charNode[d]
	if type(dom) ~= "table" or type(dom.data) ~= "table" or type(dom.meta) ~= "table" then
		return nil
	end
	return dom
end

function GMS:EnsureGlobalGuildRoot(guildId)
	local gid = tostring(guildId or "")
	if gid == "" then return nil end
	if type(self.InitializeStandardDatabases) == "function" then
		self:InitializeStandardDatabases(false)
	end
	local global = self.db and self.db.global
	if type(global) ~= "table" then return nil end
	global.guilds = type(global.guilds) == "table" and global.guilds or {}
	global.guilds[gid] = type(global.guilds[gid]) == "table" and global.guilds[gid] or {}
	local root = global.guilds[gid]
	HydrateGuildMeta(self, root, gid)
	root.players = nil
	root.roster = type(root.roster) == "table" and root.roster or {}
	return root
end

function GMS:UpsertGuildPlayer(guid, playerData, guildId)
	local g = NormalizeGuid(guid)
	if g == "" then return false end
	if type(self.InitializeStandardDatabases) == "function" then
		self:InitializeStandardDatabases(false)
	end
	local global = self.db and self.db.global
	if type(global) ~= "table" then return false end
	if not EnsureGuidInGlobal(global, g) then return false end

	local gid = tostring(guildId or self:GetCurrentGuildId() or "")
	if gid == "" then return false end
	local gRoot = self:EnsureGlobalGuildRoot(gid)
	if type(gRoot) ~= "table" then return false end
	gRoot.roster = type(gRoot.roster) == "table" and gRoot.roster or {}

	local row = type(gRoot.roster[g]) == "table" and gRoot.roster[g] or {}
	gRoot.roster[g] = row
	row.guid = g

	local pd = type(playerData) == "table" and playerData or {}
	local nameFull = tostring(pd.name_full or pd.nameFull or pd.name or row.name_full or "")
	if nameFull ~= "" then row.name_full = nameFull end

	if pd.rank ~= nil then row.rank = tostring(pd.rank or "") end
	if pd.note ~= nil then row.note = tostring(pd.note or "") end
	if pd.points ~= nil then row.points = tonumber(pd.points or 0) or 0 end

	row.rank = tostring(row.rank or "")
	row.note = tostring(row.note or "")
	row.points = tonumber(row.points or 0) or 0

	local ts = tonumber(pd.updatedAtTs or pd.ts or 0) or 0
	if ts > 0 and ts < 1000000000 then
		ts = 0
	end
	if ts <= 0 then
		ts = self:GetServerTimestamp()
	end
	row.updatedAtTs = ts
	row.updatedAt = tostring(pd.updatedAt or "")
	if row.updatedAt == "" then
		row.updatedAt = self:FormatServerTimestamp(ts)
	end
	return true
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

	self:RegisterKnownGuid(id.guid)
	local charRoot = self:GetCurrentCharRoot()
	if type(charRoot) ~= "table" then
		return false, "char-root-unavailable"
	end
	charRoot.links = type(charRoot.links) == "table" and charRoot.links or {}
	local links = charRoot.links
	links.chars = type(links.chars) == "table" and links.chars or {}
	links.twinks = type(links.twinks) == "table" and links.twinks or {}
	links.twinkMeta = type(links.twinkMeta) == "table" and links.twinkMeta or {}

	local guildKey = tostring(self:GetGuildStorageKey() or "")
	local guildName = ""
	if type(GetGuildInfo) == "function" then
		guildName = tostring(GetGuildInfo("player") or "")
	end
	local seenAt = type(now) == "function" and (tonumber(now() or 0) or 0) or 0

	local row = type(links.chars[id.guid]) == "table" and links.chars[id.guid] or {}
	links.chars[id.guid] = row
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
	for i = 1, #links.twinks do
		if tostring(links.twinks[i] or "") == id.guid then
			hasTwink = true
			break
		end
	end
	if not hasTwink then
		links.twinks[#links.twinks + 1] = id.guid
	end

	local meta = type(links.twinkMeta[id.guid]) == "table" and links.twinkMeta[id.guid] or {}
	links.twinkMeta[id.guid] = meta
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
		local gKey = self:GetCurrentGuildId()
		if type(gKey) ~= "string" or gKey == "" then
			return nil
		end
		return self:EnsureGlobalGuildRoot(gKey)
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

	-- Hard reset: clear complete SavedVariables roots (not just profile/global subsets).
	local rootDb = rawget(_G, "GMS_DB")
	if type(rootDb) == "table" then
		wipe(rootDb)
	end
	_G.GMS_DB = {}

	local rootLogDb = rawget(_G, "GMS_Logging_DB")
	if type(rootLogDb) == "table" then
		wipe(rootLogDb)
	end
	_G.GMS_Logging_DB = {}

	local rootUiDb = rawget(_G, "GMS_UIDB")
	if type(rootUiDb) == "table" then
		wipe(rootUiDb)
	end
	_G.GMS_UIDB = {}

	-- Drop runtime AceDB references so no stale table proxies are reused pre-reload.
	self.db = nil
	self.logging_db = nil

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

	local function NormalizeInspectorString(raw)
		local s = tostring(raw or "")
		-- Show raw item-string in inspector instead of UI-resolved hyperlinks.
		local itemString = s:match("|H(item:[^|]+)|h")
		if type(itemString) == "string" and itemString ~= "" then
			return itemString
		end
		return s
	end

	local function FormatScalar(v)
		local tv = type(v)
		if tv == "string" then
			return EscapeString(NormalizeInspectorString(v))
		end
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
