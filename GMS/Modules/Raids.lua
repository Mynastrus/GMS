-- ============================================================================
--  GMS/Modules/Raids.lua
--  RAIDS MODULE (Ace)
--  - Kein UI
--  - Persistenz: GMS_DB.global.characters[charKey].RAIDS
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
	VERSION      = "2.0.0",
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

-- ###########################################################################
-- # LIFECYCLE
-- ###########################################################################

function RAIDS:OnInitialize()
	LOCAL_LOG("INFO", "Initializing Raids module", METADATA.VERSION)
end

function RAIDS:OnEnable()
	LOCAL_LOG("INFO", "Enabling Raids module")
end

function RAIDS:OnDisable()
	LOCAL_LOG("INFO", "Disabling Raids module")
end

-- ###########################################################################
-- # PUBLIC API (DB-backed)
-- ###########################################################################

-- Ensures the storage table exists and returns the character table:
-- GMS_DB.global.characters[charKey]
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

-- Returns the RAIDS table (or nil if db not ready / charKey missing)
function RAIDS:GetRaids(charKey)
	local c = self:EnsureCharacter(charKey)
	return c and c.RAIDS or nil
end

-- Replaces RAIDS table with the given one (table expected)
function RAIDS:SetRaids(charKey, raidsTable)
	if type(raidsTable) ~= "table" then
		LOCAL_LOG("WARN", "SetRaids expects a table", type(raidsTable))
		return false
	end

	local c = self:EnsureCharacter(charKey)
	if not c then return false end

	c.RAIDS = raidsTable
	LOCAL_LOG("INFO", "RAIDS table replaced", charKey, #raidsTable)
	return true
end

-- Adds a raid entry. Returns (ok, idOrNil)
-- Entry example:
-- { name="Nerub-ar Palace", diff=3, time=time(), size=20, note="..." }
function RAIDS:AddRaid(charKey, entry)
	if type(entry) ~= "table" then
		LOCAL_LOG("WARN", "AddRaid expects a table", type(entry))
		return false, nil
	end

	local c = self:EnsureCharacter(charKey)
	if not c then return false, nil end

	local raids = c.RAIDS
	local id = tostring(entry.id or (entry.time or now() or 0) .. "-" .. (#raids + 1))

	entry.id = id
	raids[#raids + 1] = entry

	LOCAL_LOG("INFO", "Raid entry added", charKey, id)
	return true, id
end

-- Finds a raid entry by id and returns it (or nil)
function RAIDS:FindRaid(charKey, id)
	if not id then return nil end
	local raids = self:GetRaids(charKey)
	if not raids then return nil end

	for i = 1, #raids do
		local e = raids[i]
		if e and e.id == id then
			return e, i
		end
	end

	return nil
end

-- Removes a raid entry by id. Returns ok
function RAIDS:RemoveRaid(charKey, id)
	local raids = self:GetRaids(charKey)
	if not raids then return false end

	for i = 1, #raids do
		local e = raids[i]
		if e and e.id == id then
			table.remove(raids, i)
			LOCAL_LOG("INFO", "Raid entry removed", charKey, id)
			return true
		end
	end

	return false
end

-- Clears RAIDS for the character
function RAIDS:ClearRaids(charKey)
	local c = self:EnsureCharacter(charKey)
	if not c then return false end

	c.RAIDS = {}
	LOCAL_LOG("INFO", "RAIDS cleared", charKey)
	return true
end
