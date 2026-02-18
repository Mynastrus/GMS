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
	VERSION      = "1.1.5",
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
local MYTHIC_SYNC_DOMAIN = "MYTHICPLUS_V1"

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

local function _buildMythicDigest(score, dungeons)
	local sorted = {}
	if type(dungeons) == "table" then
		for i = 1, #dungeons do
			sorted[#sorted + 1] = dungeons[i]
		end
	end
	table.sort(sorted, function(a, b)
		return _safeNum(a and a.mapId) < _safeNum(b and b.mapId)
	end)

	local parts = { "S:" .. tostring(_safeNum(score)) }
	for i = 1, #sorted do
		local d = sorted[i]
		parts[#parts + 1] = table.concat({
			tostring(_safeNum(d and d.mapId)),
			tostring(_safeNum(d and d.level)),
			tostring(_safeNum(d and d.score)),
			tostring((type(d) == "table" and d.completed == true) or false),
		}, ":")
	end
	return table.concat(parts, "|")
end

function MYTHIC:_PublishMythicToGuild(payload, reason)
	local comm = GMS and GMS.Comm or nil
	if type(comm) ~= "table" or type(comm.PublishCharacterRecord) ~= "function" then
		return false, "comm-unavailable"
	end
	local wire = {
		module = METADATA.SHORT_NAME,
		version = METADATA.VERSION,
		reason = tostring(reason or "unknown"),
		score = payload.score,
		dungeons = payload.dungeons,
		lastScan = payload.lastScan,
	}
	return comm:PublishCharacterRecord(MYTHIC_SYNC_DOMAIN, wire)
end

function MYTHIC:InitializeOptions()
	-- Register character-scoped options
	if GMS and type(GMS.RegisterModuleOptions) == "function" then
		pcall(function()
			GMS:RegisterModuleOptions(MODULE_NAME, {
				score = 0,
				dungeons = {},
				lastScan = 0,
			}, "CHAR")
		end)
	end

	-- Retrieve options table
	if GMS and type(GMS.GetModuleOptions) == "function" then
		local ok, opts = pcall(GMS.GetModuleOptions, GMS, MODULE_NAME)
		if ok and opts then
			self._options = opts
			LOCAL_LOG("INFO", "MythicPlus options initialized")
		else
			LOCAL_LOG("WARN", "Failed to retrieve MythicPlus options")
		end
	end
end

-- ###########################################################################
-- #	SCAN LOGIC
-- ###########################################################################

function MYTHIC:ScanMythicPlusData(reason)
	if not self._options then
		self:InitializeOptions()
		if not self._options then
			LOCAL_LOG("WARN", "ScanMythicPlusData failed: options not initialized")
			return false
		end
	end

	local store = self._options

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
	local dungeons = {}

	if type(maps) == "table" then
		for _, mapId in ipairs(maps) do
			local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapId)
			local intimeInfo, overtimeInfo = nil, nil
			if type(C_MythicPlus) == "table" and type(C_MythicPlus.GetSeasonBestForMap) == "function" then
				intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapId)
			end

			local dungeonData = {
				mapId = mapId,
				name = name,
				texture = texture,
				level = 0,
				score = 0,
			}

			-- Prefer intime run, fallback to overtime
			local picked = _normalizeRunInfo(intimeInfo, true) or _normalizeRunInfo(overtimeInfo, false)
			if picked then
				dungeonData.level = picked.level
				dungeonData.score = picked.score
				dungeonData.completed = picked.completed
			end

			table.insert(dungeons, dungeonData)
		end
	end

	table.sort(dungeons, function(a, b)
		return _safeNum(a and a.mapId) < _safeNum(b and b.mapId)
	end)

	local digest = _buildMythicDigest(currentScore, dungeons)
	local previousDigest = tostring(store.lastDigest or "")

	-- Update Store
	store.score = currentScore
	store.dungeons = dungeons
	store.lastScan = time and time() or 0
	store.lastDigest = digest

	if digest ~= "" and digest ~= previousDigest then
		local ok, publishReason = self:_PublishMythicToGuild(store, reason or "scan")
		if ok then
			LOCAL_LOG("COMM", "Mythic+ snapshot published", tostring(reason or "scan"))
		else
			LOCAL_LOG("WARN", "Mythic+ publish failed", tostring(publishReason or "unknown"), tostring(reason or "scan"))
		end
	end

	LOCAL_LOG("INFO", "Mythic+ data scanned and updated", currentScore, #dungeons)
	return true
end

-- ###########################################################################
-- #	EVENTS
-- ###########################################################################


function MYTHIC:OnEnable()
	LOCAL_LOG("INFO", "Module enabled")
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
