-- ============================================================================
--	GMS/GMS.lua
--	GMS Core Entry (AceAddon)
-- ============================================================================

local ADDON_NAME = ...
local _G = _G

-- ###########################################################################
-- #	METADATA (required)
-- ###########################################################################

local METADATA = {
	TYPE         = "CORE",
	INTERN_NAME  = "GMS_CORE",
	SHORT_NAME   = "CORE",
	DISPLAY_NAME = "GMS Core",
	VERSION      = "1.0.4",
}

-- ---------------------------------------------------------------------------
--	Guards
-- ---------------------------------------------------------------------------

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

-- ---------------------------------------------------------------------------
--	Ace Mixins (optional)
-- ---------------------------------------------------------------------------

local AceConsole    = LibStub("AceConsole-3.0", true)
local AceEvent      = LibStub("AceEvent-3.0", true)
local AceTimer      = LibStub("AceTimer-3.0", true)
local AceComm       = LibStub("AceComm-3.0", true)
local AceSerializer = LibStub("AceSerializer-3.0", true)
local AceHook       = LibStub("AceHook-3.0", true)
local AceBucket     = LibStub("AceBucket-3.0", true)
local AceDB         = LibStub("AceDB-3.0", true)

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G               = _G
local GetTime          = GetTime
local C_AddOns         = C_AddOns
local GetAddOnMetadata = GetAddOnMetadata
---@diagnostic enable: undefined-global

local Unpack = (table and table.unpack) or unpack

-- ---------------------------------------------------------------------------
--	GMS AceAddon erstellen oder aus Registry holen
-- ---------------------------------------------------------------------------

local GMS = AceAddon:GetAddon("GMS", true)

if not GMS then
	local mixins = {}
	if AceConsole then mixins[#mixins + 1] = "AceConsole-3.0" end
	if AceEvent then mixins[#mixins + 1] = "AceEvent-3.0" end
	if AceTimer then mixins[#mixins + 1] = "AceTimer-3.0" end
	if AceComm then mixins[#mixins + 1] = "AceComm-3.0" end
	if AceSerializer then mixins[#mixins + 1] = "AceSerializer-3.0" end
	if AceHook then mixins[#mixins + 1] = "AceHook-3.0" end
	if AceBucket then mixins[#mixins + 1] = "AceBucket-3.0" end

	GMS = AceAddon:NewAddon("GMS", Unpack(mixins))
end

-- ---------------------------------------------------------------------------
--	Global Export (für /run & Debugging)
-- ---------------------------------------------------------------------------

---@diagnostic disable-next-line: inject-field
_G.GMS = GMS

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
		type   = tostring(METADATA.TYPE or "UNKNOWN"),
		source = tostring(METADATA.SHORT_NAME or "UNKNOWN"),
		msg    = tostring(msg or ""),
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
		GMS._LOG_NOTIFY(entry, idx)
	end
end

-- ###########################################################################
-- #	META / CONSTANTS
-- ###########################################################################

GMS.ADDON_NAME          = ADDON_NAME
GMS.INTERNAL_ADDON_NAME = tostring(ADDON_NAME or "GMS")
GMS.CHAT_PREFIX         = "|cff03A9F4[GMS]|r"
GMS.VERSION             = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or
	(GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or METADATA.VERSION

-- ###########################################################################
-- #	CHAT OUTPUT
-- ###########################################################################

function GMS:Print(msg)
	if msg == nil then return end
	print(("%s  %s"):format(self.CHAT_PREFIX, tostring(msg)))
end

function GMS:Printf(fmt, ...)
	if fmt == nil then return end
	local ok, rendered = pcall(string.format, tostring(fmt), ...)
	self:Print(ok and rendered or fmt)
end

-- ###########################################################################
-- #	DB
-- ###########################################################################

GMS.DEFAULTS = GMS.DEFAULTS or {
	profile = { debug = false },
	global  = { version = 1 },
}

function GMS:InitializeDatabaseIfAvailable(force)
	if not AceDB then
		LOCAL_LOG("WARN", "AceDB-3.0 not available")
		return false
	end

	if self.db and not force then
		return true
	end

	if type(self.InitializeStandardDatabases) == "function" then
		local ok, res = pcall(self.InitializeStandardDatabases, self, force)
		if ok and res then
			LOCAL_LOG("INFO", "InitializeStandardDatabases used")
			return true
		end
	end

	self.db = AceDB:New("GMS_DB", self.DEFAULTS, true)
	LOCAL_LOG("INFO", "AceDB initialized (fallback)")
	return true
end

-- ###########################################################################
-- #	LIFECYCLE
-- ###########################################################################

function GMS:OnInitialize()
	self:InitializeDatabaseIfAvailable(false)
	LOCAL_LOG("INFO", "OnInitialize")

	-- Register Core options
	if type(self.RegisterModuleOptions) == "function" then
		self:RegisterModuleOptions("CORE", {
			debug = { type = "toggle", name = "Debug-Modus", default = false },
		}, "PROFILE")
	end
end

function GMS:OnEnable()
	LOCAL_LOG("INFO", "OnEnable")

	if not self._startupHintShown then
		self._startupHintShown = true

		if type(self.ChatLink_Define) == "function" and type(self.ChatLink_OnClick) == "function" then
			self:ChatLink_Define("CMD_GMS", {
				title = "|cff03A9F4GMS: Hauptfenster|r",
				label = "/gms",
				hint = "/gms",
			})
			self:ChatLink_Define("CMD_HELP", {
				title = "|cff03A9F4GMS: Hilfe|r",
				label = "/gms ?",
				hint = "/gms ?",
			})

			self:ChatLink_OnClick("CMD_GMS", function()
				if type(self.SlashCommand) == "function" then self:SlashCommand("") end
			end)
			self:ChatLink_OnClick("CMD_HELP", function()
				if type(self.SlashCommand) == "function" then self:SlashCommand("?") end
			end)
		end

		local gmsCmd = "/gms"
		local helpCmd = "/gms ?"
		if type(self.ChatLink_Build) == "function" then
			gmsCmd = self:ChatLink_Build("CMD_GMS", "/gms", "GMS Hauptfenster")
			helpCmd = self:ChatLink_Build("CMD_HELP", "/gms ?", "GMS Hilfe")
		end

		self:Print(self:T("CORE_STARTUP_LOADED", tostring(self.VERSION or "?.?.?")))
		self:Print(self:T("CORE_STARTUP_HINT", gmsCmd, helpCmd))
	end
end

function GMS:OnDisable()
	LOCAL_LOG("INFO", "OnDisable")
end

LOCAL_LOG("INFO", "Core file loaded")
