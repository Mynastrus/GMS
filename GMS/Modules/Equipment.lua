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

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G            = _G
local GetTime       = GetTime
local type          = type
local tostring      = tostring
local select        = select
local pairs         = pairs
local ipairs        = ipairs
local pcall         = pcall
local tonumber      = tonumber
local C_Timer       = C_Timer
local C_Item        = C_Item
local ItemLocation  = ItemLocation
local UnitGUID      = UnitGUID
local UnitName      = UnitName
local UnitFullName  = UnitFullName
local GetServerTime = GetServerTime
local time          = time
local table         = table
local string        = string
---@diagnostic enable: undefined-global

-- ###########################################################################
-- #	METADATA
-- ###########################################################################

local METADATA = {
	TYPE         = "MOD",
	INTERN_NAME  = "Equipment",
	SHORT_NAME   = "EQUIP",
	DISPLAY_NAME = "Ausrüstung",
	VERSION      = "1.3.7",
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

-- Registration
if GMS and type(GMS.RegisterModule) == "function" then
	GMS:RegisterModule(EQUIP, METADATA)
end

-- ###########################################################################
-- #	CONFIG
-- ###########################################################################

local LOGIN_DELAY_SEC       = 4.0
local LOGIN_SECOND_PASS_SEC = 12.0
local CHANGE_DEBOUNCE_SEC   = 0.35

local STORE_POLL_MAX_TRIES = 25
local STORE_POLL_INTERVAL  = 1.0
local EQUIP_SYNC_DOMAIN    = "EQUIPMENT_V1"

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

-- Equipment options (migrated to RegisterModuleOptions API)
EQUIP._options = EQUIP._options or nil

local OPTIONS_DEFAULTS = {
	autoScan = true,
	lastScanTs = 0,
}

-- Equipment data storage (managed via new API)
local function _getDirectCharOptionsStore()
	if GMS and type(GMS.InitializeStandardDatabases) == "function" then
		GMS:InitializeStandardDatabases(false)
	end

	if not GMS or type(GMS.db) ~= "table" or type(GMS.db.global) ~= "table" then
		return nil
	end

	local charKey = _getCharKey()
	if type(charKey) ~= "string" or charKey == "" then
		if type(GMS.GetCharacterGUID) == "function" then
			charKey = GMS:GetCharacterGUID()
		end
	end
	if type(charKey) ~= "string" or charKey == "" then
		return nil
	end

	local global = GMS.db.global
	global.characters = type(global.characters) == "table" and global.characters or {}
	local charStore = global.characters[charKey]
	if type(charStore) ~= "table" then
		charStore = {}
		global.characters[charKey] = charStore
	end

	local optStore = charStore.EQUIPMENT
	if type(optStore) ~= "table" then
		optStore = {}
		charStore.EQUIPMENT = optStore
	end

	if optStore.autoScan == nil then
		optStore.autoScan = OPTIONS_DEFAULTS.autoScan
	end
	optStore.lastScanTs = tonumber(optStore.lastScanTs) or tonumber(OPTIONS_DEFAULTS.lastScanTs) or 0
	optStore.equipment = type(optStore.equipment) == "table" and optStore.equipment or {}

	return optStore
end

local function _getOptionsStore()
	local direct = _getDirectCharOptionsStore()
	if type(direct) == "table" then
		EQUIP._options = direct
		return direct
	end
	return EQUIP._options
end

local function _getEquipmentStore()
	local opts = _getOptionsStore()
	if type(opts) ~= "table" then return nil end
	opts.equipment = opts.equipment or {}
	return opts.equipment
end

function EQUIP:InitializeOptions()
	-- Register equipment options using new API
	if GMS and type(GMS.RegisterModuleOptions) == "function" then
		pcall(function()
			GMS:RegisterModuleOptions("Equipment", OPTIONS_DEFAULTS, "CHAR")
		end)
	end

	-- Retrieve options table
	if GMS and type(GMS.GetModuleOptions) == "function" then
		local ok, opts = pcall(GMS.GetModuleOptions, GMS, "Equipment")
		if ok and opts then
			self._options = opts
		else
			LOCAL_LOG("WARN", "Failed to retrieve Equipment options")
		end
	end

	local direct = _getDirectCharOptionsStore()
	if type(direct) == "table" then
		self._options = direct
		if type(self._mem) == "table" and type(self._mem.snapshot) == "table" then
			local memSnap = self._mem.snapshot
			self._mem.snapshot = nil
			self:SaveSnapshot(memSnap, "mem-flush")
		end
		LOCAL_LOG("INFO", "Equipment options initialized (direct CHAR store)")
	else
		if self._options and type(self._mem) == "table" and type(self._mem.snapshot) == "table" then
			local memSnap = self._mem.snapshot
			self._mem.snapshot = nil
			self:SaveSnapshot(memSnap, "mem-flush")
		end
		if self._options then
			LOCAL_LOG("INFO", "Equipment options initialized")
		else
			LOCAL_LOG("WARN", "Equipment options unavailable after initialization")
		end
	end
end

-- ###########################################################################
-- #	EQUIPMENT SCAN (minimal: only item links + owner guid)
-- ###########################################################################

local INV_SLOTS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }

local function _getPlayerGuid()
	return UnitGUID and UnitGUID("player") or nil
end

local function _splitKeepingEmpty(input, sep)
	local txt = tostring(input or "")
	local out = {}
	local start = 1
	while true do
		local pos = string.find(txt, sep, start, true)
		if not pos then
			out[#out + 1] = string.sub(txt, start)
			break
		end
		out[#out + 1] = string.sub(txt, start, pos - 1)
		start = pos + 1
	end
	return out
end

local function _extractItemString(link)
	if type(link) ~= "string" or link == "" then return nil end
	local itemString = link:match("|H(item:[^|]+)|h")
	if type(itemString) ~= "string" or itemString == "" then return nil end
	return itemString
end

local function _parseItemLink(link, itemLoc, slotId)
	if type(link) ~= "string" or link == "" then return nil end
	local itemString = _extractItemString(link)
	if not itemString then return nil end

	local parts = _splitKeepingEmpty(itemString, ":")
	local numBonusIds = tonumber(parts[14] or "0") or 0
	local bonusIds = {}
	if numBonusIds > 0 then
		for i = 1, numBonusIds do
			bonusIds[i] = tonumber(parts[14 + i] or "0") or 0
		end
	end

	local itemLevel = nil
	if type(C_Item) == "table" and type(C_Item.GetCurrentItemLevel) == "function" and itemLoc then
		itemLevel = tonumber(C_Item.GetCurrentItemLevel(itemLoc) or 0) or nil
		if itemLevel and itemLevel <= 0 then itemLevel = nil end
	end

	return {
		slotId = tonumber(slotId) or 0,
		link = link,
		itemString = itemString,
		itemId = tonumber(parts[2] or "0") or 0,
		enchantId = tonumber(parts[3] or "0") or 0,
		gemIds = {
			tonumber(parts[4] or "0") or 0,
			tonumber(parts[5] or "0") or 0,
			tonumber(parts[6] or "0") or 0,
			tonumber(parts[7] or "0") or 0,
		},
		bonusIds = bonusIds,
		itemLevel = itemLevel,
	}
end

local function _buildSnapshotDigest(snapshot)
	if type(snapshot) ~= "table" then return "" end
	local slots = type(snapshot.slots) == "table" and snapshot.slots or {}
	local parts = {}
	for i = 1, #INV_SLOTS do
		local slotId = INV_SLOTS[i]
		local parsed = slots[slotId]
		local itemString = (type(parsed) == "table" and parsed.itemString) or ""
		local itemLevel = (type(parsed) == "table" and tonumber(parsed.itemLevel)) or 0
		parts[#parts + 1] = tostring(slotId) .. "=" .. tostring(itemString) .. "@" .. tostring(itemLevel)
	end
	return table.concat(parts, "|")
end

function EQUIP:_PublishSnapshotToGuild(snapshot, reason)
	local comm = GMS and GMS.Comm or nil
	if type(comm) ~= "table" or type(comm.PublishCharacterRecord) ~= "function" then
		return false, "comm-unavailable"
	end
	local payload = {
		module = METADATA.SHORT_NAME,
		version = METADATA.VERSION,
		reason = tostring(reason or "unknown"),
		snapshot = snapshot,
	}
	return comm:PublishCharacterRecord(EQUIP_SYNC_DOMAIN, payload)
end

local function _scanPlayerEquipment()
	local guid = _getPlayerGuid()

	local slots = {}
	for _, slotId in ipairs(INV_SLOTS) do
		local itemLoc = nil
		if type(ItemLocation) == "table" and type(ItemLocation.CreateFromEquipmentSlot) == "function" then
			itemLoc = ItemLocation:CreateFromEquipmentSlot(slotId)
		end
		if type(C_Item) == "table" and itemLoc and type(C_Item.DoesItemExist) == "function" and C_Item.DoesItemExist(itemLoc) then
			local link = type(C_Item.GetItemLink) == "function" and C_Item.GetItemLink(itemLoc) or nil
			slots[slotId] = _parseItemLink(link, itemLoc, slotId)
		else
			slots[slotId] = nil
		end
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

function EQUIP:GetStore()
	return _getEquipmentStore()
end

function EQUIP:SaveSnapshot(snapshot, reason)
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

	local digest = _buildSnapshotDigest(snapshot)

	local store = _getEquipmentStore()
	if not store then
		self._mem = self._mem or {}
		self._mem.snapshot = snapshot
		self._mem.lastDigest = digest
		LOCAL_LOG("WARN", "SaveSnapshot: Equipment options not available, stored in memory buffer")
		return true
	end

	local previousDigest = tostring(store.lastDigest or "")
	store.snapshot = snapshot
	store.lastDigest = digest
	local opts = _getOptionsStore()
	if opts then
		opts.lastScanTs = snapshot.ts or 0
	end

	if digest ~= "" and digest ~= previousDigest then
		local ok, publishReason = self:_PublishSnapshotToGuild(snapshot, reason)
		if ok then
			LOCAL_LOG("INFO", "Equipment snapshot published", tostring(reason or "unknown"))
		else
			LOCAL_LOG("WARN", "Equipment publish failed", tostring(publishReason or "unknown"), tostring(reason or "unknown"))
		end
	end

	LOCAL_LOG("INFO", "Equipment snapshot saved")
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
		local ok = self:SaveSnapshot(snap, reason)

		if ok then
			LOCAL_LOG("INFO", "Equipment scanned + saved", tostring(reason or "unknown"))
		else
			LOCAL_LOG("WARN", "Equipment scan produced invalid snapshot", tostring(reason or "unknown"))
		end
	end)
end

function EQUIP:_OnPlayerLogin()
	-- Delayed scans after login
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
	self:InitializeOptions()
end

function EQUIP:OnEnable()
	LOCAL_LOG("INFO", "Module enabled")

	self:RegisterEvent("PLAYER_LOGIN", "_OnPlayerLogin")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "_OnEquipmentChanged")
	self:RegisterEvent("UNIT_INVENTORY_CHANGED", "_OnUnitInventoryChanged")

	self:InitializeOptions()

	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
end

function EQUIP:OnDisable()
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end
