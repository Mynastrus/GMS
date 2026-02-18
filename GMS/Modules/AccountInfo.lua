-- ============================================================================
--	GMS/Modules/AccountInfo.lua
--	AccountInfo MODULE (Ace)
--	- Central account-character link tracking/publishing/query
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G = _G
local GetTime = GetTime
local time = time
local UnitGUID = UnitGUID
local UnitLevel = UnitLevel
local UnitClass = UnitClass
local UnitFullName = UnitFullName
local GetRealmName = GetRealmName
local GetGuildInfo = GetGuildInfo
local UnitFactionGroup = UnitFactionGroup
local IsInGuild = IsInGuild
local C_Timer = C_Timer
---@diagnostic enable: undefined-global

local METADATA = {
	TYPE         = "MOD",
	INTERN_NAME  = "ACCOUNTINFO",
	SHORT_NAME   = "AccountInfo",
	DISPLAY_NAME = "Account Information",
	VERSION      = "1.0.3",
}

local ACCOUNT_CHARS_SYNC_DOMAIN = "ACCOUNT_CHARS_V1"
local ACCOUNT_CHARS_PUBLISH_MIN_INTERVAL = 20

local function AT(key, fallback, ...)
	if type(GMS.T) == "function" then
		local ok, txt = pcall(GMS.T, GMS, key, ...)
		if ok and type(txt) == "string" and txt ~= "" and txt ~= key then
			return txt
		end
	end
	if select("#", ...) > 0 then
		return string.format(tostring(fallback or key), ...)
	end
	return tostring(fallback or key)
end

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time   = (type(GetTime) == "function" and GetTime()) or nil,
		level  = tostring(level or "INFO"),
		type   = METADATA.TYPE,
		source = METADATA.SHORT_NAME,
		msg    = tostring(msg or ""),
	}
	local n = select("#", ...)
	if n > 0 then
		entry.data = { ... }
	end
	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry
	if type(GMS._LOG_NOTIFY) == "function" then
		GMS._LOG_NOTIFY(entry, idx)
	end
end

local MODULE_NAME = METADATA.INTERN_NAME
local AccountInfo = GMS:GetModule(MODULE_NAME, true)
if not AccountInfo then
	AccountInfo = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
end

if GMS and type(GMS.RegisterModule) == "function" then
	GMS:RegisterModule(AccountInfo, METADATA)
end

local OPTIONS_DEFAULTS = {
	__notice_shared = {
		type = "description",
		name = AT("ACCOUNTINFO_NOTICE_SHARED", "Alle hier eingegebenen Daten werden innerhalb der Gilde geshared."),
	},
	profileName = {
		type = "input",
		name = AT("ACCOUNTINFO_OPT_PROFILE_NAME", "Name (optional)"),
		default = "",
	},
	profileBirthday = {
		type = "input",
		name = AT("ACCOUNTINFO_OPT_BIRTHDAY", "Birthday (optional)"),
		default = "",
	},
	profileGender = {
		type = "select",
		name = AT("ACCOUNTINFO_OPT_GENDER", "Gender (optional)"),
		default = "unknown",
		values = {
			unknown = AT("ACCOUNTINFO_GENDER_UNKNOWN", "Prefer not to say"),
			male = AT("ACCOUNTINFO_GENDER_MALE", "Male"),
			female = AT("ACCOUNTINFO_GENDER_FEMALE", "Female"),
			diverse = AT("ACCOUNTINFO_GENDER_DIVERSE", "Divers"),
		},
	},
	mainCharacterGUID = {
		type = "select",
		name = AT("ACCOUNTINFO_OPT_MAINCHAR", "Main Character (guild)"),
		default = "",
		values = function()
			return AccountInfo:GetMainCharacterChoiceMap()
		end,
	},
	publishProfileNow = {
		type = "execute",
		name = AT("ACCOUNTINFO_OPT_PUBLISH_NOW", "Publish Account Info"),
		func = function()
			AccountInfo:PublishLocalAccountLinks("settings-publish", true)
		end,
	},
}

local function GetRosterModule()
	return GMS and (GMS:GetModule("ROSTER", true) or GMS:GetModule("Roster", true)) or nil
end

local function NormalizeGenderValue(raw)
	local g = tostring(raw or "unknown"):lower()
	if g == "male" or g == "female" or g == "unknown" then
		return g
	end
	if g == "divers" or g == "diverse" then
		return "diverse"
	end
	return "unknown"
end

local function GetAccountProfileFallbackStore()
	if type(_G) ~= "table" then return nil end
	_G.GMS_UIDB = type(_G.GMS_UIDB) == "table" and _G.GMS_UIDB or {}
	_G.GMS_UIDB.accountInfo = type(_G.GMS_UIDB.accountInfo) == "table" and _G.GMS_UIDB.accountInfo or {}
	_G.GMS_UIDB.accountInfo.profileSettings =
		type(_G.GMS_UIDB.accountInfo.profileSettings) == "table" and _G.GMS_UIDB.accountInfo.profileSettings or {}
	return _G.GMS_UIDB.accountInfo.profileSettings
end

function AccountInfo:PersistProfileSettings()
	local links = self:GetAccountLinkStore()
	if type(links) ~= "table" then return false end
	local opts = self._options
	if type(opts) ~= "table" and GMS and type(GMS.GetModuleOptions) == "function" then
		opts = GMS:GetModuleOptions(MODULE_NAME)
	end
	if type(opts) ~= "table" then return false end

	local payload = {
		profileName = tostring(opts.profileName or ""),
		profileBirthday = tostring(opts.profileBirthday or ""),
		profileGender = NormalizeGenderValue(opts.profileGender),
		mainCharacterGUID = tostring(opts.mainCharacterGUID or ""),
		updatedAt = (type(time) == "function" and time()) or 0,
	}

	links.profileSettings = {
		profileName = payload.profileName,
		profileBirthday = payload.profileBirthday,
		profileGender = payload.profileGender,
		mainCharacterGUID = payload.mainCharacterGUID,
		updatedAt = payload.updatedAt,
	}

	local fallback = GetAccountProfileFallbackStore()
	if type(fallback) == "table" then
		fallback.profileName = payload.profileName
		fallback.profileBirthday = payload.profileBirthday
		fallback.profileGender = payload.profileGender
		fallback.mainCharacterGUID = payload.mainCharacterGUID
		fallback.updatedAt = payload.updatedAt
	end
	return true
end

function AccountInfo:RestoreProfileSettings()
	local links = self:GetAccountLinkStore()
	local opts = self._options
	if type(opts) ~= "table" and GMS and type(GMS.GetModuleOptions) == "function" then
		opts = GMS:GetModuleOptions(MODULE_NAME)
	end
	if type(opts) ~= "table" then return false end

	local s = nil
	if type(links) == "table" and type(links.profileSettings) == "table" then
		s = links.profileSettings
	end
	local fallback = GetAccountProfileFallbackStore()
	if type(s) ~= "table" and type(fallback) == "table" then
		s = fallback
	elseif type(s) == "table" and type(fallback) == "table" then
		-- Merge fallback values when primary store is empty/incomplete.
		if tostring(s.profileName or "") == "" and tostring(fallback.profileName or "") ~= "" then
			s.profileName = tostring(fallback.profileName or "")
		end
		if tostring(s.profileBirthday or "") == "" and tostring(fallback.profileBirthday or "") ~= "" then
			s.profileBirthday = tostring(fallback.profileBirthday or "")
		end
		if tostring(s.mainCharacterGUID or "") == "" and tostring(fallback.mainCharacterGUID or "") ~= "" then
			s.mainCharacterGUID = tostring(fallback.mainCharacterGUID or "")
		end
		if NormalizeGenderValue(s.profileGender) == "unknown" and NormalizeGenderValue(fallback.profileGender) ~= "unknown" then
			s.profileGender = tostring(fallback.profileGender or "unknown")
		end
	end
	if type(s) ~= "table" then
		return false
	end

	local storedName = tostring(s.profileName or "")
	local storedBirthday = tostring(s.profileBirthday or "")
	local storedMainGuid = tostring(s.mainCharacterGUID or "")
	local storedGender = NormalizeGenderValue(s.profileGender)

	if storedName ~= "" then
		opts.profileName = storedName
	elseif opts.profileName == nil then
		opts.profileName = ""
	end

	if storedBirthday ~= "" then
		opts.profileBirthday = storedBirthday
	elseif opts.profileBirthday == nil then
		opts.profileBirthday = ""
	end

	if storedMainGuid ~= "" or tostring(opts.mainCharacterGUID or "") == "" then
		opts.mainCharacterGUID = storedMainGuid
	end

	if storedGender ~= "unknown" or NormalizeGenderValue(opts.profileGender) == "unknown" then
		opts.profileGender = storedGender
	elseif opts.profileGender == nil then
		opts.profileGender = "unknown"
	end
	return true
end

local function BuildLocalPlayerNameData()
	local name, realm = "", ""
	if type(UnitFullName) == "function" then
		local n, r = UnitFullName("player")
		if type(n) == "string" then name = n end
		if type(r) == "string" then realm = r end
	end
	if realm == "" and type(GetRealmName) == "function" then
		local r = GetRealmName()
		if type(r) == "string" and r ~= "" then realm = r end
	end
	name = tostring(name or "")
	realm = tostring(realm or "")
	if name == "" then return "", "", "" end
	if realm ~= "" then return name .. "-" .. realm, name, realm end
	return name, name, realm
end

local function GetCurrentGuildStorageKeySafe()
	if not IsInGuild or not IsInGuild() then
		return "", ""
	end
	local guildName = ""
	if type(GetGuildInfo) == "function" then
		local g = GetGuildInfo("player")
		if type(g) == "string" then guildName = g end
	end
	local guildKey = ""
	if type(GMS.GetGuildStorageKey) == "function" then
		local ok, key = pcall(GMS.GetGuildStorageKey, GMS)
		if ok and type(key) == "string" then guildKey = key end
	end
	if guildKey == "" and guildName ~= "" then
		local realm = (type(GetRealmName) == "function" and tostring(GetRealmName() or "")) or ""
		local faction = (type(UnitFactionGroup) == "function" and tostring(UnitFactionGroup("player") or "")) or ""
		if realm ~= "" and faction ~= "" then
			guildKey = string.format("%s|%s|%s", realm, faction, guildName)
		end
	end
	return guildKey, guildName
end

function AccountInfo:GetAccountLinkStore()
	if GMS and type(GMS.InitializeStandardDatabases) == "function" then
		GMS:InitializeStandardDatabases(false)
	end
	if not GMS or type(GMS.db) ~= "table" or type(GMS.db.global) ~= "table" then
		return nil
	end
	local global = GMS.db.global
	global.accountLinks = type(global.accountLinks) == "table" and global.accountLinks or {}
	global.twinks = type(global.twinks) == "table" and global.twinks or {}
	global.twinkMeta = type(global.twinkMeta) == "table" and global.twinkMeta or {}
	local links = global.accountLinks
	links.chars = type(links.chars) == "table" and links.chars or {}
	links.synced = type(links.synced) == "table" and links.synced or {}
	return links
end

function AccountInfo:InitializeOptions()
	if GMS and type(GMS.RegisterModuleOptions) == "function" then
		pcall(function()
			GMS:RegisterModuleOptions(MODULE_NAME, OPTIONS_DEFAULTS, "GLOBAL")
		end)
	end
	if GMS and type(GMS.GetModuleOptions) == "function" then
		local ok, opts = pcall(GMS.GetModuleOptions, GMS, MODULE_NAME)
		if ok and type(opts) == "table" then
			self._options = opts
			self:RestoreProfileSettings()
		end
	end
end

local function BuildAccountCharsListForGuild(links, guildKey)
	local out = {}
	local key = tostring(guildKey or "")
	if key == "" then return out end
	if type(links) ~= "table" or type(links.chars) ~= "table" then return out end
	for guid, entry in pairs(links.chars) do
		if type(entry) == "table" and tostring(entry.guildKey or "") == key then
			out[#out + 1] = {
				guid = tostring(guid or ""),
				name_full = tostring(entry.name_full or entry.name or guid or "-"),
				name = tostring(entry.name or ""),
				realm = tostring(entry.realm or ""),
				level = tonumber(entry.level or 0) or 0,
				class = tostring(entry.class or "-"),
				classFile = tostring(entry.classFile or ""),
				guild = tostring(entry.guild or ""),
				guildKey = key,
				lastSeenAt = tonumber(entry.lastSeenAt or 0) or 0,
			}
		end
	end
	table.sort(out, function(a, b)
		return tostring(a.name_full or "") < tostring(b.name_full or "")
	end)
	return out
end

local function BuildRowsFromGlobalTwinks(global, selectedGuid)
	local out = {}
	if type(global) ~= "table" then return out end
	local twinks = type(global.twinks) == "table" and global.twinks or nil
	if type(twinks) ~= "table" or #twinks <= 0 then return out end
	local selected = tostring(selectedGuid or "")
	local metaByGuid = type(global.twinkMeta) == "table" and global.twinkMeta or {}
	local selectedGuildKey = ""
	if selected ~= "" and type(metaByGuid[selected]) == "table" then
		selectedGuildKey = tostring(metaByGuid[selected].guildKey or "")
	end
	if selectedGuildKey == "" then
		selectedGuildKey = tostring(select(1, GetCurrentGuildStorageKeySafe()) or "")
	end
	for i = 1, #twinks do
		local guid = tostring(twinks[i] or "")
		if guid ~= "" then
			local meta = type(metaByGuid[guid]) == "table" and metaByGuid[guid] or {}
			local rowGuildKey = tostring(meta.guildKey or selectedGuildKey)
			if rowGuildKey ~= "" and rowGuildKey == selectedGuildKey then
				out[#out + 1] = {
					guid = guid,
					name_full = tostring(meta.name_full or meta.name or guid),
					name = tostring(meta.name or ""),
					realm = tostring(meta.realm or ""),
					level = tonumber(meta.level or 0) or 0,
					class = tostring(meta.class or "-"),
					classFile = tostring(meta.classFile or ""),
					guild = tostring(meta.guild or ""),
					guildKey = rowGuildKey,
					lastSeenAt = tonumber(meta.lastSeenAt or 0) or 0,
				}
			end
		end
	end
	table.sort(out, function(a, b)
		return tostring(a.name_full or "") < tostring(b.name_full or "")
	end)
	return out
end

local function BuildGuildVerifiedLinkedRows(selectedGuid, chars, fallbackGuildKey, sourceLabel)
	local roster = GetRosterModule()
	if type(roster) ~= "table" or type(roster.GetMemberByGUID) ~= "function" then
		return {}, false, "Roster module unavailable."
	end

	local guid = tostring(selectedGuid or "")
	if guid == "" then return {}, false, "No character GUID available." end
	if type(chars) ~= "table" or #chars <= 0 then
		return {}, false, "No same-account guild characters recorded yet."
	end

	local selectedGuildKey = tostring(fallbackGuildKey or "")
	for i = 1, #chars do
		local row = chars[i]
		if type(row) == "table" and tostring(row.guid or "") == guid then
			local rowGuildKey = tostring(row.guildKey or "")
			if rowGuildKey ~= "" then selectedGuildKey = rowGuildKey end
			break
		end
	end
	if selectedGuildKey == "" then
		return {}, false, "Selected character has no guild link."
	end
	local currentGuildKey = select(1, GetCurrentGuildStorageKeySafe())
	if tostring(currentGuildKey or "") == "" or tostring(currentGuildKey or "") ~= selectedGuildKey then
		return {}, false, "Selected character is outside the current guild context."
	end
	local currentMember = roster:GetMemberByGUID(guid)
	if type(currentMember) ~= "table" then
		return {}, false, "Selected character is not currently in guild roster."
	end

	local rows = {}
	for i = 1, #chars do
		local entry = chars[i]
		if type(entry) == "table" then
			local otherGuid = tostring(entry.guid or "")
			local otherGuildKey = tostring(entry.guildKey or selectedGuildKey)
			if otherGuid ~= "" and otherGuid ~= guid and otherGuildKey == selectedGuildKey then
				local member = roster:GetMemberByGUID(otherGuid)
				if type(member) == "table" then
					rows[#rows + 1] = {
						guid = otherGuid,
						name_full = tostring(member.name_full or member.name or entry.name_full or entry.name or "-"),
						level = tonumber(member.level or entry.level or 0) or 0,
						class = tostring(member.class or entry.class or "-"),
						classFile = tostring(member.classFileName or entry.classFile or ""),
						online = member.online == true,
					}
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		return tostring(a.name_full or "") < tostring(b.name_full or "")
	end)
	if #rows <= 0 then
		return rows, false, "No same-account guild characters currently in guild roster."
	end
	return rows, true, tostring(sourceLabel or "Account guild links (guild-verified)")
end

local function BuildStoredLinkedRows(selectedGuid, chars, fallbackGuildKey, sourceLabel)
	local guid = tostring(selectedGuid or "")
	if guid == "" then return {}, false, "No character GUID available." end
	if type(chars) ~= "table" or #chars <= 0 then
		return {}, false, "No same-account characters stored yet."
	end

	local selectedGuildKey = tostring(fallbackGuildKey or "")
	for i = 1, #chars do
		local row = chars[i]
		if type(row) == "table" and tostring(row.guid or "") == guid then
			local rowGuildKey = tostring(row.guildKey or "")
			if rowGuildKey ~= "" then selectedGuildKey = rowGuildKey end
			break
		end
	end
	if selectedGuildKey == "" then
		selectedGuildKey = tostring(select(1, GetCurrentGuildStorageKeySafe()) or "")
	end
	if selectedGuildKey == "" then
		return {}, false, "No guild context available."
	end

	local rows = {}
	for i = 1, #chars do
		local entry = chars[i]
		if type(entry) == "table" then
			local otherGuid = tostring(entry.guid or "")
			local otherGuildKey = tostring(entry.guildKey or selectedGuildKey)
			if otherGuid ~= "" and otherGuid ~= guid and otherGuildKey == selectedGuildKey then
				rows[#rows + 1] = {
					guid = otherGuid,
					name_full = tostring(entry.name_full or entry.name or otherGuid),
					level = tonumber(entry.level or 0) or 0,
					class = tostring(entry.class or "-"),
					classFile = tostring(entry.classFile or ""),
					online = false,
				}
			end
		end
	end
	table.sort(rows, function(a, b)
		return tostring(a.name_full or "") < tostring(b.name_full or "")
	end)
	if #rows <= 0 then
		return rows, false, "No same-account guild characters in stored links."
	end
	return rows, true, tostring(sourceLabel or "Account links (stored)")
end

local function BuildAccountCharsDigest(guildKey, chars)
	local parts = { tostring(guildKey or "") }
	for i = 1, #chars do
		local row = chars[i]
		parts[#parts + 1] = string.format(
			"%s:%s:%s:%d:%s",
			tostring(row.guid or ""),
			tostring(row.name_full or ""),
			tostring(row.classFile or ""),
			tonumber(row.level or 0) or 0,
			tostring(row.guildKey or "")
		)
	end
	return table.concat(parts, "|")
end

function AccountInfo:PublishLocalAccountLinks(reason, force)
	local comm = GMS and GMS.Comm
	if type(comm) ~= "table" or type(comm.PublishRecord) ~= "function" then
		LOCAL_LOG("WARN", "Account links publish unavailable", "comm-unavailable", tostring(reason or "unknown"))
		return false, "comm-unavailable"
	end
	local guid = (type(UnitGUID) == "function") and tostring(UnitGUID("player") or "") or ""
	if guid == "" then
		LOCAL_LOG("WARN", "Account links publish unavailable", "no-player-guid", tostring(reason or "unknown"))
		return false, "no-player-guid"
	end

	local links = self:GetAccountLinkStore()
	if type(links) ~= "table" or type(links.chars) ~= "table" then
		LOCAL_LOG("WARN", "Account links publish unavailable", "store-unavailable", tostring(reason or "unknown"))
		return false, "store-unavailable"
	end
	local base = links.chars[guid]
	if type(base) ~= "table" then
		LOCAL_LOG("WARN", "Account links publish unavailable", "player-row-missing", tostring(reason or "unknown"))
		return false, "player-row-missing"
	end

	local guildKey = tostring(base.guildKey or "")
	if guildKey == "" then return false, "no-guild" end
	local chars = BuildAccountCharsListForGuild(links, guildKey)
	if #chars <= 0 then return false, "no-same-guild-chars" end

	local digest = BuildAccountCharsDigest(guildKey, chars)
	local nowTs = (type(GetTime) == "function" and GetTime()) or 0
	local lastTs = tonumber(self._accountCharsLastPublishAt or 0) or 0
	local forcePublish = (force == true)
	if not forcePublish and (nowTs - lastTs) < ACCOUNT_CHARS_PUBLISH_MIN_INTERVAL then
		return false, "cooldown"
	end
	if not forcePublish and digest == tostring(self._accountCharsLastDigest or "") then
		return false, "unchanged"
	end

	local payload = {
		schema = 1,
		guildKey = guildKey,
		guild = tostring(base.guild or ""),
		sourceGuid = guid,
		reason = tostring(reason or "unknown"),
		chars = chars,
		characters = {},
		profile = {},
	}
	local opts = self._options
	if type(opts) ~= "table" and GMS and type(GMS.GetModuleOptions) == "function" then
		opts = GMS:GetModuleOptions(MODULE_NAME)
	end
	local mainGuid = type(opts) == "table" and tostring(opts.mainCharacterGUID or "") or ""
	local mainName = ""
	for i = 1, #chars do
		local row = chars[i]
		if type(row) == "table" and tostring(row.guid or "") == mainGuid then
			mainName = tostring(row.name_full or "")
			break
		end
	end
	payload.profile = {
		name = type(opts) == "table" and tostring(opts.profileName or "") or "",
		birthday = type(opts) == "table" and tostring(opts.profileBirthday or "") or "",
		gender = NormalizeGenderValue(type(opts) == "table" and opts.profileGender or "unknown"),
		mainCharacterGUID = mainGuid,
		mainCharacterName = mainName,
	}
	for i = 1, #chars do
		payload.characters[#payload.characters + 1] = tostring(chars[i].name_full or chars[i].guid or "-")
	end

	local ok, publishReason = comm:PublishRecord(ACCOUNT_CHARS_SYNC_DOMAIN, guid, payload, { updatedAt = nowTs })
	if ok then
		self._accountCharsLastDigest = digest
		self._accountCharsLastPublishAt = nowTs
		LOCAL_LOG("COMM", "Account links published", tostring(#chars), tostring(reason or "unknown"))
		return true, "published"
	end
	LOCAL_LOG("WARN", "Account links publish failed", tostring(publishReason or "unknown"), tostring(reason or "unknown"))
	return false, "publish-failed"
end

function AccountInfo:GetMainCharacterChoiceMap()
	local links = self:GetAccountLinkStore()
	local guid = (type(UnitGUID) == "function") and tostring(UnitGUID("player") or "") or ""
	local base = (type(links) == "table" and type(links.chars) == "table") and links.chars[guid] or nil
	local guildKey = type(base) == "table" and tostring(base.guildKey or "") or ""
	local chars = BuildAccountCharsListForGuild(links, guildKey)

	local list = {}
	for i = 1, #chars do
		local row = chars[i]
		local rowGuid = tostring(row.guid or "")
		if rowGuid ~= "" then
			list[rowGuid] = tostring(row.name_full or rowGuid)
		end
	end

	if GMS and type(GMS.db) == "table" and type(GMS.db.global) == "table" then
		local fromTwinks = BuildRowsFromGlobalTwinks(GMS.db.global, guid)
		for i = 1, #fromTwinks do
			local row = fromTwinks[i]
			local rowGuid = tostring(row.guid or "")
			if rowGuid ~= "" and list[rowGuid] == nil then
				list[rowGuid] = tostring(row.name_full or rowGuid)
			end
		end
	end

	if next(list) == nil and guid ~= "" then
		local nameFull = type(base) == "table" and tostring(base.name_full or guid) or guid
		list[guid] = nameFull
	end
	return list
end

function AccountInfo:TrackLocalAccountCharacter(reason)
	local guid = (type(UnitGUID) == "function") and tostring(UnitGUID("player") or "") or ""
	if guid == "" then return false end
	local links = self:GetAccountLinkStore()
	if type(links) ~= "table" or type(links.chars) ~= "table" then return false end

	local nameFull, name, realm = BuildLocalPlayerNameData()
	if nameFull == "" then nameFull = guid end
	local className, classFile = nil, nil
	if type(UnitClass) == "function" then className, classFile = UnitClass("player") end
	local level = (type(UnitLevel) == "function") and tonumber(UnitLevel("player") or 0) or 0
	local guildKey, guildName = GetCurrentGuildStorageKeySafe()
	guildKey = tostring(guildKey or "")
	guildName = tostring(guildName or "")

	links.chars[guid] = links.chars[guid] or {}
	local row = links.chars[guid]
	local changed = false

	local function SetTextField(key, value, countAsChange)
		local v = tostring(value or "")
		if tostring(row[key] or "") ~= v then
			row[key] = v
			if countAsChange ~= false then changed = true end
		end
	end
	local function SetNumberField(key, value)
		local v = tonumber(value) or 0
		if tonumber(row[key] or -1) ~= v then
			row[key] = v
			changed = true
		end
	end

	SetTextField("guid", guid)
	SetTextField("name", name)
	SetTextField("realm", realm)
	SetTextField("name_full", nameFull)
	SetTextField("class", className)
	SetTextField("classFile", classFile)
	SetNumberField("level", level)
	SetTextField("guild", guildName)
	SetTextField("guildKey", guildKey)
	SetTextField("lastSeenReason", tostring(reason or "unknown"), false)

	local nowTs = (type(time) == "function" and time()) or 0
	local oldSeenAt = tonumber(row.lastSeenAt or 0) or 0
	if changed or (tonumber(nowTs) or 0) - oldSeenAt >= 60 then
		row.lastSeenAt = tonumber(nowTs) or 0
	end

	if changed then
		LOCAL_LOG("INFO", "Local account character tracked", guid, nameFull, guildKey ~= "" and guildKey or "no-guild")
	end

	if GMS and type(GMS.db) == "table" and type(GMS.db.global) == "table" then
		local global = GMS.db.global
		global.twinks = type(global.twinks) == "table" and global.twinks or {}
		global.twinkMeta = type(global.twinkMeta) == "table" and global.twinkMeta or {}
		local exists = false
		for i = 1, #global.twinks do
			if tostring(global.twinks[i] or "") == guid then exists = true break end
		end
		if not exists then global.twinks[#global.twinks + 1] = guid end

		local meta = type(global.twinkMeta[guid]) == "table" and global.twinkMeta[guid] or {}
		global.twinkMeta[guid] = meta
		meta.guid = guid
		meta.name = tostring(name or "")
		meta.realm = tostring(realm or "")
		meta.name_full = tostring(nameFull or guid)
		meta.class = tostring(className or "")
		meta.classFile = tostring(classFile or "")
		meta.level = tonumber(level or 0) or 0
		meta.guild = tostring(guildName or "")
		meta.guildKey = tostring(guildKey or "")
		meta.lastSeenAt = tonumber(nowTs) or 0
	end

	if tostring(reason or "") ~= "query" then
		self:PublishLocalAccountLinks(reason, changed)
	end
	return true
end

local function DoesSyncedRecordMatchGuid(record, guid)
	if type(record) ~= "table" or type(record.payload) ~= "table" then return false end
	local g = tostring(guid or "")
	if g == "" then return false end
	if tostring(record.charGUID or "") == g or tostring(record.originGUID or "") == g then
		return true
	end
	local chars = record.payload.chars
	if type(chars) ~= "table" then return false end
	for i = 1, #chars do
		local row = chars[i]
		if type(row) == "table" and tostring(row.guid or "") == g then
			return true
		end
	end
	return false
end

function AccountInfo:StoreSyncedAccountRecord(record, reason)
	if type(record) ~= "table" or type(record.payload) ~= "table" then
		return false
	end
	local domain = tostring(record.domain or "")
	if domain ~= ACCOUNT_CHARS_SYNC_DOMAIN then
		return false
	end
	local key = tostring(record.key or "")
	if key == "" then
		return false
	end

	local links = self:GetAccountLinkStore()
	if type(links) ~= "table" then
		return false
	end
	links.synced = type(links.synced) == "table" and links.synced or {}

	local payload = record.payload
	local charsIn = type(payload.chars) == "table" and payload.chars or {}
	local charsOut = {}
	for i = 1, #charsIn do
		local row = charsIn[i]
		if type(row) == "table" then
			local guid = tostring(row.guid or "")
			if guid ~= "" then
				charsOut[#charsOut + 1] = {
					guid = guid,
					name_full = tostring(row.name_full or row.name or guid),
					name = tostring(row.name or ""),
					realm = tostring(row.realm or ""),
					level = tonumber(row.level or 0) or 0,
					class = tostring(row.class or "-"),
					classFile = tostring(row.classFile or ""),
					guild = tostring(row.guild or payload.guild or ""),
					guildKey = tostring(row.guildKey or payload.guildKey or ""),
					lastSeenAt = tonumber(row.lastSeenAt or 0) or 0,
				}
			end
		end
	end

	links.synced[key] = {
		key = key,
		originGUID = tostring(record.originGUID or ""),
		charGUID = tostring(record.charGUID or ""),
		domain = domain,
		seq = tonumber(record.seq or 0) or 0,
		updatedAt = tonumber(record.updatedAt or 0) or 0,
		guildKey = tostring(payload.guildKey or ""),
		guild = tostring(payload.guild or ""),
		reason = tostring(reason or "record"),
		chars = charsOut,
		profile = type(payload.profile) == "table" and {
			name = tostring(payload.profile.name or ""),
			birthday = tostring(payload.profile.birthday or ""),
			gender = tostring(payload.profile.gender or "unknown"),
			mainCharacterGUID = tostring(payload.profile.mainCharacterGUID or ""),
			mainCharacterName = tostring(payload.profile.mainCharacterName or ""),
		} or nil,
		savedAt = (type(time) == "function" and time()) or 0,
	}
	return true
end

function AccountInfo:HydrateSyncedAccountStoreFromComm(force)
	local nowTs = (type(GetTime) == "function" and GetTime()) or 0
	if force ~= true and (nowTs - tonumber(self._lastSyncedHydrationAt or 0)) < 10 then
		return false
	end
	self._lastSyncedHydrationAt = nowTs

	local comm = GMS and GMS.Comm
	if type(comm) ~= "table" or type(comm.GetRecordsByDomain) ~= "function" then
		return false
	end
	local records = comm:GetRecordsByDomain(ACCOUNT_CHARS_SYNC_DOMAIN)
	if type(records) ~= "table" or #records <= 0 then
		return false
	end
	local changed = false
	for i = 1, #records do
		if self:StoreSyncedAccountRecord(records[i], "comm-hydrate") then
			changed = true
		end
	end
	return changed
end

function AccountInfo:GetBestStoredSyncedRecordForGuid(guid)
	local g = tostring(guid or "")
	if g == "" then return nil end
	local links = self:GetAccountLinkStore()
	if type(links) ~= "table" or type(links.synced) ~= "table" then
		return nil
	end

	local best = nil
	local bestUpdated = -1
	local bestSeq = -1
	for _, rec in pairs(links.synced) do
		if type(rec) == "table" and type(rec.chars) == "table" then
			local wrapped = {
				charGUID = rec.charGUID,
				originGUID = rec.originGUID,
				payload = { chars = rec.chars },
			}
			if DoesSyncedRecordMatchGuid(wrapped, g) then
				local updated = tonumber(rec.updatedAt or 0) or 0
				local seq = tonumber(rec.seq or 0) or 0
				if updated > bestUpdated or (updated == bestUpdated and seq > bestSeq) then
					best = rec
					bestUpdated = updated
					bestSeq = seq
				end
			end
		end
	end
	return best
end

function AccountInfo:GetSyncedAccountGuildCharactersForGuid(guid)
	local g = tostring(guid or "")
	if g == "" then return {}, false, "No character GUID available." end

	self:HydrateSyncedAccountStoreFromComm(false)
	local stored = self:GetBestStoredSyncedRecordForGuid(g)
	if type(stored) == "table" and type(stored.chars) == "table" then
		local rows, hasData, source = BuildGuildVerifiedLinkedRows(
			g,
			stored.chars,
			tostring(stored.guildKey or ""),
			"Synced account guild links (saved, guild-verified)"
		)
		if hasData then
			return rows, true, source
		end
		local fallbackRows, fallbackHasData, fallbackSource = BuildStoredLinkedRows(
			g,
			stored.chars,
			tostring(stored.guildKey or ""),
			"Synced account guild links (saved, stored)"
		)
		if fallbackHasData then
			return fallbackRows, true, fallbackSource
		end
	end

	local comm = GMS and GMS.Comm
	if type(comm) ~= "table" or type(comm.GetRecordsByDomain) ~= "function" then
		return {}, false, "Comm record store unavailable."
	end

	local records = comm:GetRecordsByDomain(ACCOUNT_CHARS_SYNC_DOMAIN)
	if type(records) ~= "table" or #records <= 0 then
		return {}, false, "No synced account-link record found for selected character."
	end

	local best = nil
	local bestUpdated = -1
	local bestSeq = -1
	for i = 1, #records do
		local rec = records[i]
		if type(rec) == "table" and type(rec.payload) == "table" then
			local match = false
			if tostring(rec.charGUID or "") == g or tostring(rec.originGUID or "") == g then
				match = true
			else
				local chars = rec.payload.chars
				if type(chars) == "table" then
					for j = 1, #chars do
						local row = chars[j]
						if type(row) == "table" and tostring(row.guid or "") == g then
							match = true
							break
						end
					end
				end
			end
			if match then
				local updated = tonumber(rec.updatedAt) or 0
				local seq = tonumber(rec.seq) or 0
				if updated > bestUpdated or (updated == bestUpdated and seq > bestSeq) then
					best = rec
					bestUpdated = updated
					bestSeq = seq
				end
			end
		end
	end

	if type(best) ~= "table" or type(best.payload) ~= "table" then
		return {}, false, "No synced account-link record found for selected character."
	end
	self:StoreSyncedAccountRecord(best, "comm-best")
	local verifiedRows, verifiedHasData, verifiedSource = BuildGuildVerifiedLinkedRows(
		g,
		type(best.payload.chars) == "table" and best.payload.chars or {},
		tostring(best.payload.guildKey or ""),
		"Synced account guild links (guild-verified)"
	)
	if verifiedHasData then
		return verifiedRows, true, verifiedSource
	end
	return BuildStoredLinkedRows(
		g,
		type(best.payload.chars) == "table" and best.payload.chars or {},
		tostring(best.payload.guildKey or ""),
		"Synced account guild links (stored)"
	)
end

function AccountInfo:GetLinkedAccountGuildCharactersForGuid(guid)
	local g = tostring(guid or "")
	if g == "" then return {}, false, "No character GUID available." end

	self:TrackLocalAccountCharacter("query")

	local links = self:GetAccountLinkStore()
	if type(links) == "table" and type(links.chars) == "table" then
		local base = links.chars[g]
		if type(base) == "table" then
			local guildKey = tostring(base.guildKey or "")
			local localChars = BuildAccountCharsListForGuild(links, guildKey)
			local rows, hasData, source = BuildGuildVerifiedLinkedRows(
				g,
				localChars,
				guildKey,
				"Local account guild links (guild-verified)"
			)
			if hasData then return rows, true, source end
			local fallbackRows, fallbackHasData, fallbackSource = BuildStoredLinkedRows(
				g,
				localChars,
				guildKey,
				"Local account guild links (stored)"
			)
			if fallbackHasData then return fallbackRows, true, fallbackSource end

			local syncedRows, syncedHasData, syncedSource = self:GetSyncedAccountGuildCharactersForGuid(g)
			if syncedHasData then return syncedRows, true, syncedSource end

			if GMS and type(GMS.db) == "table" and type(GMS.db.global) == "table" then
				local globalRows = BuildRowsFromGlobalTwinks(GMS.db.global, g)
				local globalVerifiedRows, globalHasData, globalSource = BuildGuildVerifiedLinkedRows(
					g, globalRows, tostring(base.guildKey or ""), "Global twink list (guild-verified)"
				)
				if globalHasData then return globalVerifiedRows, true, globalSource end
				local globalFallbackRows, globalFallbackHasData, globalFallbackSource = BuildStoredLinkedRows(
					g, globalRows, tostring(base.guildKey or ""), "Global twink list (stored)"
				)
				if globalFallbackHasData then return globalFallbackRows, true, globalFallbackSource end
			end
			return rows, false, source
		end
	end

	local syncedRows, syncedHasData, syncedSource = self:GetSyncedAccountGuildCharactersForGuid(g)
	if syncedHasData then return syncedRows, true, syncedSource end

	if GMS and type(GMS.db) == "table" and type(GMS.db.global) == "table" then
		local globalRows = BuildRowsFromGlobalTwinks(GMS.db.global, g)
		local globalVerifiedRows, globalHasData, globalSource = BuildGuildVerifiedLinkedRows(
			g, globalRows, "", "Global twink list (guild-verified)"
		)
		if globalHasData then return globalVerifiedRows, true, globalSource end
		local globalFallbackRows, globalFallbackHasData, globalFallbackSource = BuildStoredLinkedRows(
			g, globalRows, "", "Global twink list (stored)"
		)
		if globalFallbackHasData then return globalFallbackRows, true, globalFallbackSource end
	end

	return syncedRows, false, syncedSource
end

function AccountInfo:OnEnable()
	self:InitializeOptions()
	self:RestoreProfileSettings()
	self:PersistProfileSettings()
	self:HydrateSyncedAccountStoreFromComm(true)
	local comm = GMS and GMS.Comm
	if type(comm) == "table" and type(comm.RegisterRecordListener) == "function" then
		comm:RegisterRecordListener(ACCOUNT_CHARS_SYNC_DOMAIN, function(record)
			AccountInfo:StoreSyncedAccountRecord(record, "comm-listener")
		end)
	end
	if C_Timer and type(C_Timer.After) == "function" then
		C_Timer.After(1.0, function()
			AccountInfo:TrackLocalAccountCharacter("enable-delay")
		end)
	end
	self:RegisterEvent("PLAYER_LOGIN", function()
		AccountInfo:TrackLocalAccountCharacter("player-login")
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		AccountInfo:TrackLocalAccountCharacter("entering-world")
	end)
	self:RegisterEvent("GUILD_ROSTER_UPDATE", function()
		AccountInfo:TrackLocalAccountCharacter("guild-roster-update")
	end)
	self:RegisterMessage("GMS_CONFIG_CHANGED", function(_, targetKey, key)
		if tostring(targetKey or "") ~= MODULE_NAME then return end
		AccountInfo:PersistProfileSettings()
		if key == "profileName" or key == "profileBirthday" or key == "profileGender" or key == "mainCharacterGUID" then
			AccountInfo:PublishLocalAccountLinks("profile-update-" .. tostring(key), true)
		end
	end)
	self:TrackLocalAccountCharacter("enable")
	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
end

function AccountInfo:OnDisable()
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end

-- Ensure options are available in Settings even before module enable timing kicks in.
pcall(function()
	if type(AccountInfo) == "table" and type(AccountInfo.InitializeOptions) == "function" then
		AccountInfo:InitializeOptions()
	end
end)
