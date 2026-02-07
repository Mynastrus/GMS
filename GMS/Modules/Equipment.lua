-- ============================================================================
--	GMS/Modules/Equipment.lua
--	Equipment MODULE (Ace)
--	- Keine UI
--	- Spricht mit GMS.DB (AceDB) wenn verfügbar, sonst in-memory fallback
--	- Stellt API bereit zum Speichern/Laden von Equipment-Snapshots
--	- Auto-Scan: nach Login (mit Delay) + bei Änderungen
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
	VERSION      = "1.1.0",
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
-- #	INTERNAL STORAGE
-- ###########################################################################

-- DB Pfad:
-- GMS.DB.profile.equipment = {
--   byGuid = { [guid] = snapshot },
--   byName = { ["Name-Realm"] = snapshot },
-- }

EQUIP._mem = {
	byGuid = {},
	byName = {},
}

local function _dbAvailable()
	return GMS.DB and GMS.DB.profile ~= nil
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
		-- Fallback: sofort ausführen
		fn()
	end
end

-- ###########################################################################
-- #	EQUIPMENT SCAN
-- ###########################################################################

local INV_SLOTS = {
	1,  -- Head
	2,  -- Neck
	3,  -- Shoulder
	4,  -- Shirt
	5,  -- Chest
	6,  -- Waist
	7,  -- Legs
	8,  -- Feet
	9,  -- Wrist
	10, -- Hands
	11, -- Finger1
	12, -- Finger2
	13, -- Trinket1
	14, -- Trinket2
	15, -- Back
	16, -- MainHand
	17, -- OffHand
	18, -- Ranged
	19, -- Tabard
}

local function _parseItemStringFromLink(link)
	if type(link) ~= "string" then return nil end
	-- Extrahiert "item:...." aus einem normalen ItemLink
	local itemString = link:match("item:[%-:%d]+")
	return itemString
end

local function _splitItemString(itemString)
	if type(itemString) ~= "string" then return nil end
	-- item:ITEMID:ENCHANT:...
	local parts = {}
	local idx = 0
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

	-- parts[1] = "item"
	-- parts[2] = itemId
	-- parts[3] = enchantId
	local enchantId = tonumber(parts[3]) or nil

	-- Gems: in vielen Clients liegen 4 Gem-Slots danach (pos kann je nach client variieren,
	-- aber klassische Struktur: gem1..gem4 direkt nach enchant)
	-- Wir nehmen konservativ die nächsten 4 Felder.
	local gems = nil
	local g1 = tonumber(parts[4] or "") or nil
	local g2 = tonumber(parts[5] or "") or nil
	local g3 = tonumber(parts[6] or "") or nil
	local g4 = tonumber(parts[7] or "") or nil

	if g1 or g2 or g3 or g4 then
		gems = { g1, g2, g3, g4 }
	end

	return enchantId, gems
end

local function _getPlayerIdentity()
	local name, realm = UnitName and UnitName("player") or nil, nil
	if UnitFullName then
		local n, r = UnitFullName("player")
		if n and n ~= "" then name = n end
		if r and r ~= "" then realm = r end
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
	local guid = UnitGUID and UnitGUID("player") or nil

	return guid, name, realm, class, race, level
end

local function _scanPlayerEquipment()
	local guid, name, realm, class, race, level = _getPlayerIdentity()

	local equippedIlvl, overallIlvl = nil, nil
	if type(GetAverageItemLevel) == "function" then
		-- returns: equipped, total
		local eq, total = GetAverageItemLevel()
		if eq and eq > 0 then equippedIlvl = eq end
		if total and total > 0 then overallIlvl = total end
	end

	local slots = {}

	for _, slotId in ipairs(INV_SLOTS) do
		local itemId = GetInventoryItemID and GetInventoryItemID("player", slotId) or nil
		local link = GetInventoryItemLink and GetInventoryItemLink("player", slotId) or nil

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
			slotId   = slotId,
			itemId   = itemId,
			link     = link,
			ilvl     = itemLevel,
			enchant  = enchantId,
			gems     = gems,
		}
	end

	local snapshot = {
		guid   = guid,
		name   = name,
		realm  = realm,
		class  = class,
		race   = race,
		level  = level,
		ilvl   = equippedIlvl or overallIlvl,
		ilvlEquipped = equippedIlvl,
		ilvlOverall  = overallIlvl,
		slots  = slots,
		ts     = _nowEpoch(),
	}

	return snapshot
end

-- ###########################################################################
-- #	AUTO-SCAN (Login + Changes)
-- ###########################################################################

local LOGIN_DELAY_SEC = 4.0
local CHANGE_DEBOUNCE_SEC = 0.35

EQUIP._scanToken = 0

function EQUIP:_ScheduleScan(delaySec, reason)
	self._scanToken = (self._scanToken or 0) + 1
	local token = self._scanToken

	_schedule(delaySec or 0, function()
		-- Token guard: nur der neueste geplante Scan darf laufen
		if token ~= self._scanToken then return end

		local snap = _scanPlayerEquipment()
		local ok = self:SaveSnapshot(snap)

		if ok then
			LOCAL_LOG("INFO", "Equipment scanned + saved", tostring(reason or "unknown"), snap.guid or "-", _normNameRealm(snap.name, snap.realm) or "-")
		else
			LOCAL_LOG("WARN", "Equipment scan produced invalid snapshot", tostring(reason or "unknown"))
		end
	end)
end

function EQUIP:_OnPlayerLogin()
	-- bewusst kurz warten, damit Inventory/ItemInfo stabil ist
	self:_ScheduleScan(LOGIN_DELAY_SEC, "login-delay")

	-- Optionaler zweiter Pass, falls ItemLinks beim ersten Mal noch nicht da sind
	self:_ScheduleScan(LOGIN_DELAY_SEC + 8.0, "login-second-pass")
end

function EQUIP:_OnEquipmentChanged(slotId, hasItem)
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
	LOCAL_LOG("INFO", "Module initialized (no UI)")

	-- Optional: Registry-Eintrag falls ModuleStates aktiv ist
	if GMS.REGISTRY and GMS.REGISTRY.MOD then
		GMS.REGISTRY.MOD[MODULE_NAME] = {
			key = MODULE_NAME,
			name = METADATA.INTERN_NAME,
			displayName = METADATA.DISPLAY_NAME,
			version = METADATA.VERSION,
			readyKey = "MOD:" .. MODULE_NAME,
			state = { status = "init" },
		}
	end
end

function EQUIP:OnEnable()
	LOCAL_LOG("INFO", "Module enabled")

	-- Wenn DB schon da ist, Tabellen direkt anlegen
	if _dbAvailable() then
		_ensureDbTables()
		LOCAL_LOG("DEBUG", "DB available; tables ensured")
	else
		LOCAL_LOG("DEBUG", "DB not available; using in-memory store")
	end

	-- Events
	self:RegisterEvent("PLAYER_LOGIN", "_OnPlayerLogin")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "_OnEquipmentChanged")
	self:RegisterEvent("UNIT_INVENTORY_CHANGED", "_OnUnitInventoryChanged")

	if GMS.SetReady then
		GMS:SetReady("MOD:" .. MODULE_NAME)
	end
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

-- Snapshot-Format (empfohlen):
-- {
--   guid = "Player-...",
--   name = "Name",
--   realm = "Realm",
--   class = "WARRIOR",
--   ilvl = 512.3,
--   ilvlEquipped = 512.3,
--   ilvlOverall = 512.3,
--   slots = {
--     [slotId] = { itemId=..., link=..., ilvl=..., enchant=..., gems={...} },
--   },
--   ts = epochSeconds,
-- }

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

	local store = _getStore()

	if guid and guid ~= "" then
		store.byGuid[guid] = snapshot
	end

	if keyName then
		store.byName[keyName] = snapshot
	end

	return true
end

function EQUIP:GetSnapshotByGUID(guid)
	if not guid or guid == "" then return nil end
	local store = _getStore()
	return store.byGuid[guid]
end

function EQUIP:GetSnapshotByName(name, realm)
	local keyName = _normNameRealm(name, realm)
	if not keyName then return nil end
	local store = _getStore()
	return store.byName[keyName]
end

function EQUIP:DeleteSnapshotByGUID(guid)
	if not guid or guid == "" then return false end
	local store = _getStore()
	local snap = store.byGuid[guid]
	if not snap then return false end

	if snap.name and snap.name ~= "" then
		local keyName = _normNameRealm(snap.name, snap.realm)
		if keyName then store.byName[keyName] = nil end
	end

	store.byGuid[guid] = nil
	LOCAL_LOG("INFO", "Snapshot deleted (guid)", guid)
	return true
end

function EQUIP:DeleteSnapshotByName(name, realm)
	local keyName = _normNameRealm(name, realm)
	if not keyName then return false end
	local store = _getStore()
	local snap = store.byName[keyName]
	if not snap then return false end

	if snap.guid and snap.guid ~= "" then
		store.byGuid[snap.guid] = nil
	end

	store.byName[keyName] = nil
	LOCAL_LOG("INFO", "Snapshot deleted (name)", keyName)
	return true
end

function EQUIP:ResetAll()
	local store = _getStore()
	store.byGuid = {}
	store.byName = {}
	LOCAL_LOG("WARN", "All equipment snapshots reset")
end

-- Manuelles Triggern (z.B. Debug)
function EQUIP:ScanNow(reason)
	self:_ScheduleScan(0, reason or "manual")
end
