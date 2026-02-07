-- ============================================================================
--  GMS/Modules/Equipment.lua
--  Equipment MODULE (Ace)
--  - Keine UI
--  - Spricht mit GMS.DB (AceDB) wenn verfügbar, sonst in-memory fallback
--  - Stellt API bereit zum Speichern/Laden von Equipment-Snapshots
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- ###########################################################################
-- #  METADATA
-- ###########################################################################

local METADATA = {
	TYPE         = "MODULE",
	INTERN_NAME  = "Equipment",
	SHORT_NAME   = "EQUIP",
	DISPLAY_NAME = "Ausrüstung",
	VERSION      = "1.0.0",
}

-- ###########################################################################
-- #  LOG BUFFER + LOCAL LOGGER
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
-- #  MODULE
-- ###########################################################################

local MODULE_NAME = "Equipment"

local EQUIP = GMS:GetModule(MODULE_NAME, true)
if not EQUIP then
	EQUIP = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
end

-- ###########################################################################
-- #  INTERNAL STORAGE
-- ###########################################################################
-- DB Pfad:
--   GMS.DB.profile.equipment = {
--      byGuid = { [guid] = snapshot },
--      byName = { ["Name-Realm"] = snapshot },
--   }

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
	-- WoW: time() ist epoch seconds; GetServerTime() existiert in neueren Clients.
	if type(GetServerTime) == "function" then
		return GetServerTime()
	end
	if type(time) == "function" then
		return time()
	end
	return nil
end

-- ###########################################################################
-- #  LIFECYCLE
-- ###########################################################################

function EQUIP:OnInitialize()
	LOCAL_LOG("INFO", "Module initialized (no UI)")

	-- Optional: Registry-Eintrag falls ModuleStates aktiv ist
	if GMS.REGISTRY and GMS.REGISTRY.MOD then
		GMS.REGISTRY.MOD[MODULE_NAME] = {
			key         = MODULE_NAME,
			name        = METADATA.INTERN_NAME,
			displayName = METADATA.DISPLAY_NAME,
			version     = METADATA.VERSION,
			readyKey    = "MOD:" .. MODULE_NAME,
			state       = "init",
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

	if GMS.SetReady then
		GMS:SetReady("MOD:" .. MODULE_NAME)
	end
end

-- ###########################################################################
-- #  PUBLIC API
-- ###########################################################################

-- Gibt true zurück, wenn tatsächlich AceDB (GMS.DB) genutzt wird
function EQUIP:UsesDatabase()
	return _dbAvailable() == true
end

-- Liefert den aktuellen Store (DB oder Memory). Nur lesen/diagnose.
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
--   slots = { [slotId]= { itemId=..., link=..., enchant=..., gems=... }, ... },
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

	LOCAL_LOG("INFO", "Snapshot saved", guid or "-", keyName or "-")
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

	-- auch byName aufräumen, falls vorhanden
	if snap.name and snap.name ~= "" then
		local keyName = _normNameRealm(snap.name, snap.realm)
		if keyName then
			store.byName[keyName] = nil
		end
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

-- Optional: komplettes Löschen (z.B. Debug / Reset)
function EQUIP:ResetAll()
	local store = _getStore()
	store.byGuid = {}
	store.byName = {}
	LOCAL_LOG("WARN", "All equipment snapshots reset")
end
