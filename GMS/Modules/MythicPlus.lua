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
---@diagnostic enable: undefined-global

local METADATA = {
	TYPE         = "MOD",
	INTERN_NAME  = "MythicPlus",
	SHORT_NAME   = "MYTHIC",
	DISPLAY_NAME = "Mythic Plus",
	VERSION      = "1.1.2",
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

function MYTHIC:ScanMythicPlusData()
	if not self._options then
		self:InitializeOptions()
		if not self._options then
			LOCAL_LOG("WARN", "ScanMythicPlusData failed: options not initialized")
			return
		end
	end

	local store = self._options

	-- Current Season Score
	local currentScore = C_ChallengeMode.GetOverallDungeonScore()

	-- Scan Maps
	local maps = C_ChallengeMode.GetMapTable()
	local dungeons = {}

	if maps then
		for _, mapId in ipairs(maps) do
			local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapId)
			local intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapId)

			local dungeonData = {
				mapId = mapId,
				name = name,
				texture = texture,
				level = 0,
				score = 0,
			}

			-- Prefer intime run, fallback to overtime
			if intimeInfo then
				dungeonData.level = intimeInfo.level
				dungeonData.score = intimeInfo.dungeonScore
				dungeonData.completed = true
			elseif overtimeInfo then
				dungeonData.level = overtimeInfo.level
				dungeonData.score = overtimeInfo.dungeonScore
				dungeonData.completed = false
			end

			table.insert(dungeons, dungeonData)
		end
	end

	-- Update Store
	store.score = currentScore
	store.dungeons = dungeons
	store.lastScan = time and time() or 0

	LOCAL_LOG("INFO", "Mythic+ data scanned and updated", currentScore, #dungeons)
end

-- ###########################################################################
-- #	EVENTS
-- ###########################################################################


function MYTHIC:OnEnable()
	LOCAL_LOG("INFO", "Module enabled")
	self:InitializeOptions()

	self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
	self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnChallengeModeCompleted")

	-- Initial scan if already logged in (reload)
	if IsLoggedIn() then
		self:ScanMythicPlusData()
	end

	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
end

function MYTHIC:OnDisable()
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end

function MYTHIC:OnPlayerLogin()
	-- Delayed scan to ensure data availability
	C_Timer.After(4, function() self:ScanMythicPlusData() end)
end

function MYTHIC:OnChallengeModeCompleted()
	-- Delayed scan to allow API update
	C_Timer.After(2, function() self:ScanMythicPlusData() end)
end
