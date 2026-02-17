-- ============================================================================
--	GMS/Core/Dashboard.lua
--	DASHBOARD EXTENSION
--	- Central landing page for GMS
--	- Monitors state of all Extensions and Modules
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G      = _G
local GetTime = GetTime
local C_Timer = C_Timer
---@diagnostic enable: undefined-global

-- ###########################################################################
-- #	METADATA
-- ###########################################################################

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "DASHBOARD",
	SHORT_NAME   = "Dashboard",
	DISPLAY_NAME = "Dashboard",
	VERSION      = "1.0.0",
}

-- ###########################################################################
-- #	LOG BUFFER + LOCAL LOGGER
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return type(GetTime) == "function" and GetTime() or nil
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

	local buf = GMS._LOG_BUFFER
	local idx = #buf + 1
	buf[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		pcall(GMS._LOG_NOTIFY, entry, idx)
	end
end

local function DT(key, fallback, ...)
	if type(GMS.T) == "function" then
		local ok, txt = pcall(GMS.T, GMS, key, ...)
		if ok and type(txt) == "string" and txt ~= "" and txt ~= key then
			return txt
		end
	end
	if select("#", ...) > 0 then
		return string.format(tostring(fallback or key), ...)
	end
	return tostring(fallback or key)
end
-- ###########################################################################
-- #	EXTENSION REGISTRATION
-- ###########################################################################

GMS:RegisterExtension({
	key = METADATA.INTERN_NAME,
	name = METADATA.SHORT_NAME,
	displayName = METADATA.DISPLAY_NAME,
	version = METADATA.VERSION,
	desc = "Addon Dashboard with Status Monitoring",
})

-- ###########################################################################
-- #	UI RENDERING
-- ###########################################################################

local function RenderDashboard(root, id, isCached)
	if not GMS.UI then return end

	-- Header (Always Rebuild)
	GMS.UI:Header_BuildDefault()
	GMS.UI:SetStatusText(DT("DASHBOARD_STATUS_LOADED", "DASHBOARD: system status loaded"))

	-- If cached, only update Header/Footer (done above) and return
	if isCached then return end

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	root:AddChild(scroll)

	-- Info Block
	local infoGroup = AceGUI:Create("InlineGroup")
	infoGroup:SetTitle(DT("DASHBOARD_INFO_TITLE", "General information"))
	infoGroup:SetFullWidth(true)
	infoGroup:SetLayout("Flow")
	scroll:AddChild(infoGroup)

	local guildInfoMod = (type(GMS.GetModule) == "function") and GMS:GetModule("GuildInfo", true) or nil
	local guild = (guildInfoMod and type(guildInfoMod.GetSnapshot) == "function")
		and guildInfoMod:GetSnapshot() or nil

	local guildText = DT("DASHBOARD_GUILD_INFO_MISSING", "No guild information available.")
	if type(guild) == "table" then
		if guild.inGuild then
			guildText = string.format(
				DT("DASHBOARD_GUILD_SUMMARY_FMT", "Guild: |cffffcc00%s|r\nRealm/Faction: |cffd7d7d7%s / %s|r\nRank: |cffd7d7d7%s (%s)|r\nMembers online: |cffd7d7d7%d/%d|r"),
				tostring(guild.name or "-"),
				tostring(guild.realm or "-"),
				tostring(guild.faction or "-"),
				tostring(guild.rankName or "-"),
				tostring(guild.rankIndex or "-"),
				tonumber(guild.memberOnline) or 0,
				tonumber(guild.memberCount) or 0
			)
		else
			guildText = DT("DASHBOARD_GUILD_NONE", "Currently not in a guild.")
		end
	end

	local lblInfo = AceGUI:Create("Label")
	lblInfo:SetFullWidth(true)
	lblInfo:SetText(string.format(
		DT("DASHBOARD_WELCOME_FMT", "Welcome to |cff03A9F4GMS - Guild Management System|r.\nVersion: |cffffcc00%s|r\n\n%s"),
		GMS.VERSION or "?.?.?",
		guildText
	))
	infoGroup:AddChild(lblInfo)

	local hint = AceGUI:Create("Label")
	hint:SetFullWidth(true)
	hint:SetText(DT("DASHBOARD_HINT_SETTINGS", "You can now find technical system status under: Settings -> Home page (Dashboard)."))
	scroll:AddChild(hint)
end

GMS.Dashboard = GMS.Dashboard or {}
GMS.Dashboard.Render = RenderDashboard

-- ###########################################################################
-- #	INITIALIZATION
-- ###########################################################################

local function Init()
	if not GMS.UI or type(GMS.UI.RegisterPage) ~= "function" then
		-- Retry later if UI is not yet available
		if C_Timer and C_Timer.After then
			C_Timer.After(0.5, Init)
		end
		return
	end

	GMS.UI:RegisterPage(METADATA.INTERN_NAME, 0, METADATA.DISPLAY_NAME, RenderDashboard)
	LOCAL_LOG("INFO", "DASHBOARD page registered")
end

Init()

-- ###########################################################################
-- #	READY
-- ###########################################################################

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)
LOCAL_LOG("INFO", "Dashboard logic loaded")
