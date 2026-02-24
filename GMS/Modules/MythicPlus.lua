local _, GMS = ...

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G              = _G
local GetTime         = GetTime
local UnitGUID        = UnitGUID
local C_ChallengeMode = C_ChallengeMode
local C_MythicPlus    = C_MythicPlus
local time            = time
local IsLoggedIn      = IsLoggedIn
local C_Timer         = C_Timer
local select          = select
local ipairs          = ipairs
local pairs           = pairs
local tostring        = tostring
local pcall           = pcall
local type            = type
local table           = table
local tonumber        = tonumber
---@diagnostic enable: undefined-global

local METADATA = {
	TYPE         = "MOD",
	INTERN_NAME  = "MythicPlus",
	SHORT_NAME   = "MYTHIC",
	DISPLAY_NAME = "Mythic Plus",
	VERSION      = "1.1.11",
}

-- Ensure global log buffer exists
GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return GetTime and GetTime() or nil
end

-- Local logging function
local function LOCAL_LOG(level, msg, ...)
	local entry = {
		timestamp = now(),
		level     = tostring(level or "INFO"),
		type      = METADATA.TYPE,
		source    = METADATA.SHORT_NAME,
		message   = tostring(msg or ""),
	}

	local n = select("#", ...)
	if n > 0 then
		entry.data = { ... }
	end

	local buffer = GMS._LOG_BUFFER
	local idx = #buffer + 1
	buffer[idx] = entry

	if GMS._LOG_NOTIFY then
		GMS._LOG_NOTIFY(entry, idx)
	end
end

-- ###########################################################################
-- #	MODULE
-- ###########################################################################

local MODULE_NAME = "MythicPlus"
local MYTHIC_SYNC_DOMAIN = "MYTHICPLUS_V2"

local MYTHIC = GMS:GetModule(MODULE_NAME, true)
if not MYTHIC then
	MYTHIC = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
end

-- Registration
if GMS and type(GMS.RegisterModule) == "function" then
	GMS:RegisterModule(MYTHIC, METADATA)
end

-- ###########################################################################
-- #	UTILS
-- ###########################################################################

local function _getCharKey()
	local guid = UnitGUID and UnitGUID("player") or nil
	if guid and guid ~= "" then return guid end
	return nil
end

local function _safeNum(v)
	return tonumber(v) or 0
end

local function _normalizeRunInfo(info, completed)
	if type(info) ~= "table" then return nil end
	return {
		level = _safeNum(info.level),
		score = _safeNum(info.dungeonScore),
		completed = completed == true,
	}
end

local function _normalizeAffixes(rawAffixes)
	local out = {}
	if type(rawAffixes) ~= "table" then return out end
	for i = 1, #rawAffixes do
		local row = rawAffixes[i]
		local affixID = tonumber(type(row) == "table" and (row.id or row.affixID) or row) or 0
		if affixID > 0 then
			out[#out + 1] = affixID
		end
	end
	table.sort(out, function(a, b) return a < b end)
	return out
end

local function _encodeDungeonData(row)
	if type(row) ~= "table" then return "" end
	local fl = _safeNum(row.fl or row.fortifiedLevel)
	local fs = _safeNum(row.fs or row.fortifiedScore)
	local fc = ((row.fc == true) or (row.fortifiedCompleted == true)) and 1 or 0
	local tl = _safeNum(row.tl or row.tyrannicalLevel)
	local ts = _safeNum(row.ts or row.tyrannicalScore)
	local tc = ((row.tc == true) or (row.tyrannicalCompleted == true)) and 1 or 0
	local tex = _safeNum(row.t or row.texture)
	return table.concat({
		tostring(fl),
		tostring(fs),
		tostring(fc),
		tostring(tl),
		tostring(ts),
		tostring(tc),
		tostring(tex),
	}, ":")
end

local function _decodeDungeonData(raw)
	local v = tostring(raw or "")
	local fl, fs, fc, tl, ts, tc, t = v:match("^(%-?%d+):(%-?%d+):([01]):(%-?%d+):(%-?%d+):([01]):(%-?%d+)$")
	if fl then
		local out = {
			fl = _safeNum(fl),
			fs = _safeNum(fs),
			fc = tostring(fc) == "1",
			tl = _safeNum(tl),
			ts = _safeNum(ts),
			tc = tostring(tc) == "1",
			t = _safeNum(t),
		}
		out.s = _safeNum(out.fs) + _safeNum(out.ts)
		out.l = (_safeNum(out.fl) > _safeNum(out.tl)) and _safeNum(out.fl) or _safeNum(out.tl)
		out.c = (out.fc == true) or (out.tc == true)
		return out
	end

	-- Backward compatibility: prior V2 format with affixCsv suffix.
	fl, fs, fc, tl, ts, tc, t = v:match("^(%-?%d+):(%-?%d+):([01]):(%-?%d+):(%-?%d+):([01]):(%-?%d+):[^:]*$")
	if fl then
		local out = {
			fl = _safeNum(fl),
			fs = _safeNum(fs),
			fc = tostring(fc) == "1",
			tl = _safeNum(tl),
			ts = _safeNum(ts),
			tc = tostring(tc) == "1",
			t = _safeNum(t),
		}
		out.s = _safeNum(out.fs) + _safeNum(out.ts)
		out.l = (_safeNum(out.fl) > _safeNum(out.tl)) and _safeNum(out.fl) or _safeNum(out.tl)
		out.c = (out.fc == true) or (out.tc == true)
		return out
	end

	-- Backward compatibility: legacy compact format without split affix scores.
	local l, s, c, tLegacy, aLegacy = v:match("^(%-?%d+):(%-?%d+):([01]):(%-?%d+):([^:]*)$")
	if not l then
		-- Older legacy format with encoded name suffix.
		l, s, c, tLegacy, aLegacy = v:match("^(%-?%d+):(%-?%d+):([01]):(%-?%d+):([^:]*):.*$")
	end
	if not l then
		return nil
	end
	return {
		l = _safeNum(l),
		s = _safeNum(s),
		c = tostring(c) == "1",
		fl = _safeNum(l),
		fs = _safeNum(s),
		fc = tostring(c) == "1",
		tl = 0,
		ts = 0,
		tc = false,
		t = _safeNum(tLegacy),
	}
end

local function _readAffixBestForMap(mapId)
	local out = {
		fl = 0, fs = 0, fc = false,
		tl = 0, ts = 0, tc = false,
	}
	if type(C_MythicPlus) ~= "table" or type(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap) ~= "function" then
		return out, false
	end
	local ok, rows = pcall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, mapId)
	if not ok or type(rows) ~= "table" then
		return out, false
	end
	local has = false
	for i = 1, #rows do
		local r = rows[i]
		if type(r) == "table" then
			local affixId = tonumber(r.id or r.affixID or r.affixId) or 0
			local level = _safeNum(r.level or r.bestLevel)
			local score = _safeNum(r.score or r.bestScore)
			local completed = (r.completed == true) or (r.overTime == false)
			if affixId == 10 or (affixId == 0 and i == 1) then
				out.fl, out.fs, out.fc = level, score, completed
				has = has or (level > 0 or score > 0)
			elseif affixId == 9 or (affixId == 0 and i == 2) then
				out.tl, out.ts, out.tc = level, score, completed
				has = has or (level > 0 or score > 0)
			end
		end
	end
	return out, has
end

local function _buildPackedDigest(packedByMap)
	if type(packedByMap) ~= "table" then
		return ""
	end
	local keys = {}
	for k, v in pairs(packedByMap) do
		local mapId = tonumber(k) or 0
		if mapId > 0 and type(v) == "string" and v ~= "" then
			keys[#keys + 1] = mapId
		end
	end
	table.sort(keys, function(a, b) return a < b end)
	local out = {}
	for i = 1, #keys do
		local mid = keys[i]
		out[#out + 1] = tostring(mid) .. "=" .. tostring(packedByMap[mid] or packedByMap[tostring(mid)] or "")
	end
	return table.concat(out, "|")
end

function MYTHIC:_PublishMythicToGuild(payload, reason)
	local comm = GMS and GMS.Comm or nil
	if type(comm) ~= "table" or type(comm.PublishCharacterRecord) ~= "function" then
		return false, "comm-unavailable"
	end
	local wire = {
	}
	for k, v in pairs(payload) do
		wire[k] = v
	end
	return comm:PublishCharacterRecord(MYTHIC_SYNC_DOMAIN, wire)
end

function MYTHIC:InitializeOptions()
	self._options = self._options or {}
	LOCAL_LOG("INFO", "MythicPlus options initialized (MYTHICPLUS_V2 char scope)")
end

local function EnsureMythicV2Store(charStore)
	if type(charStore) ~= "table" then
		return nil, false
	end
	local migrated = false
	local legacyStore = type(charStore.MYTHICPLUS) == "table" and charStore.MYTHICPLUS or nil
	local node = type(charStore.MYTHICPLUS_V2) == "table" and charStore.MYTHICPLUS_V2 or nil
	if type(node) ~= "table" then
		node = { data = {}, meta = {} }
		charStore.MYTHICPLUS_V2 = node
	end
	node.data = type(node.data) == "table" and node.data or {}
	node.meta = type(node.meta) == "table" and node.meta or {}
	local store = node.data

	local function importLegacyDungeons(dungeons)
		if type(dungeons) ~= "table" then return end
		for i = 1, #dungeons do
			local row = dungeons[i]
			local mid = tonumber(type(row) == "table" and (row.m or row.mapId) or nil) or 0
			if mid > 0 and type(row) == "table" then
				store[mid] = _encodeDungeonData(row)
			end
		end
	end

	if type(legacyStore) == "table" then
		importLegacyDungeons(legacyStore.dungeons)
		migrated = true
	end

	if type(store.d) == "table" then
		importLegacyDungeons(store.d)
	end
	if type(store.dungeons) == "table" then
		importLegacyDungeons(store.dungeons)
	end

	local deleteKeys = {
		"s", "score", "d", "dungeons", "a", "affixes",
		"ls", "lastScan", "dg", "lastDigest",
		"module", "version", "reason",
	}
	for i = 1, #deleteKeys do
		store[deleteKeys[i]] = nil
	end

	-- Legacy persistence removed; keep only MYTHICPLUS_V2.
	charStore.MYTHICPLUS = nil

	return store, migrated
end

local function GetDirectMythicStore()
	if not GMS or type(GMS.db) ~= "table" or type(GMS.db.global) ~= "table" then
		return nil
	end
	local guid = _getCharKey()
	if type(guid) ~= "string" or guid == "" then
		return nil
	end
	local global = GMS.db.global
	global.characters = type(global.characters) == "table" and global.characters or {}
	global.characters[guid] = type(global.characters[guid]) == "table" and global.characters[guid] or {}
	local store = EnsureMythicV2Store(global.characters[guid])
	return store
end

local function PurgeLegacyMythicStores()
	if not GMS or type(GMS.db) ~= "table" or type(GMS.db.global) ~= "table" then
		return 0
	end
	local chars = GMS.db.global.characters
	if type(chars) ~= "table" then
		return 0
	end
	local migratedCount = 0
	for _, charStore in pairs(chars) do
		if type(charStore) == "table" and type(charStore.MYTHICPLUS) == "table" then
			local _, migrated = EnsureMythicV2Store(charStore)
			if migrated then
				migratedCount = migratedCount + 1
			end
		elseif type(charStore) == "table" and charStore.MYTHICPLUS ~= nil then
			charStore.MYTHICPLUS = nil
			migratedCount = migratedCount + 1
		end
	end
	return migratedCount
end

-- ###########################################################################
-- #	SCAN LOGIC
-- ###########################################################################

function MYTHIC:ScanMythicPlusData(reason)
	local store = GetDirectMythicStore()
	if type(store) ~= "table" then
		self:InitializeOptions()
		store = GetDirectMythicStore()
		if type(store) ~= "table" then
			LOCAL_LOG("WARN", "ScanMythicPlusData failed: options not initialized")
			return false
		end
	end
	self._options = store

	if type(C_ChallengeMode) ~= "table"
		or type(C_ChallengeMode.GetOverallDungeonScore) ~= "function"
		or type(C_ChallengeMode.GetMapTable) ~= "function" then
		LOCAL_LOG("WARN", "Mythic+ API not available")
		return false
	end

	-- Current Season Score
	local currentScore = _safeNum(C_ChallengeMode.GetOverallDungeonScore())

	-- Scan Maps
	local maps = C_ChallengeMode.GetMapTable()
	local packed = {}
	if type(maps) == "table" then
		for _, mapId in ipairs(maps) do
			local _, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapId)
			local intimeInfo, overtimeInfo = nil, nil
			if type(C_MythicPlus) == "table" and type(C_MythicPlus.GetSeasonBestForMap) == "function" then
				intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapId)
			end

			local dungeonData = {
				m = mapId,
				t = texture,
				l = 0,
				s = 0,
				c = false,
				fl = 0,
				fs = 0,
				fc = false,
				tl = 0,
				ts = 0,
				tc = false,
			}

			-- Prefer intime run, fallback to overtime
			local picked = _normalizeRunInfo(intimeInfo, true) or _normalizeRunInfo(overtimeInfo, false)
			local affixBest, hasAffixBest = _readAffixBestForMap(mapId)
			if hasAffixBest then
				dungeonData.fl = _safeNum(affixBest.fl)
				dungeonData.fs = _safeNum(affixBest.fs)
				dungeonData.fc = affixBest.fc == true
				dungeonData.tl = _safeNum(affixBest.tl)
				dungeonData.ts = _safeNum(affixBest.ts)
				dungeonData.tc = affixBest.tc == true
				dungeonData.l = (dungeonData.fl > dungeonData.tl) and dungeonData.fl or dungeonData.tl
				dungeonData.s = _safeNum(dungeonData.fs) + _safeNum(dungeonData.ts)
				dungeonData.c = (dungeonData.fc == true) or (dungeonData.tc == true)
			end
			if picked then
				if dungeonData.l <= 0 then dungeonData.l = picked.level end
				if dungeonData.s <= 0 then dungeonData.s = picked.score end
				if dungeonData.c ~= true then dungeonData.c = picked.completed end
				if dungeonData.fl <= 0 and dungeonData.tl <= 0 then
					dungeonData.fl = picked.level
					dungeonData.fs = picked.score
					dungeonData.fc = picked.completed == true
				end
			end

			packed[mapId] = _encodeDungeonData(dungeonData)
		end
	end

	local digest = _buildPackedDigest(packed)
	local previousDigest = tostring(self._lastDigest or "")

	-- Update Store
	for k, _ in pairs(store) do
		local mid = tonumber(k)
		if mid and mid > 0 then
			store[k] = nil
		end
	end
	for k, v in pairs(packed) do
		store[k] = v
	end
	self._lastDigest = digest

	if digest ~= "" and digest ~= previousDigest then
		local ok, publishReason = self:_PublishMythicToGuild(store, reason or "scan")
		if ok then
			LOCAL_LOG("COMM", "Mythic+ snapshot published", tostring(reason or "scan"))
		else
			LOCAL_LOG("WARN", "Mythic+ publish failed", tostring(publishReason or "unknown"), tostring(reason or "scan"))
		end
	end

	LOCAL_LOG("INFO", "Mythic+ data scanned and updated", currentScore, (maps and #maps or 0))
	return true
end

-- ###########################################################################
-- #	EVENTS
-- ###########################################################################


function MYTHIC:OnEnable()
	LOCAL_LOG("INFO", "Module enabled")
	local purged = PurgeLegacyMythicStores()
	if purged > 0 then
		LOCAL_LOG("INFO", "Migrated legacy MYTHICPLUS stores to MYTHICPLUS_V2", purged)
	end
	self:InitializeOptions()

	self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
	self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnChallengeModeCompleted")
	self:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", "OnChallengeModeMapsUpdate")

	-- Initial scan if already logged in (reload)
	if IsLoggedIn() then
		self:ScanMythicPlusData("enable")
	end

	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
end

function MYTHIC:OnDisable()
	if type(self.UnregisterAllEvents) == "function" then
		self:UnregisterAllEvents()
	end
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end

function MYTHIC:OnPlayerLogin()
	-- Delayed scan to ensure data availability
	C_Timer.After(4, function() self:ScanMythicPlusData("login") end)
end

function MYTHIC:OnChallengeModeCompleted()
	-- Delayed scan to allow API update
	C_Timer.After(2, function() self:ScanMythicPlusData("challenge_completed") end)
end

function MYTHIC:OnChallengeModeMapsUpdate()
	C_Timer.After(1, function() self:ScanMythicPlusData("maps_update") end)
end
