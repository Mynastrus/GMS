-- ============================================================================
--	GMS/Core/Database.lua
--	Database EXTENSION
--	- Registers standard SavedVariables via AceDB-3.0
-- ============================================================================

local METADATA = {
	TYPE = "EXTENSION",
	INTERN_NAME = "DATABASE",
	SHORT_NAME = "DB",
	DISPLAY_NAME = "Database",
	VERSION = "1.0.1",
}

local _G = _G

-- ---------------------------------------------------------------------------
--	Guards
-- ---------------------------------------------------------------------------

local LibStub = LibStub
if not LibStub then return end

local AceDB = LibStub("AceDB-3.0", true)
if not AceDB then
	return
end

local AceAddon = LibStub("AceAddon-3.0", true)
local GMS = AceAddon and AceAddon:GetAddon("GMS", true) or nil
if not GMS then
	GMS = _G.GMS
end
if not GMS then return end

-- ###########################################################################
-- #	LOG BUFFER + LOCAL LOGGER
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return GetTime and GetTime() or nil
end

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time = now(),
		level = tostring(level or "INFO"),
		type = METADATA.TYPE,
		source = METADATA.SHORT_NAME,
		msg = tostring(msg or ""),
	}

	local n = select("#", ...)
	if n > 0 then
		entry.data = {}
		for i = 1, n do
			entry.data[i] = select(i, ...)
		end
	end

	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		pcall(GMS._LOG_NOTIFY, entry, idx)
	end
end

-- ###########################################################################
-- #	Extension REGISTRATION
-- ###########################################################################

if type(GMS.RegisterExtension) == "function" then
	GMS:RegisterExtension({
		key = METADATA.SHORT_NAME,
		name = METADATA.INTERN_NAME,
		displayName = METADATA.DISPLAY_NAME,
		version = METADATA.VERSION,
		desc = "AceDB-based SavedVariables and module namespaces",
	})
end

-- ###########################################################################
-- #	DEFAULTS
-- ###########################################################################

local DB_DEFAULTS = GMS.DEFAULTS or {
	profile = { debug = false },
	global = { version = 1 },
}

local LOGGING_DEFAULTS = {
	profile = {},
	global = { logs = {} },
}

-- ###########################################################################
-- #	STANDARD DATABASE INIT
-- ###########################################################################

function GMS:InitializeStandardDatabases(force)
	if not AceDB then
		LOCAL_LOG("WARN", "AceDB-3.0 not available")
		return false
	end

	if self.db and self.logging_db and not force then
		return true
	end

	self.db = self.db or AceDB:New("GMS_DB", DB_DEFAULTS, true)
	self.logging_db = self.logging_db or AceDB:New("GMS_Logging_DB", LOGGING_DEFAULTS, true)

	LOCAL_LOG("INFO", "Standard databases initialized")
	return true
end

-- Early init attempt (harmless if Core runs it again later)
pcall(function()
	if type(GMS.InitializeStandardDatabases) == "function" then
		GMS:InitializeStandardDatabases(false)
	end
end)

-- ###########################################################################
-- #	GMS.DB HELPER API
-- ###########################################################################

GMS.DB = GMS.DB or {}
GMS.DB._parent = GMS

function GMS.DB:RegisterModule(moduleName, defaults, optionsProvider)
	if not moduleName or not self._parent or not self._parent.db then
		return nil
	end

	local ok, ns = pcall(function()
		return self._parent.db:RegisterNamespace(moduleName, defaults)
	end)

	if ok and ns then
		self._modules = self._modules or {}
		self._modules[moduleName] = ns

		if type(optionsProvider) == "function" then
			pcall(optionsProvider)
		end

		LOCAL_LOG("DEBUG", "Registered module DB", moduleName)
		return ns
	end

	return nil
end

function GMS.DB:GetModuleDB(moduleName)
	if not moduleName then return nil end
	self._modules = self._modules or {}

	if self._modules[moduleName] then
		return self._modules[moduleName]
	end

	if self._parent and self._parent.db then
		local ok, ns = pcall(function()
			return self._parent.db:GetNamespace(moduleName, true)
		end)
		if ok and ns then
			self._modules[moduleName] = ns
			return ns
		end
	end

	return nil
end

-- ###########################################################################
-- #	READY
-- ###########################################################################

if type(GMS.SetReady) == "function" then
	GMS:SetReady("EXT:DB")
end

LOCAL_LOG("INFO", "Database extension loaded")
