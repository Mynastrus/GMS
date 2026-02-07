-- ============================================================================
--  GMS/Modules/Raids.lua
--  RAIDS MODULE (Ace)
--  - Kein UI
--  - Persistenz: GMS_DB.global.characters[charKey].RAIDS
--  - Scan: Saved Raid Lockouts + Encounter-Killstatus
--  - Cleanup: Auto-Remove expired lockouts
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- ###########################################################################
-- # METADATA
-- ###########################################################################

local METADATA = {
	TYPE         = "MODULE",
	INTERN_NAME  = "RAIDS",
	SHORT_NAME   = "Raids",
	DISPLAY_NAME = "Raids",
	VERSION      = "1.1.0",
}

-- ###########################################################################
-- # LOG BUFFER + LOCAL LOGGER
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return GetTime and GetTime() or nil
end

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time   = now(),
		level  = tostring(level or "INFO"),
		type   = METADATA.TYPE,
		source = METADATA.SHORT_NAME,
		msg    = tostring(msg or ""),
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
-- # MODULE
-- ###########################################################################

local MODULE_NAME = METADATA.INTERN_NAME

local RAIDS = GMS:GetModule(MODULE_NAME, true)
if not RAIDS then
	RAIDS = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
end

RAIDS.METADATA = METADATA

-- ###########################################################################
-- # INTERNAL HELPERS
-- ###########################################################################

local function hasDB()
	return type(GMS_DB) == "table"
		and type(GMS_DB.global) == "table"
end

local function ensureCharRoot(charKey)
	if not hasDB() then return nil end
	if not charKey or charKey == "" then return nil end

	local g = GMS_DB.global
	g.characters = g.characters or {}

	local c = g.characters[charKey]
	if not c then
		c = {}
		g.characters[charKey] = c
	end

	c.RAIDS = c.RAIDS or {}

	return c
end

local function safeDifficultyName(diffID)
	if GetDifficultyInfo then
		local name = GetDifficultyInfo(diffID)
		if name and name ~= "" then return name end
	end
	return tostring(diffID or "?")
end

local function makeRaidKey(name, diffID, instanceIDMostSig, instanceIDLeastSig)
	-- Prefer stable numeric instance pair if present, fallback to name+diff
	if instanceIDMostSig and instanceIDLeastSig
		and tostring(instanceIDMostSig) ~= "nil"
		and tostring(instanceIDLeastSig) ~= "nil"
	then
		return tostring(instanceIDMostSig) .. ":" .. tostring(instanceIDLeastSig) .. ":" .. tostring(diffID or 0)
	end
	return tostring(name or "UNKNOWN") .. ":" .. tostring(diffID or 0)
end

local function cleanupExpired(raidsTable, tsNow, graceSeconds)
	graceSeconds = graceSeconds or 60
	if type(raidsTable) ~= "table" then return end

	for key, entry in pairs(raidsTable) do
		if type(entry) == "table" then
			local resetAt = entry.resetAt
			-- If we know resetAt and it's clearly in the past -> delete
			if type(resetAt) == "number" and type(tsNow) == "number" then
				if tsNow > (resetAt + graceSeconds) then
					raidsTable[key] = nil
				end
			end
		end
	end
end

-- ###########################################################################
-- # LIFECYCLE
-- ###########################################################################

function RAIDS:OnInitialize()
	LOCAL_LOG("INFO", "Initializing Raids module", METADATA.VERSION)
	self._pendingScan = false
	self._lastScanAt = nil
end

function RAIDS:OnEnable()
	LOCAL_LOG("INFO", "Enabling Raids module")

	-- We only register events if the API exists (safe for classic variants)
	if RequestRaidInfo and GetNumSavedInstances and GetSavedInstanceInfo then
		self:RegisterEvent("PLAYER_LOGIN", "QueueScan")
		self:RegisterEvent("PLAYER_ENTERING_WORLD", "QueueScan")
		self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnUpdateInstanceInfo")
	else
		LOCAL_LOG("WARN", "Saved instances API not available in this client")
	end
end

function RAIDS:OnDisable()
	LOCAL_LOG("INFO", "Disabling Raids module")
end

-- ###########################################################################
-- # SCAN / UPDATE
-- ###########################################################################

-- Triggers a scan (async). You MUST pass charKey (storage partition).
function RAIDS:QueueScan(_, charKey)
	if not charKey or charKey == "" then
		LOCAL_LOG("WARN", "QueueScan called without charKey")
		return false
	end
	if not RequestRaidInfo then return false end

	self._pendingScan = true
	self._pendingCharKey = charKey
	RequestRaidInfo()

	return true
end

-- Processes the results of RequestRaidInfo().
function RAIDS:OnUpdateInstanceInfo()
	if not self._pendingScan then
		return
	end
	self._pendingScan = false

	local charKey = self._pendingCharKey
	self._pendingCharKey = nil

	local c = ensureCharRoot(charKey)
	if not c then
		LOCAL_LOG("WARN", "Database not ready during scan", charKey)
		return
	end

	local tsNow = now()
	c.RAIDS = c.RAIDS or {}
	local store = c.RAIDS

	-- Mark current scan token so we can know what's "seen" this scan
	local scanToken = tostring(tsNow or time() or 0) .. ":" .. tostring(math.random(1000, 9999))

	-- Proactively cleanup old entries
	cleanupExpired(store, tsNow, 60)

	local num = GetNumSavedInstances and GetNumSavedInstances() or 0
	local raidsFound = 0

	for i = 1, num do
		-- GetSavedInstanceInfo return values vary slightly across versions,
		-- we only take what we need and keep it defensive.
		local name,
			_raidID,
			reset,
			diffID,
			locked,
			extended,
			_instanceIDMostSig,
			_instanceIDLeastSig,
			_isRaid,
			_maxPlayers,
			_difficultyName,
			_numEncounters
			= GetSavedInstanceInfo(i)

		local isRaid = _isRaid == true
		local numEncounters = tonumber(_numEncounters) or 0

		if isRaid then
			raidsFound = raidsFound + 1

			local key = makeRaidKey(name, diffID, _instanceIDMostSig, _instanceIDLeastSig)
			local entry = store[key]
			if type(entry) ~= "table" then
				entry = {}
				store[key] = entry
			end

			-- Count killed encounters (if API exists)
			local killed = 0
			if GetSavedInstanceEncounterInfo and numEncounters > 0 then
				for e = 1, numEncounters do
					local _encName, _encID, _isKilled = GetSavedInstanceEncounterInfo(i, e)
					if _isKilled then
						killed = killed + 1
					end
				end
			end

			entry.key = key
			entry.name = tostring(name or "UNKNOWN")
			entry.diffID = tonumber(diffID) or diffID
			entry.diffName = safeDifficultyName(diffID)
			entry.locked = locked == true
			entry.extended = extended == true
			entry.total = numEncounters
			entry.killed = killed

			entry.resetSeconds = tonumber(reset) or reset
			if type(tsNow) == "number" and type(reset) == "number" then
				entry.resetAt = tsNow + reset
			end

			entry.lastSeen = tsNow
			entry._scanToken = scanToken
		end
	end

	-- Remove entries that were not seen this scan AND are already past resetAt (extra safety)
	for key, entry in pairs(store) do
		if type(entry) == "table" then
			if entry._scanToken ~= scanToken then
				local resetAt = entry.resetAt
				if type(tsNow) == "number" and type(resetAt) == "number" and tsNow > resetAt then
					store[key] = nil
				end
			end
		end
	end

	self._lastScanAt = tsNow
	LOCAL_LOG("INFO", "Raid scan completed", charKey, raidsFound)
end

-- ###########################################################################
-- # PUBLIC API (DB-backed)
-- ###########################################################################

function RAIDS:EnsureCharacter(charKey)
	if not charKey or charKey == "" then
		LOCAL_LOG("WARN", "EnsureCharacter called without charKey")
		return nil
	end

	local c = ensureCharRoot(charKey)
	if not c then
		LOCAL_LOG("WARN", "Database not ready, cannot ensure character", charKey)
		return nil
	end

	return c
end

function RAIDS:GetRaids(charKey)
	local c = self:EnsureCharacter(charKey)
	return c and c.RAIDS or nil
end

function RAIDS:ClearRaids(charKey)
	local c = self:EnsureCharacter(charKey)
	if not c then return false end
	c.RAIDS = {}
	LOCAL_LOG("INFO", "RAIDS cleared", charKey)
	return true
end

-- Returns a snapshot grouped by difficulty:
-- result[diffID] = { entries... }  (each entry includes killed/total and resetAt)
function RAIDS:GetSnapshotByDifficulty(charKey)
	local raids = self:GetRaids(charKey)
	if type(raids) ~= "table" then return {} end

	local grouped = {}

	for _, entry in pairs(raids) do
		if type(entry) == "table" then
			local diffID = entry.diffID or 0
			grouped[diffID] = grouped[diffID] or {}
			grouped[diffID][#grouped[diffID] + 1] = entry
		end
	end

	-- Sort each group: name asc, then killed desc
	for _, list in pairs(grouped) do
		table.sort(list, function(a, b)
			local an = tostring(a.name or "")
			local bn = tostring(b.name or "")
			if an ~= bn then return an < bn end
			return (tonumber(a.killed) or 0) > (tonumber(b.killed) or 0)
		end)
	end

	return grouped
end

-- Convenience: returns a flat list sorted by diffID then name
function RAIDS:GetSnapshotFlat(charKey)
	local raids = self:GetRaids(charKey)
	if type(raids) ~= "table" then return {} end

	local list = {}
	for _, entry in pairs(raids) do
		if type(entry) == "table" then
			list[#list + 1] = entry
		end
	end

	table.sort(list, function(a, b)
		local ad = tonumber(a.diffID) or 0
		local bd = tonumber(b.diffID) or 0
		if ad ~= bd then return ad < bd end
		return tostring(a.name or "") < tostring(b.name or "")
	end)

	return list
end
