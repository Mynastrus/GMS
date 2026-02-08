-- ============================================================================
--  GMS/Modules/Raids.lua
--  RAIDS MODULE (Ace)
--  - Kein UI
--  - Nur aktueller Spieler (charKey = UnitGUID("player"))
--  - Persistenz: GMS_DB.global.characters[charKey].RAIDS
--  - Key pro Raid: Encounter Journal instanceID (EJ)
--  - Current (lockout-spezifisch) pro Difficulty: "H 3/8", Boss-Kills, resetAt
--  - Best (persistiert) pro Raid: höchste Difficulty + Progress (zuerst diff, dann killed)
--  - Auto-Update:
--      * Login -> delayed scan
--      * Boss kill -> delayed scan
--  - EJ ist tricky: Catalog wird mit Retries aufgebaut
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
-- # INTERNAL HELPERS (DB + PlayerKey)
-- ###########################################################################

local function getPlayerKey()
	return UnitGUID and UnitGUID("player") or nil
end

local function hasDB()
	return type(GMS_DB) == "table"
		and type(GMS_DB.global) == "table"
end

local function ensureStore()
	if not hasDB() then return nil, nil end

	local charKey = getPlayerKey()
	if not charKey then return nil, nil end

	local g = GMS_DB.global
	g.characters = g.characters or {}

	local c = g.characters[charKey]
	if not c then
		c = {}
		g.characters[charKey] = c
	end

	c.RAIDS = c.RAIDS or {}
	local s = c.RAIDS

	s.catalog = s.catalog or {}
	s.raids = s.raids or {}

	return s, charKey
end

-- ###########################################################################
-- # DIFFICULTY TAGS / RANKING (best: diffRank first, then killed)
-- ###########################################################################

local DIFF_TAG = {
	[17] = "LFR",
	[14] = "N",
	[15] = "H",
	[16] = "M",
}

local DIFF_RANK = {
	[17] = 1,
	[14] = 2,
	[15] = 3,
	[16] = 4,
}

local function diffTag(diffID)
	return DIFF_TAG[diffID] or tostring(diffID or "?")
end

local function diffRank(diffID)
	return DIFF_RANK[diffID] or 0
end

local function buildShort(diffID, killed, total)
	return diffTag(diffID) .. " " .. tostring(killed or 0) .. "/" .. tostring(total or 0)
end

local function betterThan(a, b)
	if not a then return true end
	if not b then return true end

	local ar = diffRank(a.diffID)
	local br = diffRank(b.diffID)
	if ar ~= br then
		return ar > br
	end

	local ak = tonumber(a.killed) or 0
	local bk = tonumber(b.killed) or 0
	if ak ~= bk then
		return ak > bk
	end

	return false
end

-- ###########################################################################
-- # BEST UPDATE
-- ###########################################################################

local function updateBest(raidEntry, diffID, killed, total)
	if type(raidEntry) ~= "table" then return end
	if type(diffID) ~= "number" then return end

	killed = tonumber(killed) or 0
	total  = tonumber(total) or 0

	raidEntry.bestByDiff = raidEntry.bestByDiff or {}

	local prev = raidEntry.bestByDiff[diffID]
	if type(prev) ~= "table" or (tonumber(prev.killed) or 0) < killed then
		raidEntry.bestByDiff[diffID] = {
			diffID  = diffID,
			diffTag = diffTag(diffID),
			killed  = killed,
			total   = total,
			short   = buildShort(diffID, killed, total),
		}
	end

	local candidate = raidEntry.bestByDiff[diffID]
	if candidate then
		if type(raidEntry.best) ~= "table" or betterThan(candidate, raidEntry.best) then
			raidEntry.best = {
				diffID  = candidate.diffID,
				diffTag = candidate.diffTag,
				killed  = candidate.killed,
				total   = candidate.total,
				short   = candidate.short,
			}
		end
	end
end

-- ###########################################################################
-- # CLEANUP: remove expired CURRENT lockouts (best persists)
-- ###########################################################################

local function cleanupExpiredCurrent(raidEntry, tsNow, graceSeconds)
	graceSeconds = graceSeconds or 60
	if type(raidEntry) ~= "table" then return end
	if type(raidEntry.current) ~= "table" then return end
	if type(tsNow) ~= "number" then return end

	for diffID, cur in pairs(raidEntry.current) do
		if type(cur) == "table" then
			local resetAt = cur.resetAt
			if type(resetAt) == "number" and tsNow > (resetAt + graceSeconds) then
				raidEntry.current[diffID] = nil
			end
		end
	end
end

-- ###########################################################################
-- # ENCOUNTER JOURNAL CATALOG (all raids of the current expansion) - RETRY SAFE
-- ###########################################################################

local function ejAvailable()
	return EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex
		and EJ_SelectInstance and EJ_GetInstanceInfo
		and EJ_GetNumEncounters and EJ_GetEncounterInfoByIndex
		and EJ_GetTierInfo and EJ_GetCurrentTier
end

local function getExpansionName()
	-- Best-effort: Retail typically has GetExpansionLevel + GetExpansionDisplayInfo
	if GetExpansionLevel and GetExpansionDisplayInfo then
		local expID = GetExpansionLevel()
		if expID then
			local name = GetExpansionDisplayInfo(expID)
			if type(name) == "string" and name ~= "" then
				return name
			end
		end
	end
	return nil
end

local function buildExpansionRaidCatalog()
	local catalog = {
		byInstanceID = {},
		nameToInstanceID = {},
		builtAt = now(),
		source = "EJ",
	}

	if not ejAvailable() then
		catalog.source = "EJ_MISSING"
		return catalog
	end

	local expansionName = getExpansionName()
	local numTiers = EJ_GetNumTiers() or 0

	local tiersToScan = {}

	-- Primary: all tiers containing expansionName
	if expansionName and expansionName ~= "" then
		for t = 1, numTiers do
			local tierName = EJ_GetTierInfo(t)
			if type(tierName) == "string" and tierName:find(expansionName, 1, true) then
				tiersToScan[#tiersToScan + 1] = t
			end
		end
	end

	-- Fallback: at least current tier (prevents "empty catalog" on weird clients)
	if #tiersToScan == 0 then
		local cur = EJ_GetCurrentTier and EJ_GetCurrentTier() or nil
		if cur then
			tiersToScan[1] = cur
			catalog.source = "EJ_CURRENT_TIER_ONLY"
		else
			catalog.source = "EJ_NO_TIER"
			return catalog
		end
	end

	for _, tierID in ipairs(tiersToScan) do
		EJ_SelectTier(tierID)

		local idx = 1
		while true do
			local instanceID = EJ_GetInstanceByIndex(idx, true) -- isRaid = true
			if not instanceID then break end

			EJ_SelectInstance(instanceID)

			local raidName = EJ_GetInstanceInfo()
			local total = tonumber(EJ_GetNumEncounters()) or 0

			if type(raidName) == "string" and raidName ~= "" and total > 0 then
				local encounters = {}

				for e = 1, total do
					local ename, _, encounterID = EJ_GetEncounterInfoByIndex(e, instanceID)
					encounters[#encounters + 1] = {
						order = e,
						id    = encounterID,
						name  = ename,
					}
				end

				catalog.byInstanceID[instanceID] = {
					instanceID = instanceID,
					name       = raidName,
					total      = total,
					encounters = encounters,
				}
				catalog.nameToInstanceID[raidName] = instanceID
			end

			idx = idx + 1
		end
	end

	return catalog
end

local function catalogIsUsable(catalog)
	return type(catalog) == "table"
		and type(catalog.byInstanceID) == "table"
		and next(catalog.byInstanceID) ~= nil
		and type(catalog.nameToInstanceID) == "table"
end

function RAIDS:_EnsureCatalogReady()
	local store = ensureStore()
	if not store then return false end

	store.catalog = store.catalog or {}
	if catalogIsUsable(store.catalog) then
		return true
	end

	-- Build once
	store.catalog = buildExpansionRaidCatalog()
	if catalogIsUsable(store.catalog) then
		LOCAL_LOG("INFO", "EJ catalog built", store.catalog.source)
		return true
	end

	-- Not ready yet -> schedule retries
	self:_ScheduleCatalogRetry("catalog_not_ready")
	return false
end

function RAIDS:_ScheduleCatalogRetry(reason)
	if self._catalogRetryTimer then
		-- already scheduled
		return
	end

	self._catalogRetries = (self._catalogRetries or 0) + 1
	local attempt = self._catalogRetries

	-- Backoff: 0.5s, 1s, 2s, 4s, then stop
	local delay = 0.5
	if attempt == 2 then delay = 1 end
	if attempt == 3 then delay = 2 end
	if attempt == 4 then delay = 4 end
	if attempt >= 5 then
		self._catalogRetryTimer = nil
		LOCAL_LOG("WARN", "EJ catalog retry limit reached", reason)
		return
	end

	if not C_Timer or not C_Timer.After then
		LOCAL_LOG("WARN", "C_Timer missing, cannot retry EJ catalog")
		return
	end

	self._catalogRetryTimer = true
	C_Timer.After(delay, function()
		self._catalogRetryTimer = nil
		local ok = self:_EnsureCatalogReady()
		LOCAL_LOG(ok and "INFO" or "WARN", "EJ catalog retry", attempt, ok, reason)

		-- If we were waiting to scan but catalog wasn't ready, try scanning again
		if ok and self._scanWantedAfterCatalog then
			self._scanWantedAfterCatalog = nil
			self:ScanNow("catalog_ready")
		end
	end)
end

-- ###########################################################################
-- # AUTO SCAN SCHEDULER
-- ###########################################################################

function RAIDS:_ScheduleScan(reason, delay)
	if not C_Timer or not C_Timer.After then
		return self:ScanNow(reason)
	end

	delay = tonumber(delay) or 0

	-- Debounce: one pending timer at a time
	self._scanToken = (self._scanToken or 0) + 1
	local token = self._scanToken

	C_Timer.After(delay, function()
		if token ~= self._scanToken then
			return
		end
		self:ScanNow(reason)
	end)

	return true
end

-- ###########################################################################
-- # EJ BOOTSTRAP (Blizzard_EncounterJournal can be lazy-loaded)
-- ###########################################################################

function RAIDS:_TryLoadEncounterJournal()
	-- If EJ functions already exist, we're good
	if EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex then
		return true
	end

	-- Try to load Blizzard Encounter Journal UI addon
	if LoadAddOn then
		local loaded, reason = LoadAddOn("Blizzard_EncounterJournal")
		if loaded then
			return true
		else
			-- reason can be: "DISABLED", "MISSING", "CORRUPT", "INCOMPATIBLE", etc.
			LOCAL_LOG("WARN", "LoadAddOn(Blizzard_EncounterJournal) failed", reason)
		end
	else
		LOCAL_LOG("WARN", "LoadAddOn not available")
	end

	return false
end

function RAIDS:ADDON_LOADED(_, addonName)
	if addonName ~= "Blizzard_EncounterJournal" then return end

	-- Now EJ APIs should exist
	self:UnregisterEvent("ADDON_LOADED")

	LOCAL_LOG("INFO", "Blizzard_EncounterJournal loaded, rebuilding catalog")
	self:RebuildCatalog()

	-- If we deferred scans while EJ wasn't ready, do one now
	self:_ScheduleScan("ej_loaded", 1.0)
end

-- ###########################################################################
-- # LIFECYCLE
-- ###########################################################################

function RAIDS:OnInitialize()
	LOCAL_LOG("INFO", "Initializing Raids module", METADATA.VERSION)
	self._pendingScan = false
	self._catalogRetries = 0
	self._scanToken = 0
end

function RAIDS:OnEnable()
	LOCAL_LOG("INFO", "Enabling Raids module")

	-- Ensure Encounter Journal API is available (can be lazy-loaded)
	if not self:_TryLoadEncounterJournal() then
		self:RegisterEvent("ADDON_LOADED")
	end

	-- Register events
	self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")

	-- Boss kill / encounter end -> schedule a scan
	-- (ENCOUNTER_END is reliable for raid bosses; BOSS_KILL is also useful)
	self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
	self:RegisterEvent("BOSS_KILL", "OnBossKill")

	-- SavedInstances update
	if RequestRaidInfo and GetNumSavedInstances and GetSavedInstanceInfo then
		self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnUpdateInstanceInfo")
	else
		LOCAL_LOG("WARN", "Saved instances API not available")
	end

	-- Try to build EJ catalog early (best-effort, with retries)
	self:_EnsureCatalogReady()
end


function RAIDS:OnDisable()
	LOCAL_LOG("INFO", "Disabling Raids module")
end

-- ###########################################################################
-- # EVENTS -> AUTO UPDATE
-- ###########################################################################

function RAIDS:OnPlayerLogin()
	-- Login: wait a short moment so SavedInstances/EJ are ready
	self:_ScheduleScan("login", 2.0)
end

function RAIDS:OnEnteringWorld()
	-- Entering world: light debounce
	self:_ScheduleScan("entering_world", 1.0)
end

function RAIDS:OnEncounterEnd(_, encounterID, encounterName, difficultyID, groupSize, success)
	-- success == 1 => boss killed
	if success == 1 then
		-- Wait a bit so instance info updates are available
		self:_ScheduleScan("encounter_end", 1.0)
	end
end

function RAIDS:OnBossKill()
	-- Some kills fire this; also schedule
	self:_ScheduleScan("boss_kill", 1.0)
end

-- ###########################################################################
-- # PUBLIC API
-- ###########################################################################

function RAIDS:RebuildCatalog()
	local store = ensureStore()
	if not store then return false end

	store.catalog = buildExpansionRaidCatalog()
	self._catalogRetries = 0

	local ok = catalogIsUsable(store.catalog)
	LOCAL_LOG(ok and "INFO" or "WARN", "Catalog rebuilt", store.catalog.source)
	return ok
end

function RAIDS:ScanNow(reason)
	if not RequestRaidInfo then
		return false
	end

	local store, charKey = ensureStore()
	if not store or not charKey then
		LOCAL_LOG("WARN", "ScanNow failed: DB or player key missing", reason)
		return false
	end

	-- Ensure EJ catalog; if not ready, defer scan until catalog is ready
	if not self:_EnsureCatalogReady() then
		self._scanWantedAfterCatalog = true
		LOCAL_LOG("WARN", "Scan deferred until EJ catalog ready", reason)
		return false
	end

	self._pendingScan = true
	self._pendingReason = tostring(reason or "manual")
	RequestRaidInfo()
	return true
end

function RAIDS:GetAllRaids()
	local store = ensureStore()
	if not store then return {} end
	return store.raids or {}
end

function RAIDS:GetCatalog()
	local store = ensureStore()
	if not store then return {} end
	self:_EnsureCatalogReady()
	return store.catalog or {}
end

-- ###########################################################################
-- # SCAN RESULT INGEST (SavedInstances -> per instanceID current state)
-- ###########################################################################

function RAIDS:OnUpdateInstanceInfo()
	if not self._pendingScan then return end
	self._pendingScan = false

	local store, charKey = ensureStore()
	if not store or not charKey then
		LOCAL_LOG("WARN", "OnUpdateInstanceInfo: DB or player key missing")
		return
	end

	-- Catalog must be usable here
	if not self:_EnsureCatalogReady() then
		self._scanWantedAfterCatalog = true
		LOCAL_LOG("WARN", "Ingest skipped: EJ catalog not ready")
		return
	end

	local catalog = store.catalog
	local raidsStore = store.raids
	local tsNow = now()

	-- Cleanup expired current lockouts (do not touch best)
	for _, raidEntry in pairs(raidsStore) do
		if type(raidEntry) == "table" then
			cleanupExpiredCurrent(raidEntry, tsNow, 60)
		end
	end

	local num = GetNumSavedInstances and GetNumSavedInstances() or 0
	local ingested = 0
	local unresolved = 0

	for i = 1, num do
		local name,
			_,
			reset,
			diffID,
			locked,
			extended,
			_,
			_,
			isRaid,
			_,
			_,
			numEncounters
			= GetSavedInstanceInfo(i)

		if isRaid == true and type(name) == "string" and name ~= "" then
			-- Map SavedInstance raid name -> EJ instanceID
			local instanceID = catalog.nameToInstanceID and catalog.nameToInstanceID[name] or nil
			if not instanceID then
				unresolved = unresolved + 1
			else
				local catRaid = catalog.byInstanceID and catalog.byInstanceID[instanceID] or nil
				local total = (catRaid and catRaid.total) or (tonumber(numEncounters) or 0)
				local encCount = tonumber(numEncounters) or total or 0

				local killed = 0
				local bosses = {}

				if GetSavedInstanceEncounterInfo and encCount > 0 then
					for e = 1, encCount do
						local _, encID, isKilled = GetSavedInstanceEncounterInfo(i, e)
						if isKilled then
							killed = killed + 1
							if encID then
								bosses[encID] = true
							end
						end
					end
				end

				-- Only keep CURRENT if it is lockout-relevant
				if locked == true or extended == true or killed > 0 then
					local raidEntry = raidsStore[instanceID]
					if type(raidEntry) ~= "table" then
						raidEntry = {}
						raidsStore[instanceID] = raidEntry
					end

					raidEntry.instanceID = instanceID
					raidEntry.name = (catRaid and catRaid.name) or name
					raidEntry.total = total
					raidEntry.current = raidEntry.current or {}
					raidEntry.bestByDiff = raidEntry.bestByDiff or {}

					local dID = tonumber(diffID) or diffID
					if type(dID) == "number" then
						local cur = raidEntry.current[dID]
						if type(cur) ~= "table" then
							cur = {}
							raidEntry.current[dID] = cur
						end

						cur.diffID = dID
						cur.diffTag = diffTag(dID)
						cur.killed = killed
						cur.total  = total
						cur.short  = buildShort(dID, killed, total)
						cur.locked = locked == true
						cur.extended = extended == true
						cur.bosses = bosses
						cur.resetSeconds = tonumber(reset) or reset

						if type(tsNow) == "number" and type(reset) == "number" then
							cur.resetAt = tsNow + reset
						end

						-- Persist BEST from current progress
						updateBest(raidEntry, dID, killed, total)

						raidEntry.lastScan = tsNow
						raidEntry.lastReason = self._pendingReason
						ingested = ingested + 1
					end
				end
			end
		end
	end

	-- If some raids couldn't be mapped (EJ tricky), attempt a catalog rebuild and rescan
	if unresolved > 0 then
		LOCAL_LOG("WARN", "Some raids unresolved (name->instanceID). Scheduling catalog rebuild+rescan", unresolved)
		self:_ScheduleCatalogRetry("unresolved_mapping")
		self:_ScheduleScan("rescan_after_unresolved", 2.0)
	end

	LOCAL_LOG("INFO", "Raid scan ingested", ingested, "reason", self._pendingReason or "?", "unresolved", unresolved)
	self._pendingReason = nil
end
