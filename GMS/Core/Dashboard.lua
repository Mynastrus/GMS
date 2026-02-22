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
	VERSION      = "1.0.2",
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

local function BuildRegistryRows(kind)
	local rows = {}
	local registry = type(GMS.REGISTRY) == "table" and GMS.REGISTRY or nil
	local source = registry and registry[kind] or nil
	if type(source) ~= "table" then
		return rows
	end
	for key, entry in pairs(source) do
		if type(entry) == "table" then
			local display = ""
			if type(GMS.ResolveRegistryDisplayName) == "function" then
				display = tostring(GMS:ResolveRegistryDisplayName(entry, entry.displayName or entry.name or key))
			else
				display = tostring(entry.displayName or entry.name or key or "")
			end
			rows[#rows + 1] = {
				name = display ~= "" and display or tostring(key or "-"),
				version = tostring(entry.version or "-"),
				ready = type(GMS.IsReady) == "function" and GMS:IsReady(tostring(entry.readyKey or "")) == true,
			}
		end
	end
	table.sort(rows, function(a, b)
		return tostring(a.name or "") < tostring(b.name or "")
	end)
	return rows
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
	GMS.UI:SetStatusText("")

	-- If cached, only update Header/Footer (done above) and return
	if isCached then return end

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	root:AddChild(scroll)

	-- Info Block
	local infoGroup = AceGUI:Create("InlineGroup")
	infoGroup:SetTitle(DT("DASHBOARD_INFO_TITLE", "General information"))
	infoGroup:SetFullWidth(true)
	infoGroup:SetLayout("List")
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

	local extRows = BuildRegistryRows("EXT")
	local modRows = BuildRegistryRows("MOD")
	local extReady = 0
	local modReady = 0
	for i = 1, #extRows do
		if extRows[i].ready then extReady = extReady + 1 end
	end
	for i = 1, #modRows do
		if modRows[i].ready then modReady = modReady + 1 end
	end

	local summary = AceGUI:Create("InlineGroup")
	summary:SetTitle(DT("DASHBOARD_STATUS_TITLE", "System status"))
	summary:SetFullWidth(true)
	summary:SetLayout("List")
	scroll:AddChild(summary)

	local summaryLabel = AceGUI:Create("Label")
	summaryLabel:SetFullWidth(true)
	summaryLabel:SetText(string.format(
		DT("DASHBOARD_STATUS_SUMMARY_FMT", "Extensions ready: |cff4caf50%d|r / %d\nModules ready: |cff4caf50%d|r / %d"),
		extReady, #extRows, modReady, #modRows
	))
	summary:AddChild(summaryLabel)

	local function AddStatusList(titleKey, titleFallback, rows)
		local group = AceGUI:Create("InlineGroup")
		group:SetTitle(DT(titleKey, titleFallback))
		group:SetFullWidth(true)
		group:SetLayout("List")
		scroll:AddChild(group)

		if #rows <= 0 then
			local empty = AceGUI:Create("Label")
			empty:SetFullWidth(true)
			empty:SetText("|cff9d9d9d" .. DT("DASHBOARD_STATUS_EMPTY", "No registry data available.") .. "|r")
			group:AddChild(empty)
			return
		end

		for i = 1, #rows do
			local row = rows[i]
			local item = AceGUI:Create("Label")
			item:SetFullWidth(true)
			local color = row.ready and "ff4caf50" or "ffff5c5c"
			local state = row.ready and DT("DASHBOARD_READY", "READY") or DT("DASHBOARD_NOT_READY", "NOT READY")
			item:SetText(string.format("|c%s%s|r  |cffd7d7d7%s|r  |cff9d9d9d(%s)|r", color, state, tostring(row.name or "-"), tostring(row.version or "-")))
			group:AddChild(item)
		end
	end

	AddStatusList("DASHBOARD_EXTENSIONS_TITLE", "Extensions", extRows)
	AddStatusList("DASHBOARD_MODULES_TITLE", "Modules", modRows)

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
