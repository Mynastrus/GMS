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
local IsAddOnLoaded                 = IsAddOnLoaded
local C_AddOns                      = C_AddOns
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
local table                         = table
local string                        = string
---@diagnostic enable: undefined-global

-- ###########################################################################
-- # METADATA
-- ###########################################################################

local METADATA = {
	TYPE         = "MOD",
	INTERN_NAME  = "RAIDS",
	SHORT_NAME   = "Raids",
	DISPLAY_NAME = "Raids",
	VERSION      = "1.2.7",
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
local RAIDS_SYNC_DOMAIN = "RAIDS_V1"

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

local function getDirectCharStore(charKey)
	if not GMS or type(GMS.db) ~= "table" or type(GMS.db.global) ~= "table" then
		return nil
	end
	local global = GMS.db.global
	global.characters = type(global.characters) == "table" and global.characters or {}
	local fallbackKey = UnitGUID and UnitGUID("player") or nil
	local key = tostring(charKey or fallbackKey or "")
	if key == "" then
		return nil
	end
	local charStore = global.characters[key]
	if type(charStore) ~= "table" then
		charStore = {}
		global.characters[key] = charStore
	end
	local raidsStore = charStore.RAIDS
	if type(raidsStore) ~= "table" then
		raidsStore = {}
		charStore.RAIDS = raidsStore
	end
	if raidsStore.scanLegacy == nil then raidsStore.scanLegacy = false end
	if type(raidsStore.rebuild) ~= "table" then
		raidsStore.rebuild = { type = "execute", name = "Katalog neu aufbauen" }
	end
	raidsStore.raids = type(raidsStore.raids) == "table" and raidsStore.raids or {}
	raidsStore.lastScan = tonumber(raidsStore.lastScan) or 0
	return raidsStore
end

local function getRaidsStore()
	local store = getDirectCharStore()
	if not store then return nil end
	store.raids = store.raids or {}
	return store.raids
end

RAIDS.METADATA = METADATA
RAIDS._slashRegistered = RAIDS._slashRegistered or false

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
	local charKey = getPlayerKey()
	if not charKey then return nil, nil end
	local directStore = getDirectCharStore(charKey)
	if type(directStore) ~= "table" then
		LOCAL_LOG("ERROR", "RAIDS direct char store unavailable")
		return nil, nil
	end

	-- Keep options registration for UI compatibility, but always bind runtime
	-- writes to the direct character store to guarantee persistence.
	if not RAIDS._options then
		RAIDS:InitializeOptions()
	end
	if type(RAIDS._options) == "table" and RAIDS._options ~= directStore then
		if directStore.scanLegacy == nil and RAIDS._options.scanLegacy ~= nil then
			directStore.scanLegacy = RAIDS._options.scanLegacy
		end
	end
	RAIDS._options = directStore

	-- Catalog is now local to the module session, not persisted in the options
	if not RAIDS._catalog then
		RAIDS:_EnsureCatalogReady()
	end

	return directStore, charKey
end

local function RegisterRaidsSlash()
	if RAIDS._slashRegistered then return true end
	if type(GMS.Slash_RegisterSubCommand) ~= "function" then
		return false
	end

	GMS:Slash_RegisterSubCommand("raids", function(args)
		local input = tostring(args or "")
		local cmd = input:match("^%s*(%S*)")
		cmd = string.lower(tostring(cmd or ""))

		if cmd == "" or cmd == "scan" then
			local ok = RAIDS:ScanNow("slash_scan")
			if type(GMS.Print) == "function" then
				if ok then
					GMS:Print("Raids: scan requested.")
				else
					GMS:Print("Raids: scan could not be started.")
				end
			end
			return
		end

		if cmd == "rebuild" then
			local ok = RAIDS:RebuildCatalog()
			if type(GMS.Print) == "function" then
				GMS:Print(ok and "Raids: catalog rebuild started." or "Raids: catalog rebuild not available.")
			end
			return
		end

		if type(GMS.Print) == "function" then
			GMS:Print("Usage: /gms raids scan")
		end
	end, {
		help = "/gms raids scan - trigger a raid lockout scan now",
	})

	RAIDS._slashRegistered = true
	return true
end

local function _publishRaidsToGuild(payload, reason)
	local comm = GMS and GMS.Comm or nil
	if type(comm) ~= "table" or type(comm.PublishCharacterRecord) ~= "function" then
		return false, "comm-unavailable"
	end
	local wire = {
		module = METADATA.SHORT_NAME,
		version = METADATA.VERSION,
		reason = tostring(reason or "unknown"),
		raids = payload,
	}
	return comm:PublishCharacterRecord(RAIDS_SYNC_DOMAIN, wire)
end

local function _buildRaidsDigest(raidsStore)
	if type(raidsStore) ~= "table" then return "" end
	local instanceIDs = {}
	for instanceID in pairs(raidsStore) do
		instanceIDs[#instanceIDs + 1] = tonumber(instanceID) or instanceID
	end
	table.sort(instanceIDs, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local out = {}
	for i = 1, #instanceIDs do
		local iid = instanceIDs[i]
		local raidEntry = raidsStore[iid]
		if type(raidEntry) == "table" then
			out[#out + 1] = "I:" .. tostring(iid) .. ":" .. tostring(raidEntry.total or 0)
			local best = raidEntry.best
			if type(best) == "table" then
				out[#out + 1] = "B:" .. tostring(best.diffID or "") .. ":" .. tostring(best.killed or 0) .. "/" .. tostring(best.total or 0)
			else
				out[#out + 1] = "B:-"
			end

			local current = raidEntry.current
			if type(current) == "table" then
				local diffIDs = {}
				for diffID in pairs(current) do
					diffIDs[#diffIDs + 1] = tonumber(diffID) or diffID
				end
				table.sort(diffIDs, function(a, b)
					local an = tonumber(a)
					local bn = tonumber(b)
					if an and bn then return an < bn end
					return tostring(a) < tostring(b)
				end)

				for j = 1, #diffIDs do
					local d = diffIDs[j]
					local cur = current[d]
					if type(cur) == "table" then
						out[#out + 1] = "C:" .. tostring(d) .. ":" .. tostring(cur.killed or 0) .. "/" .. tostring(cur.total or 0)
							.. ":" .. tostring(cur.locked == true)
							.. ":" .. tostring(cur.extended == true)
							.. ":" .. tostring(cur.resetAt or 0)
					end
				end
			end
		end
	end

	return table.concat(out, "|")
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

local function RefreshEJApiBindings()
	-- Rebind globals after Blizzard_EncounterJournal load; locals captured at file load
	-- may still be nil otherwise.
	C_EncounterJournal         = (_G and _G.C_EncounterJournal) or C_EncounterJournal
	EJ_GetNumTiers             = (_G and _G.EJ_GetNumTiers) or EJ_GetNumTiers
	EJ_SelectTier              = (_G and _G.EJ_SelectTier) or EJ_SelectTier
	EJ_GetInstanceByIndex      = (_G and _G.EJ_GetInstanceByIndex) or EJ_GetInstanceByIndex
	EJ_SelectInstance          = (_G and _G.EJ_SelectInstance) or EJ_SelectInstance
	EJ_GetInstanceInfo         = (_G and _G.EJ_GetInstanceInfo) or EJ_GetInstanceInfo
	EJ_GetNumEncounters        = (_G and _G.EJ_GetNumEncounters) or EJ_GetNumEncounters
	EJ_GetEncounterInfoByIndex = (_G and _G.EJ_GetEncounterInfoByIndex) or EJ_GetEncounterInfoByIndex
	EJ_GetTierInfo             = (_G and _G.EJ_GetTierInfo) or EJ_GetTierInfo
	EJ_GetCurrentTier          = (_G and _G.EJ_GetCurrentTier) or EJ_GetCurrentTier
end

local function ejApiPresent()
	RefreshEJApiBindings()
	-- This module uses EJ_* globals; require these callsites explicitly.
	return type(EJ_GetNumTiers) == "function"
		and type(EJ_SelectTier) == "function"
		and type(EJ_GetInstanceByIndex) == "function"
		and type(EJ_SelectInstance) == "function"
		and type(EJ_GetInstanceInfo) == "function"
		and type(EJ_GetNumEncounters) == "function"
		and type(EJ_GetEncounterInfoByIndex) == "function"
		and type(EJ_GetTierInfo) == "function"
		and type(EJ_GetCurrentTier) == "function"
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

local function normalizeRaidName(name)
	name = tostring(name or "")
	if name == "" then return "" end
	name = string.lower(name)
	return (name:gsub("[%s%p]+", ""))
end

local function buildExpansionRaidCatalog()
	local catalog = {
		byInstanceID = {},
		nameToInstanceID = {},
		nameNormToInstanceID = {},
		encounterToInstanceID = {},
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
			-- Current tier can be user-selected in EJ and may not include current raids.
			-- Fall back to all tiers to keep name->instance mapping robust.
			for t = 1, numTiers do tiersToScan[#tiersToScan + 1] = t end
			catalog.source = "EJ_ALL_TIERS_FALLBACK"
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
				local normalizedName = normalizeRaidName(raidName)
				if normalizedName ~= "" then
					catalog.nameNormToInstanceID[normalizedName] = instanceID
				end
				for j = 1, #encounters do
					local encounterID = tonumber(encounters[j] and encounters[j].id or nil)
					if encounterID then
						catalog.encounterToInstanceID[encounterID] = instanceID
					end
				end
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

	local addonName = "Blizzard_EncounterJournal"
	local alreadyLoaded = false
	if type(C_AddOns) == "table" and type(C_AddOns.IsAddOnLoaded) == "function" then
		alreadyLoaded = C_AddOns.IsAddOnLoaded(addonName) == true
	elseif type(IsAddOnLoaded) == "function" then
		alreadyLoaded = IsAddOnLoaded(addonName) == true
	end
	if alreadyLoaded then
		RefreshEJApiBindings()
		return ejApiPresent()
	end

	if type(C_AddOns) == "table" and type(C_AddOns.LoadAddOn) == "function" then
		local ok, reason = C_AddOns.LoadAddOn(addonName)
		if ok then
			RefreshEJApiBindings()
			return true
		end
		LOCAL_LOG("WARN", "C_AddOns.LoadAddOn failed", reason)
		return false
	end

	if type(LoadAddOn) == "function" then
		local loaded, reason = LoadAddOn(addonName)
		if loaded then
			RefreshEJApiBindings()
			return true
		end
		LOCAL_LOG("WARN", "LoadAddOn failed", reason)
		return false
	end

	LOCAL_LOG("WARN", "No API available to load Blizzard_EncounterJournal")
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
	if self._ejUnsupported then
		if self.UnregisterEvent then
			self:UnregisterEvent("EJ_DIFFICULTY_UPDATE")
		end
		return
	end

	-- STRICT: do not accept readiness if APIs are still missing
	if not ejApiPresent() then
		self._ejReady = false
		self._ejUnsupported = true
		LOCAL_LOG("INFO", "EJ event received but EJ API missing; switching to fallback mode")
		if self.UnregisterEvent then
			self:UnregisterEvent("EJ_DIFFICULTY_UPDATE")
		end
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

	if self._ejUnsupported then
		return false
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
	self:InitializeOptions()
	self._pendingScan = false
	self._scanToken = 0
	self._ejReady = false
	self._ejUnsupported = false
	self._scanWantedAfterCatalog = nil
end

function RAIDS:OnEnable()
	LOCAL_LOG("INFO", "Enabling Raids module")
	self:InitializeOptions()

	-- SavedInstances update
	if RequestRaidInfo and GetNumSavedInstances and GetSavedInstanceInfo then
		self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnUpdateInstanceInfo")
	else
		LOCAL_LOG("WARN", "Saved instances API not available")
	end

	self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
	self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
	self:RegisterEvent("BOSS_KILL", "OnBossKill")

	if not self:_ProbeEJReady() then
		local loaded = self:_TryLoadEncounterJournal()
		if not loaded and not ejApiPresent() then
			self._ejUnsupported = true
			LOCAL_LOG("INFO", "EncounterJournal API unavailable; running raids in SavedInstances fallback mode")
		else
			self:RegisterEvent("ADDON_LOADED", "ADDON_LOADED")
		end
	end

	RegisterRaidsSlash()
	if type(GMS.OnReady) == "function" then
		GMS:OnReady("EXT:SLASH", RegisterRaidsSlash)
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
	if type(self.UnregisterAllEvents) == "function" then
		self:UnregisterAllEvents()
	end
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
	if self._ejUnsupported then
		LOCAL_LOG("INFO", "RebuildCatalog skipped: EJ unsupported on this client (fallback mode)")
		return false
	end

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

	self:_EnsureCatalogReady()

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

	local catalogReady = self:_EnsureCatalogReady()
	if not catalogReady then
		self._scanWantedAfterCatalog = true
		LOCAL_LOG("WARN", "Catalog not ready; ingest continues with name-based fallback keys")
	end

	local raidsStore = getRaidsStore()
	if type(raidsStore) ~= "table" then
		LOCAL_LOG("WARN", "OnUpdateInstanceInfo: raids store unavailable")
		return
	end
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
	local fallbackMapped = 0
	local unresolvedDetails = {}
	local rawDetails = {}

	for i = 1, num do
		local info = { GetSavedInstanceInfo(i) }
		local name = info[1]
		local reset = info[3]
		local diffID = info[4]
		local locked = info[5]
		local extended = info[6]
		-- WoW 12.x return layout:
		-- 8=isRaid, 9=maxPlayers, 10=difficultyName, 11=numEncounters, 12=encounterProgress
		local isRaid = info[8]
		local maxPlayers = info[9]
		local difficultyName = tostring(info[10] or "")
		local numEncounters = info[11]
		local encounterProgress = info[12]

		if type(name) == "string" and name ~= "" then
			local encCount = tonumber(numEncounters) or 0
			local progress = tonumber(encounterProgress) or 0
			if progress > encCount then
				encCount = progress
			end

			local looksLikeRaid = (isRaid == true)
			if not looksLikeRaid then
				local dn = string.lower(difficultyName or "")
				local mp = tonumber(maxPlayers) or 0
				if dn:find("schlachtzugsbrowser", 1, true)
					or dn:find("raid finder", 1, true)
					or dn:find("lfr", 1, true)
					or dn:find("normal", 1, true)
					or dn:find("heroic", 1, true)
					or dn:find("heroisch", 1, true)
					or dn:find("mythic", 1, true)
					or dn:find("mythisch", 1, true)
					or (mp > 5 and (encCount > 0 or progress > 0)) then
					looksLikeRaid = true
				end
			end
			if looksLikeRaid then
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
				-- Some raid modes expose only aggregate progress.
				if progress > killed then
					killed = progress
				end

				local dID = tonumber(diffID) or diffID
				if type(dID) ~= "number" then
					local dn = string.lower(tostring(difficultyName or ""))
					if dn:find("schlachtzugsbrowser", 1, true) or dn:find("raid finder", 1, true) or dn:find("lfr", 1, true) then
						dID = 17
					elseif dn:find("mythisch", 1, true) or dn:find("mythic", 1, true) then
						dID = 16
					elseif dn:find("heroisch", 1, true) or dn:find("heroic", 1, true) then
						dID = 15
					elseif dn:find("normal", 1, true) then
						dID = 14
					else
						-- API 12.x fallback: if diffID is missing, keep progress by assigning LFR bucket.
						dID = 17
					end
				end

				local catalog = RAIDS._catalog
				local instanceID = catalog and catalog.nameToInstanceID and catalog.nameToInstanceID[name] or nil
				if not instanceID then
					local normalizedName = normalizeRaidName(name)
					instanceID = (normalizedName ~= "" and catalog and catalog.nameNormToInstanceID and catalog.nameNormToInstanceID[normalizedName]) or nil
				end
				if not instanceID and catalog and type(catalog.encounterToInstanceID) == "table" then
					for encID in pairs(bosses) do
						local iid = catalog.encounterToInstanceID[tonumber(encID) or encID]
						if iid then
							instanceID = iid
							break
						end
					end
				end
				if not instanceID then
					local nkey = normalizeRaidName(name)
					if nkey ~= "" then
						instanceID = "name:" .. nkey
						fallbackMapped = fallbackMapped + 1
					else
						unresolved = unresolved + 1
					end
				end
				if instanceID then
					local catRaid = catalog and catalog.byInstanceID and catalog.byInstanceID[instanceID] or nil
					local total = (catRaid and catRaid.total) or (tonumber(numEncounters) or 0)
					if total <= 0 then total = encCount end

					-- Only keep CURRENT if lockout-relevant
					if locked == true or extended == true or killed > 0 or progress > 0 then
						local raidEntry = raidsStore[instanceID]
						if type(raidEntry) ~= "table" then
							raidEntry = {}
							raidsStore[instanceID] = raidEntry
						end

						raidEntry.instanceID = instanceID
						raidEntry.name = (catRaid and catRaid.name) or name
						raidEntry.total = total
						raidEntry.current = raidEntry.current or {}

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
				else
					unresolved = unresolved + 1
					if #unresolvedDetails < 10 then
						unresolvedDetails[#unresolvedDetails + 1] = string.format(
							"name=%s diff=%s difficulty=%s progress=%s/%s locked=%s extended=%s",
							tostring(name or "-"),
							tostring(dID or "-"),
							tostring(difficultyName or "-"),
							tostring(killed or 0),
							tostring(encCount or 0),
							tostring(locked == true),
							tostring(extended == true)
						)
					end
				end
			elseif #rawDetails < 5 then
				rawDetails[#rawDetails + 1] = string.format(
					"skip name=%s isRaid=%s maxPlayers=%s diff=%s difficulty=%s progress=%s/%s",
					tostring(name), tostring(isRaid), tostring(maxPlayers), tostring(diffID), tostring(difficultyName), tostring(progress), tostring(encCount)
				)
			end
		end
	end

	if ingested == 0 and #rawDetails > 0 then
		LOCAL_LOG("WARN", "SavedInstances skipped entries", table.concat(rawDetails, " || "))
	end

	-- If mapping failed, do one forced rebuild + rescan (only if EJ is ready)
	if unresolved > 0 then
		LOCAL_LOG("WARN", "Unresolved raid name->instanceID mappings", unresolved)
		if #unresolvedDetails > 0 then
			LOCAL_LOG("WARN", "Unresolved raid details", table.concat(unresolvedDetails, " || "))
		end
		if self._ejReady then
			self:RebuildCatalog()
			self:_ScheduleScan("rescan_after_unresolved", 2.0)
		end
	end

	store.lastScan = tsNow or now()
	local digest = _buildRaidsDigest(raidsStore)
	local previousDigest = tostring(store.lastDigest or "")
	store.lastDigest = digest
	if digest ~= "" and digest ~= previousDigest then
		local ok, publishReason = _publishRaidsToGuild(raidsStore, self._pendingReason)
		if ok then
			LOCAL_LOG("INFO", "Raids snapshot published", self._pendingReason or "?")
		else
			LOCAL_LOG("WARN", "Raids publish failed", tostring(publishReason or "unknown"), self._pendingReason or "?")
		end
		local roster = GMS and (GMS:GetModule("ROSTER", true) or GMS:GetModule("Roster", true)) or nil
		if type(roster) == "table" and type(roster.BroadcastMetaHeartbeat) == "function" then
			roster:BroadcastMetaHeartbeat(true)
		end
	end

	LOCAL_LOG("INFO", "Raid scan ingested", ingested, "reason", self._pendingReason or "?", "unresolved", unresolved, "fallbackMapped", fallbackMapped)
	self._pendingReason = nil
end
