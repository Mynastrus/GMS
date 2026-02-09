local _, GMS = ...

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

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
		level     = level,
		type      = METADATA.TYPE,
		source    = METADATA.SHORT_NAME,
		message   = string.format(msg, ...),
	}

	-- Add to buffer
	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry

	-- Notify if handler exists
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

-- ###########################################################################
-- #	UTILS
-- ###########################################################################

local function _getCharKey()
	local guid = UnitGUID and UnitGUID("player") or nil
	if guid and guid ~= "" then return guid end
	return nil
end

local function _ensureSvTables()
	if type(GMS_DB) ~= "table" then return nil end

	local key = _getCharKey()
	if not key then return nil end

	GMS_DB.global = GMS_DB.global or {}
	GMS_DB.global.characters = GMS_DB.global.characters or {}

	local c = GMS_DB.global.characters[key]
	if not c then
		c = { __version = 1 }
		GMS_DB.global.characters[key] = c
	end

	c.MYTHIC = c.MYTHIC or {}
	return c.MYTHIC, key
end

-- ###########################################################################
-- #	SCAN LOGIC
-- ###########################################################################

function MYTHIC:ScanMythicPlusData()
	local store, charKey = _ensureSvTables()
	if not store then
		LOCAL_LOG("WARN", "Could not access SV store for Mythic+ scan")
		return
	end

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
	store.lastScan = time()

	LOCAL_LOG("INFO", "Mythic+ data scanned and updated", currentScore, #dungeons)
end

-- ###########################################################################
-- #	EVENTS
-- ###########################################################################

function MYTHIC:OnInitialize()
	LOCAL_LOG("INFO", "Module initialized")
end

function MYTHIC:OnEnable()
	LOCAL_LOG("INFO", "Module enabled")

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
