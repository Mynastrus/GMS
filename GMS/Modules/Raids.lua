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
--  - EJ ist tricky:
--      * Blizzard_EncounterJournal wird bei Bedarf geladen
--      * Catalog-Build erst nach bestätigter EJ-Bereitschaft
--      * _ejReady darf NUR true sein, wenn alle EJ APIs vorhanden sind
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G                            = _G
local GetTime                       = GetTime
local type                          = type
local tostring                      = tostring
local select                        = select
local pairs                         = pairs
local ipairs                        = ipairs
local pcall                         = pcall
local tonumber                      = tonumber
local next                          = next
local C_Timer                       = C_Timer
local UnitGUID                      = UnitGUID
local RequestRaidInfo               = RequestRaidInfo
local GetNumSavedInstances          = GetNumSavedInstances
local GetSavedInstanceInfo          = GetSavedInstanceInfo
local GetSavedInstanceEncounterInfo = GetSavedInstanceEncounterInfo
local LoadAddOn                     = LoadAddOn
local GetExpansionLevel             = GetExpansionLevel
local GetExpansionDisplayInfo       = GetExpansionDisplayInfo
local C_EncounterJournal            = C_EncounterJournal
local EJ_GetNumTiers                = EJ_GetNumTiers
local EJ_SelectTier                 = EJ_SelectTier
local EJ_GetInstanceByIndex         = EJ_GetInstanceByIndex
local EJ_SelectInstance             = EJ_SelectInstance
local EJ_GetInstanceInfo            = EJ_GetInstanceInfo
local EJ_GetNumEncounters           = EJ_GetNumEncounters
local EJ_GetEncounterInfoByIndex    = EJ_GetEncounterInfoByIndex
local EJ_GetTierInfo                = EJ_GetTierInfo
local EJ_GetCurrentTier             = EJ_GetCurrentTier
local ReloadUI                      = ReloadUI
---@diagnostic enable: undefined-global

-- ###########################################################################
-- # METADATA
-- ###########################################################################

local METADATA = {
	TYPE         = "MODULE",
	INTERN_NAME  = "RAIDS",
	SHORT_NAME   = "Raids",
	DISPLAY_NAME = "Raids",
	VERSION      = "1.2.5",
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

-- Registration
if GMS and type(GMS.RegisterModule) == "function" then
	GMS:RegisterModule(RAIDS, METADATA)
end

local OPTIONS_DEFAULTS = {
	scanLegacy = { type = "toggle", name = "Legacy Raids scannen", default = false },
	rebuild = { type = "execute", name = "Katalog neu aufbauen", func = function()
		local R = GMS:GetModule("RAIDS", true)
		if R then R:RebuildCatalog() end
	end },
	raids = {}, -- { [instanceID] = { current = {...}, best = {...} } }
	lastScan = 0,
}

RAIDS._catalog = nil

function RAIDS:InitializeOptions()
	-- Register character-scoped raid options
	if GMS and type(GMS.RegisterModuleOptions) == "function" then
		pcall(function()
			GMS:RegisterModuleOptions("RAIDS", OPTIONS_DEFAULTS, "CHAR")
		end)
	end

	-- Retrieve options table
	if GMS and type(GMS.GetModuleOptions) == "function" then
		local ok, opts = pcall(GMS.GetModuleOptions, GMS, "RAIDS")
		if ok and opts then
			self._options = opts
			LOCAL_LOG("INFO", "Raids options initialized (CHAR scope)")
		else
			LOCAL_LOG("WARN", "Failed to retrieve Raids options")
		end
	end
end

local function getRaidsStore()
	if not RAIDS._options then return nil end
	RAIDS._options.raids = RAIDS._options.raids or {}
	return RAIDS._options.raids
end

RAIDS.METADATA = METADATA

-- ###########################################################################
-- # INTERNAL HELPERS (DB + PlayerKey)
-- ###########################################################################

local function getPlayerKey()
	return UnitGUID and UnitGUID("player") or nil
end

local function hasDB()
	-- This function is largely obsolete with the new options system,
	-- but kept for potential future checks if GMS_DB is still used elsewhere.
	return type(GMS_DB) == "table"
		and type(GMS_DB.global) == "table"
end

local function ensureStore()
	-- The new options system handles the persistence and default values.
	-- We just need to ensure RAIDS._options is set and return it.
	if not RAIDS._options then
		RAIDS:InitializeOptions() -- Attempt to initialize if not already
		if not RAIDS._options then
			LOCAL_LOG("ERROR", "RAIDS._options could not be initialized.")
			return nil, nil
		end
	end

	local charKey = getPlayerKey()
	if not charKey then return nil, nil end

	-- Catalog is now local to the module session, not persisted in the options
	if not RAIDS._catalog then
		RAIDS:_EnsureCatalogReady()
	end

	return RAIDS._options, charKey
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
-- # EJ BOOTSTRAP + CATALOG (all raids of the current expansion) - READY SAFE
-- ###########################################################################

local function ejApiPresent()
	-- Retail: C_EncounterJournal is standard now, but some functions might still be global or mixed
	if C_EncounterJournal then return true end
	return EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex
		and EJ_SelectInstance and EJ_GetInstanceInfo
		and EJ_GetNumEncounters and EJ_GetEncounterInfoByIndex
		and EJ_GetTierInfo and EJ_GetCurrentTier
end

local function getExpansionName()
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

	if not ejApiPresent() then
		catalog.source = "EJ_MISSING"
		return catalog
	end

	local numTiers = EJ_GetNumTiers and (EJ_GetNumTiers() or 0) or 0
	if numTiers <= 0 then
		catalog.source = "EJ_NOT_READY"
		return catalog
	end

	local expansionName = getExpansionName()
	local scanLegacy = false
	local options = GMS:GetModuleOptions(MODULE_NAME)
	if options then
		scanLegacy = (options.scanLegacy == true)
	end

	local tiersToScan = {}

	if not scanLegacy and expansionName and expansionName ~= "" then
		for t = 1, numTiers do
			local tierName = EJ_GetTierInfo(t)
			if type(tierName) == "string" and tierName:find(expansionName, 1, true) then
				tiersToScan[#tiersToScan + 1] = t
			end
		end
	end

	if #tiersToScan == 0 then
		if scanLegacy then
			for t = 1, numTiers do tiersToScan[#tiersToScan + 1] = t end
			catalog.source = "EJ_ALL_TIERS"
		else
			local cur = EJ_GetCurrentTier and EJ_GetCurrentTier() or nil
			if cur then
				tiersToScan[1] = cur
				catalog.source = "EJ_CURRENT_TIER_ONLY"
			else
				catalog.source = "EJ_NO_TIER"
				return catalog
			end
		end
	end

	for _, tierID in ipairs(tiersToScan) do
		EJ_SelectTier(tierID)

		local idx = 1
		while true do
			local instanceID = EJ_GetInstanceByIndex(idx, true)
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

function RAIDS:_TryLoadEncounterJournal()
	if ejApiPresent() then
		return true
	end

	if LoadAddOn then
		local loaded, reason = LoadAddOn("Blizzard_EncounterJournal")
		if loaded then
			return true
		end
		LOCAL_LOG("WARN", "LoadAddOn(Blizzard_EncounterJournal) failed", reason)
	else
		LOCAL_LOG("WARN", "LoadAddOn not available")
	end

	return false
end

function RAIDS:_ProbeEJReady()
	-- Strict: only ready if EJ APIs are present AND tiers are initialized
	if not ejApiPresent() then
		return false
	end

	local n = EJ_GetNumTiers and EJ_GetNumTiers() or 0
	if n and n > 0 then
		self._ejReady = true
		return true
	end

	return false
end

function RAIDS:ADDON_LOADED(_, addonName)
	if addonName ~= "Blizzard_EncounterJournal" then return end

	self:UnregisterEvent("ADDON_LOADED")

	self:RegisterEvent("EJ_DIFFICULTY_UPDATE", "OnEJReady")

	if C_Timer and C_Timer.After then
		C_Timer.After(0.2, function()
			if self:_ProbeEJReady() then
				self:OnEJReady()
			end
		end)
	end
end

function RAIDS:OnEJReady()
	-- STRICT: do not accept readiness if APIs are still missing
	if not ejApiPresent() then
		self._ejReady = false
		LOCAL_LOG("WARN", "EJ ready event received but EJ API still missing")
		self:_TryLoadEncounterJournal()
		return
	end

	-- Also ensure tiers are initialized
	local n = EJ_GetNumTiers and (EJ_GetNumTiers() or 0) or 0
	if n <= 0 then
		self._ejReady = false
		LOCAL_LOG("WARN", "EJ ready event received but tiers not initialized yet")
		return
	end

	self._ejReady = true

	if self.UnregisterEvent then
		self:UnregisterEvent("EJ_DIFFICULTY_UPDATE")
	end

	LOCAL_LOG("INFO", "Encounter Journal fully initialized (EJ_DIFFICULTY_UPDATE)")

	-- Force rebuild (now safe)
	self:RebuildCatalog()

	-- Resume deferred scan
	if self._scanWantedAfterCatalog then
		self._scanWantedAfterCatalog = nil
		self:_ScheduleScan("ej_ready_final", 0.5)
	end
end

function RAIDS:_EnsureCatalogReady()
	if RAIDS._catalog and catalogIsUsable(RAIDS._catalog) then
		return true
	end

	-- Hard gate
	if not self._ejReady then
		return false
	end

	-- Safety: ejReady but API missing -> revert
	if not ejApiPresent() then
		self._ejReady = false
		LOCAL_LOG("WARN", "EJ ready flag set but EJ API missing; reverting to not-ready")
		self:_TryLoadEncounterJournal()
		return false
	end

	RAIDS._catalog = buildExpansionRaidCatalog()
	if catalogIsUsable(RAIDS._catalog) then
		LOCAL_LOG("INFO", "EJ catalog built", RAIDS._catalog.source)
		return true
	end

	LOCAL_LOG("WARN", "EJ catalog build failed", RAIDS._catalog.source or "unknown")
	return false
end

-- ###########################################################################
-- # AUTO SCAN SCHEDULER
-- ###########################################################################

function RAIDS:_ScheduleScan(reason, delay)
	if not C_Timer or not C_Timer.After then
		return self:ScanNow(reason)
	end

	delay = tonumber(delay) or 0

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
-- # LIFECYCLE
-- ###########################################################################

function RAIDS:OnInitialize()
	LOCAL_LOG("INFO", "Initializing Raids module", METADATA.VERSION)
	self._pendingScan = false
	self._scanToken = 0
	self._ejReady = false
	self._scanWantedAfterCatalog = nil
end

function RAIDS:OnEnable()
	LOCAL_LOG("INFO", "Enabling Raids module")
	-- SavedInstances update
	if RequestRaidInfo and GetNumSavedInstances and GetSavedInstanceInfo then
		self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnUpdateInstanceInfo")
	else
		LOCAL_LOG("WARN", "Saved instances API not available")
	end

	-- Try to build EJ catalog early (gated until EJ is ready)
	self:_EnsureCatalogReady()

	-- Hook into configuration changes
	if type(GMS.RegisterMessage) == "function" then
		self:RegisterMessage("GMS_CONFIG_CHANGED", "OnConfigChanged")
	end

	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
end

function RAIDS:OnConfigChanged(message, targetKey, key, newValue)
	if targetKey == MODULE_NAME then
		if key == "scanLegacy" then
			self:RebuildCatalog()
		end
	end
end

function RAIDS:OnDisable()
	LOCAL_LOG("INFO", "Disabling Raids module")
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end

-- ###########################################################################
-- # EVENTS -> AUTO UPDATE
-- ###########################################################################

function RAIDS:OnPlayerLogin()
	self:_ScheduleScan("login", 2.0)
end

function RAIDS:OnEnteringWorld()
	self:_ScheduleScan("entering_world", 1.0)
end

function RAIDS:OnEncounterEnd(_, _, _, _, _, success)
	if success == 1 then
		self:_ScheduleScan("encounter_end", 1.0)
	end
end

function RAIDS:OnBossKill()
	self:_ScheduleScan("boss_kill", 1.0)
end

-- ###########################################################################
-- # PUBLIC API
-- ###########################################################################

function RAIDS:RebuildCatalog()
	-- HARD GATE: never rebuild before EJ is truly ready
	if not self._ejReady then
		LOCAL_LOG("WARN", "RebuildCatalog blocked: EJ not ready")
		return false
	end

	-- EXTRA SAFETY: ejReady must also mean API present
	if not ejApiPresent() then
		self._ejReady = false
		LOCAL_LOG("WARN", "RebuildCatalog blocked: EJ API missing; reverting ejReady")
		self:_TryLoadEncounterJournal()
		return false
	end

	RAIDS._catalog = buildExpansionRaidCatalog()
	local ok = catalogIsUsable(RAIDS._catalog)

	LOCAL_LOG(ok and "INFO" or "WARN", "Catalog rebuild", RAIDS._catalog.source or "unknown")
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

	if not self:_EnsureCatalogReady() then
		self._scanWantedAfterCatalog = true
		LOCAL_LOG("WARN", "Scan deferred until catalog ready", reason)
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
	self:_EnsureCatalogReady()
	return RAIDS._catalog or {}
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

	if not self:_EnsureCatalogReady() then
		self._scanWantedAfterCatalog = true
		LOCAL_LOG("WARN", "Ingest skipped: catalog not ready")
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
		numEncounters = GetSavedInstanceInfo(i)

		if isRaid == true and type(name) == "string" and name ~= "" then
			local catalog = RAIDS._catalog
			local instanceID = catalog and catalog.nameToInstanceID and catalog.nameToInstanceID[name] or nil
			if not instanceID then
				unresolved = unresolved + 1
			else
				local catRaid = catalog and catalog.byInstanceID and catalog.byInstanceID[instanceID] or nil
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

				-- Only keep CURRENT if lockout-relevant
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

					local dID = tonumber(diffID) or diffID
					if type(dID) == "number" then
						local cur = raidEntry.current[dID]
						if type(cur) ~= "table" then
							cur = {}
							raidEntry.current[dID] = cur
						end

						cur.diffID       = dID
						cur.diffTag      = diffTag(dID)
						cur.killed       = killed
						cur.total        = total
						cur.short        = buildShort(dID, killed, total)
						cur.locked       = locked == true
						cur.extended     = extended == true
						cur.bosses       = bosses
						cur.resetSeconds = tonumber(reset) or reset

						if type(tsNow) == "number" and type(reset) == "number" then
							cur.resetAt = tsNow + reset
						end

						updateBest(raidEntry, dID, killed, total)

						raidEntry.lastScan = tsNow
						raidEntry.lastReason = self._pendingReason
						ingested = ingested + 1
					end
				end
			end
		end
	end

	-- If mapping failed, do one forced rebuild + rescan (only if EJ is ready)
	if unresolved > 0 then
		LOCAL_LOG("WARN", "Unresolved raid name->instanceID mappings", unresolved)
		if self._ejReady then
			self:RebuildCatalog()
			self:_ScheduleScan("rescan_after_unresolved", 2.0)
		end
	end

	LOCAL_LOG("INFO", "Raid scan ingested", ingested, "reason", self._pendingReason or "?", "unresolved", unresolved)
	self._pendingReason = nil
end
