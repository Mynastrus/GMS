-- ============================================================================
--	GMS/Core/SlashCommands.lua
--	SlashCommands EXTENSION (no GMS:NewModule)
-- ============================================================================

-- ###########################################################################
-- #	METADATA (required)
-- ###########################################################################

local METADATA = {
	TYPE = "EXT",
	INTERN_NAME = "SLASH",
	SHORT_NAME = "SLASH",
	DISPLAY_NAME = "Slash Commands",
	VERSION = "1.0.4",
}

-- ---------------------------------------------------------------------------
--	Guards
-- ---------------------------------------------------------------------------

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G       = _G
local GetTime  = GetTime
local type     = type
local tostring = tostring
local select   = select
local pairs    = pairs
local ipairs   = ipairs
local pcall    = pcall
local table    = table
local ReloadUI = ReloadUI
---@diagnostic enable: undefined-global

-- ###########################################################################
-- #	LOG BUFFER + LOCAL LOGGER (required)
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return GetTime and GetTime() or nil
end

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time   = now(),
		level  = tostring(level or "INFO"),
		type   = tostring(METADATA.TYPE),
		source = tostring(METADATA.SHORT_NAME),
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
-- #	EXTENSION REGISTRATION
-- ###########################################################################

if type(GMS.RegisterExtension) == "function" then
	GMS:RegisterExtension({
		key = METADATA.INTERN_NAME,
		name = METADATA.INTERN_NAME,
		displayName = METADATA.DISPLAY_NAME,
		version = METADATA.VERSION,
		desc = "/gms command and subcommand registry",
	})
end

-- Requires AceConsole mixin
if type(GMS.RegisterChatCommand) ~= "function" then
	LOCAL_LOG("WARN", "AceConsole not available; slash commands disabled")
	return
end

-- ###########################################################################
-- #	META / STATE
-- ###########################################################################

GMS.SlashCommands = GMS.SlashCommands or {}
local SlashCommands = GMS.SlashCommands

local EXT_NAME = METADATA.INTERN_NAME
local DISPLAY_NAME = "Chateingabe"

SlashCommands.SUBCOMMAND_REGISTRY = SlashCommands.SUBCOMMAND_REGISTRY or {}
SlashCommands.PRIMARY_COMMAND = SlashCommands.PRIMARY_COMMAND or "gms"

-- ###########################################################################
-- #	INTERNAL HELPERS
-- ###########################################################################

local function LOWER(s) return string.lower(tostring(s or "")) end

local function TRIM(s)
	return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizeSubCommandKey(rawKey)
	return LOWER(TRIM(rawKey))
end

local function ParseGmsSlashInput(input)
	local full = TRIM(input)
	if full == "" then return "", "", "" end
	local cmd, rest = full:match("^(%S+)%s*(.*)$")
	return tostring(cmd or ""), tostring(rest or ""), full
end

local function IsStringArray(v)
	if type(v) ~= "table" then return false end
	for _, x in ipairs(v) do
		if type(x) ~= "string" then return false end
	end
	return true
end

local function FindSubCommandEntry(registry, subCommand)
	local norm = NormalizeSubCommandKey(subCommand)
	if norm == "" then return end

	if registry[norm] then return registry[norm] end

	for _, entry in pairs(registry) do
		local alias = entry.alias
		if type(alias) == "string" then
			if NormalizeSubCommandKey(alias) == norm then
				return entry
			end
		elseif IsStringArray(alias) then
			for _, a in ipairs(alias) do
				if NormalizeSubCommandKey(a) == norm then
					return entry
				end
			end
		end
	end
end

local function PrintGmsHelp(registry, header)
	LOCAL_LOG("INFO", "Print help", header)

	if type(GMS.Print) == "function" then
		if header and header ~= "" then
			GMS:Print(header)
		end
		GMS:Print("Usage: /gms <subcommand> [args]")
		GMS:Print("Example: /gms help")
	end

	local keys = {}
	for k in pairs(registry) do keys[#keys + 1] = k end
	table.sort(keys)

	if #keys == 0 then
		if type(GMS.Print) == "function" then
			GMS:Print("No subcommands registered.")
		end
		return
	end

	for _, key in ipairs(keys) do
		local e = registry[key]
		if e.help and e.help ~= "" then
			if type(GMS.Printf) == "function" then
				GMS:Printf(" - %s: %s", key, e.help)
			else
				GMS:Print((" - %s: %s"):format(key, e.help))
			end
		else
			GMS:Print(" - " .. key)
		end
	end
end

-- ###########################################################################
-- #	DISPATCHER
-- ###########################################################################

local function HandleGmsSlashCommandInput(input)
	local sub, args = ParseGmsSlashInput(input)

	if sub == "" then
		if type(GMS.UI_Open) == "function" then
			local ok = pcall(function() return GMS:UI_Open(nil) end)
			if ok then return end
		end
		local uiEntry = FindSubCommandEntry(SlashCommands.SUBCOMMAND_REGISTRY, "ui")
		if uiEntry and type(uiEntry.handlerFn) == "function" then
			local ok, err = pcall(uiEntry.handlerFn, "")
			if not ok then
				LOCAL_LOG("ERROR", "Default /gms UI handler error", err)
			end
			return
		end
		return HandleGmsSlashCommandInput("?")
	end

	if sub == "help" or sub == "?" then
		return PrintGmsHelp(SlashCommands.SUBCOMMAND_REGISTRY, DISPLAY_NAME)
	end

	local entry = FindSubCommandEntry(SlashCommands.SUBCOMMAND_REGISTRY, sub)
	if not entry or type(entry.handlerFn) ~= "function" then
		return PrintGmsHelp(SlashCommands.SUBCOMMAND_REGISTRY, "Unknown subcommand: " .. sub)
	end

	local ok, err = pcall(entry.handlerFn, args)
	if not ok then
		LOCAL_LOG("ERROR", "Subcommand handler error", err)
	end
end

-- ###########################################################################
-- #	PUBLIC API
-- ###########################################################################

function GMS:Slash_RegisterSubCommand(key, handlerFn, opts)
	local norm = NormalizeSubCommandKey(key)
	if norm == "" or type(handlerFn) ~= "function" then
		LOCAL_LOG("ERROR", "Invalid subcommand registration", key)
		return false
	end

	opts = opts or {}
	SlashCommands.SUBCOMMAND_REGISTRY[norm] = {
		key = norm,
		handlerFn = handlerFn,
		help = tostring(opts.help or ""),
		alias = opts.alias,
		owner = tostring(opts.owner or ""),
	}

	LOCAL_LOG("DEBUG", "Registered subcommand", norm)
	return true
end

function GMS:Slash_UnregisterSubCommand(key)
	local norm = NormalizeSubCommandKey(key)
	if SlashCommands.SUBCOMMAND_REGISTRY[norm] then
		SlashCommands.SUBCOMMAND_REGISTRY[norm] = nil
		LOCAL_LOG("DEBUG", "Unregistered subcommand", norm)
		return true
	end
	return false
end

function GMS:Slash_PrintHelp()
	PrintGmsHelp(SlashCommands.SUBCOMMAND_REGISTRY, DISPLAY_NAME)
end

function GMS:SlashCommand(input)
	HandleGmsSlashCommandInput(input)
end

-- ###########################################################################
-- #	BOOTSTRAP
-- ###########################################################################

if not SlashCommands._registered then
	SlashCommands._registered = true
	GMS:RegisterChatCommand(SlashCommands.PRIMARY_COMMAND, HandleGmsSlashCommandInput)
end

if not SlashCommands._defaultsLoaded then
	SlashCommands._defaultsLoaded = true

	GMS:Slash_RegisterSubCommand("reload", function()
		if ReloadUI then ReloadUI() end
	end, {
		help = "Lädt die UI neu.",
		alias = { "rl" },
		owner = EXT_NAME,
	})
end

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)

LOCAL_LOG("INFO", "SlashCommands extension loaded")
