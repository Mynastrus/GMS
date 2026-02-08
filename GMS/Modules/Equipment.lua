-- ============================================================================
--	GMS/Modules/Equipment.lua
--	Equipment MODULE (Ace)
--	- Auto-Scan: nach Login (delayed) + bei Änderungen (debounced)
--	- Speichert Snapshot pro Charakter in SavedVariables: GMS_DB.global.characters[charKey].EQUIPMENT
--	  (global, damit andere Chars es sehen können)
--	- charKey: UnitGUID("player") (Fallback: Name-Realm)
--	- Memory buffer falls SV noch nicht verfügbar ist, Migration sobald möglich
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
	VERSION      = "1.3.4",
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

local LOGIN_DELAY_SEC       = 4.0
local LOGIN_SECOND_PASS_SEC = 12.0
local CHANGE_DEBOUNCE_SEC   = 0.35

local STORE_POLL_MAX_TRIES = 25
local STORE_POLL_INTERVAL  = 1.0

-- ###########################################################################
-- #	INTERNAL STATE
-- ###########################################################################

EQUIP._scanToken = EQUIP._scanToken or 0
EQUIP._pollTries = EQUIP._pollTries or 0

-- Memory buffer, falls SavedVariables noch nicht verfügbar sind
EQUIP._mem = EQUIP._mem or {
	snapshot = nil,
}

-- ###########################################################################
-- #	UTILS
-- ###########################################################################

local function _schedule(delay, fn)
	if type(fn) ~= "function" then return end
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(tonumber(delay or 0) or 0, fn)
	else
		fn()
	end
end

local function _nowEpoch()
	if type(GetServerTime) == "function" then return GetServerTime() end
	if type(time) == "function" then return time() end
	return nil
end

local function _svAvailable()
	return type(GMS_DB) == "table"
end

local function _getCharKey()
	local guid = UnitGUID and UnitGUID("player") or nil
	if guid and guid ~= "" then return guid end

	local name, realm = nil, nil
	if UnitFullName then
		local n, r = UnitFullName("player")
		if n and n ~= "" then name = n end
		if r and r ~= "" then realm = r end
	end
	if not name and UnitName then
		name = UnitName("player")
	end

	if name and name ~= "" then
		if realm and realm ~= "" then
			return tostring(name) .. "-" .. tostring(realm)
		end
		return tostring(name)
	end

	return nil
end

local function _ensureSvTables()
	if not _svAvailable() then return nil end

	local key = _getCharKey()
	if not key then return nil end

	GMS_DB.global = GMS_DB.global or {}
	GMS_DB.global.characters = GMS_DB.global.characters or {}

	local c = GMS_DB.global.characters[key]
	if not c then
		c = { __version = 1 }
		GMS_DB.global.characters[key] = c
	end

	c.EQUIPMENT = c.EQUIPMENT or {}
	return c.EQUIPMENT, key
end

local function _getStore()
	local eq = _ensureSvTables()
	if eq then return eq, true end
	return EQUIP._mem, false
end

function EQUIP:_MigrateMemToSv()
	local eq = _ensureSvTables()
	if not eq then return false end

	if self._mem.snapshot then
		eq.snapshot = self._mem.snapshot
		self._mem.snapshot = nil
		LOCAL_LOG("INFO", "Migrated buffered equipment snapshot to SV.global.characters")
		return true
	end

	return false
end

function EQUIP:_TryEnsureStore(reason)
	local eq = _ensureSvTables()
	if eq then
		self:_MigrateMemToSv()
		return true
	end
	LOCAL_LOG("DEBUG", "SV store not available yet", tostring(reason or "unknown"))
	return false
end

function EQUIP:_StartStorePolling()
	self._pollTries = 0

	local function tick()
		self._pollTries = (self._pollTries or 0) + 1

		if self:_TryEnsureStore("poll") then
			LOCAL_LOG("INFO", "SV store available (poll)", self._pollTries)
			return
		end

		if self._pollTries >= STORE_POLL_MAX_TRIES then
			LOCAL_LOG("WARN", "SV store still not available after polling; staying in memory", self._pollTries)
			return
		end

		_schedule(STORE_POLL_INTERVAL, tick)
	end

	_schedule(STORE_POLL_INTERVAL, tick)
end

-- ###########################################################################
-- #	EQUIPMENT SCAN (minimal: only item links + owner guid)
-- ###########################################################################

local INV_SLOTS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }

local function _getPlayerGuid()
	return UnitGUID and UnitGUID("player") or nil
end

local function _scanPlayerEquipmentMinimal()
	local guid = _getPlayerGuid()

	local slots = {}
	for _, slotId in ipairs(INV_SLOTS) do
		local link = (GetInventoryItemLink and GetInventoryItemLink("player", slotId)) or nil
		-- store only link (or nil if empty)
		slots[slotId] = link
	end

	return {
		guid  = guid,
		ts    = _nowEpoch(),
		slots = slots,
	}
end

-- ###########################################################################
-- #	PUBLIC API
-- ###########################################################################

function EQUIP:UsesDatabase()
	return _svAvailable() == true
end

function EQUIP:GetStore()
	local store = _getStore()
	return store
end

function EQUIP:SaveSnapshot(snapshot)
	if type(snapshot) ~= "table" then
		LOCAL_LOG("WARN", "SaveSnapshot: invalid snapshot type", type(snapshot))
		return false
	end

	if not snapshot.guid or snapshot.guid == "" then
		LOCAL_LOG("WARN", "SaveSnapshot: missing guid")
		return false
	end

	if not snapshot.ts then
		snapshot.ts = _nowEpoch()
	end

	if type(snapshot.slots) ~= "table" then
		snapshot.slots = {}
	end

	local store, isSv = _getStore()
	store.snapshot = snapshot

	self:_TryEnsureStore("save")

	LOCAL_LOG("INFO", "Snapshot saved", isSv and "SV.global.characters" or "MEM")
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

		local snap = _scanPlayerEquipmentMinimal()
		local ok = self:SaveSnapshot(snap)

		if ok then
			LOCAL_LOG("INFO", "Equipment scanned + saved", tostring(reason or "unknown"))
		else
			LOCAL_LOG("WARN", "Equipment scan produced invalid snapshot", tostring(reason or "unknown"))
		end
	end)
end

function EQUIP:_OnPlayerLogin()
	self:_StartStorePolling()

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

	-- Store-ready Hook (DB init bedeutet i.d.R. auch: SV existiert)
	if type(GMS.OnReady) == "function" then
		GMS:OnReady("EXT:DB", function()
			LOCAL_LOG("INFO", "EXT:DB ready -> ensure store + migrate")
			self:_TryEnsureStore("onready")
		end)
	end
end

function EQUIP:OnEnable()
	LOCAL_LOG("INFO", "Module enabled")

	self:RegisterEvent("PLAYER_LOGIN", "_OnPlayerLogin")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "_OnEquipmentChanged")
	self:RegisterEvent("UNIT_INVENTORY_CHANGED", "_OnUnitInventoryChanged")

	self:_TryEnsureStore("enable")

	self:_TryEnsureStore("enable")

	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
end

function EQUIP:OnDisable()
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end
