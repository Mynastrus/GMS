-- ============================================================================
--	GMS/Modules/Equipment.lua
--	Equipment MODULE (Ace)
--	- Auto-Scan: nach Login (delayed) + bei Änderungen (debounced)
--	- Speichert Snapshot in GMS.DB (AceDB) sobald verfügbar, sonst in-memory buffer
--	- Migrates in-memory snapshots -> DB sobald EXT:DB ready wird (OnReady + Polling)
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- ###########################################################################
-- #	METADATA
-- ###########################################################################

local METADATA = {
	TYPE         = "MODULE",
	INTERN_NAME  = "Equipment",
	SHORT_NAME   = "EQUIP",
	DISPLAY_NAME = "Ausrüstung",
	VERSION      = "1.2.0",
}

-- ###########################################################################
-- #	LOG BUFFER + LOCAL LOGGER
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
		entry.data = {}
		for i = 1, n do
			entry.data[i] = select(i, ...)
		end
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

local MODULE_NAME = "Equipment"

local EQUIP = GMS:GetModule(MODULE_NAME, true)
if not EQUIP then
	EQUIP = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
end

-- ###########################################################################
-- #	CONFIG
-- ###########################################################################

local LOGIN_DELAY_SEC        = 4.0
local LOGIN_SECOND_PASS_SEC  = 12.0
local CHANGE_DEBOUNCE_SEC    = 0.35

local DB_POLL_MAX_TRIES      = 25
local DB_POLL_INTERVAL_SEC   = 1.0

-- ###########################################################################
-- #	INTERNAL STORAGE (DB + MEM BUFFER)
-- ###########################################################################

EQUIP._mem = EQUIP._mem or { byGuid = {}, byName = {} }
EQUIP._scanToken = EQUIP._scanToken or 0
EQUIP._dbPollTries = EQUIP._dbPollTries or 0

local function _dbAvailable()
	return (GMS.DB and GMS.DB.profile ~= nil) == true
end

local function _ensureDbTables()
	if not _dbAvailable() then return nil end
	local p = GMS.DB.profile

	p.equipment = p.equipment or {}
	p.equipment.byGuid = p.equipment.byGuid or {}
	p.equipment.byName = p.equipment.byName or {}

	return p.equipment
end

local function _getStore()
	if _dbAvailable() then
		local eq = _ensureDbTables()
		if eq then return eq end
	end
	return EQUIP._mem
end

local function _normNameRealm(name, realm)
	if not name or name == "" then return nil end
	if realm and realm ~= "" then
		return tostring(name) .. "-" .. tostring(realm)
	end
	return tostring(name)
end

local function _nowEpoch()
	if type(GetServerTime) == "function" then return GetServerTime() end
	if type(time) == "function" then return time() end
	return nil
end

local function _schedule(delay, fn)
	if type(fn) ~= "function" then return end
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(tonumber(delay or 0) or 0, fn)
	else
		fn()
	end
end

function EQUIP:_MigrateMemToDb()
	if not _dbAvailable() then return false end
	local eq = _ensureDbTables()
	if not eq then return false end

	local moved = 0
	for guid, snap in pairs(self._mem.byGuid or {}) do
		eq.byGuid[guid] = snap
		moved = moved + 1
	end
	for key, snap in pairs(self._mem.byName or {}) do
		eq.byName[key] = snap
	end

	self._mem.byGuid = {}
	self._mem.byName = {}

	LOCAL_LOG("INFO", "Migrated equipment snapshots to DB", moved)
	return true
end

function EQUIP:_TryEnsureDb(reason)
	if _dbAvailable() then
		_ensureDbTables()
		self:_MigrateMemToDb()
		return true
	end
	LOCAL_LOG("DEBUG", "DB not available yet", tostring(reason or "unknown"))
	return false
end

function EQUIP:_StartDbPolling()
	self._dbPollTries = 0

	local function tick()
		self._dbPollTries = (self._dbPollTries or 0) + 1

		if self:_TryEnsureDb("poll") then
			LOCAL_LOG("INFO", "DB became available (poll)", self._dbPollTries)
			return
		end

		if self._dbPollTries >= DB_POLL_MAX_TRIES then
			LOCAL_LOG("WARN", "DB still not available after polling; staying in memory", self._dbPollTries)
			return
		end

		_schedule(DB_POLL_INTERVAL_SEC, tick)
	end

	_schedule(DB_POLL_INTERVAL_SEC, tick)
end

-- ###########################################################################
-- #	EQUIPMENT SCAN
-- ###########################################################################

local INV_SLOTS = { 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19 }

local function _parseItemStringFromLink(link)
	if type(link) ~= "string" then return nil end
	return link:match("item:[%-:%d]+")
end

local function _splitItemString(itemString)
	if type(itemString) ~= "string" then return nil end
	local parts, idx = {}, 0
	for token in itemString:gmatch("([^:]+)") do
		idx = idx + 1
		parts[idx] = token
	end
	return parts
end

local function _extractEnchantAndGems(link)
	local itemString = _parseItemStringFromLink(link)
	if not itemString then return nil, nil end

	local parts = _splitItemString(itemString)
	if not parts or #parts < 3 then return nil, nil end

	local enchantId = tonumber(parts[3]) or nil

	local g1 = tonumber(parts[4] or "") or nil
	local g2 = tonumber(parts[5] or "") or nil
	local g3 = tonumber(parts[6] or "") or nil
	local g4 = tonumber(parts[7] or "") or nil

	local gems = nil
	if g1 or g2 or g3 or g4 then
		gems = { g1, g2, g3, g4 }
	end

	return enchantId, gems
end

local function _getPlayerIdentity()
	local name, realm = nil, nil

	if UnitFullName then
		local n, r = UnitFullName("player")
		if n and n ~= "" then name = n end
		if r and r ~= "" then realm = r end
	end
	if not name and UnitName then
		name = UnitName("player")
	end

	local class = nil
	if UnitClass then
		local _, classTag = UnitClass("player")
		class = classTag
	end

	local race = nil
	if UnitRace then
		local raceName = UnitRace("player")
		race = raceName
	end

	local level = UnitLevel and UnitLevel("player") or nil
	local guid  = UnitGUID  and UnitGUID("player")  or nil

	return guid, name, realm, class, race, level
end

local function _scanPlayerEquipment()
	local guid, name, realm, class, race, level = _getPlayerIdentity()

	local equippedIlvl, overallIlvl = nil, nil
	if type(GetAverageItemLevel) == "function" then
		local eq, total = GetAverageItemLevel()
		if eq and eq > 0 then equippedIlvl = eq end
		if total and total > 0 then overallIlvl = total end
	end

	local slots = {}

	for _, slotId in ipairs(INV_SLOTS) do
		local itemId = (GetInventoryItemID and GetInventoryItemID("player", slotId)) or nil
		local link   = (GetInventoryItemLink and GetInventoryItemLink("player", slotId)) or nil

		local itemLevel = nil
		if link and type(GetDetailedItemLevelInfo) == "function" then
			local ilvl = GetDetailedItemLevelInfo(link)
			if ilvl and ilvl > 0 then itemLevel = ilvl end
		end

		local enchantId, gems = nil, nil
		if link then
			enchantId, gems = _extractEnchantAndGems(link)
		end

		slots[slotId] = {
			slotId  = slotId,
			itemId  = itemId,
			link    = link,
			ilvl    = itemLevel,
			enchant = enchantId,
			gems    = gems,
		}
	end

	return {
		guid         = guid,
		name         = name,
		realm        = realm,
		class        = class,
		race         = race,
		level        = level,
		ilvl         = equippedIlvl or overallIlvl,
		ilvlEquipped = equippedIlvl,
		ilvlOverall  = overallIlvl,
		slots        = slots,
		ts           = _nowEpoch(),
	}
end

-- ###########################################################################
-- #	PUBLIC API
-- ###########################################################################

function EQUIP:UsesDatabase()
	return _dbAvailable() == true
end

function EQUIP:GetStore()
	return _getStore()
end

function EQUIP:SaveSnapshot(snapshot)
	if type(snapshot) ~= "table" then
		LOCAL_LOG("WARN", "SaveSnapshot: invalid snapshot type", type(snapshot))
		return false
	end

	local guid = snapshot.guid
	local keyName = _normNameRealm(snapshot.name, snapshot.realm)

	if (not guid or guid == "") and (not keyName) then
		LOCAL_LOG("WARN", "SaveSnapshot: missing guid and name-realm")
		return false
	end

	if not snapshot.ts then
		snapshot.ts = _nowEpoch()
	end

	-- Erst in aktuellen Store (DB oder MEM) schreiben
	local store = _getStore()

	if guid and guid ~= "" then
		store.byGuid[guid] = snapshot
	end
	if keyName then
		store.byName[keyName] = snapshot
	end

	-- Falls DB inzwischen da ist: MEM -> DB migrieren
	self:_TryEnsureDb("save")

	LOCAL_LOG("INFO", "Snapshot saved", guid or "-", keyName or "-", self:UsesDatabase() and "DB" or "MEM")
	return true
end

function EQUIP:ScanNow(reason)
	self:_ScheduleScan(0, reason or "manual")
end

-- ###########################################################################
-- #	AUTO-SCAN
-- ###########################################################################

function EQUIP:_ScheduleScan(delaySec, reason)
	self._scanToken = (self._scanToken or 0) + 1
	local token = self._scanToken

	_schedule(delaySec or 0, function()
		if token ~= self._scanToken then return end
		local snap = _scanPlayerEquipment()
		local ok = self:SaveSnapshot(snap)
		if ok then
			LOCAL_LOG("INFO", "Equipment scanned + saved", tostring(reason or "unknown"))
		else
			LOCAL_LOG("WARN", "Equipment scan produced invalid snapshot", tostring(reason or "unknown"))
		end
	end)
end

function EQUIP:_OnPlayerLogin()
	-- DB kann später kommen
	self:_StartDbPolling()

	-- bewusst warten
	self:_ScheduleScan(LOGIN_DELAY_SEC, "login-delay")
	self:_ScheduleScan(LOGIN_SECOND_PASS_SEC, "login-second-pass")
end

function EQUIP:_OnEquipmentChanged()
	self:_ScheduleScan(CHANGE_DEBOUNCE_SEC, "equip-changed")
end

function EQUIP:_OnUnitInventoryChanged(unit)
	if unit ~= "player" then return end
	self:_ScheduleScan(CHANGE_DEBOUNCE_SEC, "unit-inv-changed")
end

-- ###########################################################################
-- #	LIFECYCLE
-- ###########################################################################

function EQUIP:OnInitialize()
	LOCAL_LOG("INFO", "Module initialized")

	-- DB-ready Hook
	if type(GMS.OnReady) == "function" then
		GMS:OnReady("EXT:DB", function()
			LOCAL_LOG("INFO", "EXT:DB ready -> ensure DB + migrate")
			self:_TryEnsureDb("onready")
		end)
	end
end

function EQUIP:OnEnable()
	LOCAL_LOG("INFO", "Module enabled")

	self:RegisterEvent("PLAYER_LOGIN", "_OnPlayerLogin")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "_OnEquipmentChanged")
	self:RegisterEvent("UNIT_INVENTORY_CHANGED", "_OnUnitInventoryChanged")

	-- falls DB schon da ist
	self:_TryEnsureDb("enable")

	if GMS.SetReady then
		GMS:SetReady("MOD:" .. MODULE_NAME)
	end
end
