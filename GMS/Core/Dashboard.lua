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
-- #	HELPERS
-- ###########################################################################

local function GetStatusColor(ready, enabled)
	if ready then
		return "|cff00ff00READY|r"
	elseif enabled then
		return "|cffffff00ENABLED (Waiting for Ready)|r"
	else
		return "|cffff0000INACTIVE|r"
	end
end

-- ###########################################################################
-- #	UI RENDERING
-- ###########################################################################

local function RenderDashboard(root, id, isCached)
	if not GMS.UI then return end

	-- Header (Always Rebuild)
	GMS.UI:Header_BuildDefault()
	GMS.UI:SetStatusText("DASHBOARD: Systemstatus geladen")

	-- If cached, only update Header/Footer (done above) and return
	if isCached then return end

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	root:AddChild(scroll)

	-- Info Block
	local infoGroup = AceGUI:Create("InlineGroup")
	infoGroup:SetTitle("Allgemeine Informationen")
	infoGroup:SetFullWidth(true)
	infoGroup:SetLayout("Flow")
	scroll:AddChild(infoGroup)

	local lblInfo = AceGUI:Create("Label")
	lblInfo:SetFullWidth(true)
	lblInfo:SetText(string.format(
		"Willkommen bei |cff03A9F4GMS – Guild Management System|r.\n" ..
		"Version: |cffffcc00%s|r\n\n" ..
		"Dieses Dashboard gibt eine Übersicht über alle aktiven Komponenten des Systems.",
		GMS.VERSION or "?.?.?"
	))
	infoGroup:AddChild(lblInfo)

	-- Extensions Block
	local extGroup = AceGUI:Create("InlineGroup")
	extGroup:SetTitle("Extensions (Kernsystem)")
	extGroup:SetFullWidth(true)
	extGroup:SetLayout("Flow")
	scroll:AddChild(extGroup)

	if GMS.REGISTRY and GMS.REGISTRY.EXT then
		local keys = {}
		for k in pairs(GMS.REGISTRY.EXT) do table.insert(keys, k) end
		table.sort(keys)

		for _, k in ipairs(keys) do
			local e = GMS.REGISTRY.EXT[k]
			local row = AceGUI:Create("SimpleGroup")
			row:SetFullWidth(true)
			row:SetLayout("Flow")

			local lblName = AceGUI:Create("Label")
			lblName:SetText("- |cff03A9F4" .. (e.displayName or e.key) .. "|r")
			lblName:SetWidth(200)

			local lblVer = AceGUI:Create("Label")
			lblVer:SetText("[v" .. (e.version or "1.0.0") .. "]")
			lblVer:SetWidth(80)

			local status = GetStatusColor(e.state and e.state.READY)
			local lblStatus = AceGUI:Create("Label")
			lblStatus:SetText(status)
			lblStatus:SetWidth(100)

			row:AddChild(lblName)
			row:AddChild(lblVer)
			row:AddChild(lblStatus)
			extGroup:AddChild(row)
		end
	end

	-- Modules Block
	local modGroup = AceGUI:Create("InlineGroup")
	modGroup:SetTitle("Module (Features)")
	modGroup:SetFullWidth(true)
	modGroup:SetLayout("Flow")
	scroll:AddChild(modGroup)

	if GMS.REGISTRY and GMS.REGISTRY.MOD then
		local keys = {}
		for k in pairs(GMS.REGISTRY.MOD) do table.insert(keys, k) end
		table.sort(keys)

		for _, k in ipairs(keys) do
			local m = GMS.REGISTRY.MOD[k]
			local row = AceGUI:Create("SimpleGroup")
			row:SetFullWidth(true)
			row:SetLayout("Flow")

			local lblName = AceGUI:Create("Label")
			lblName:SetText("- |cffffcc00" .. (m.displayName or m.key) .. "|r")
			lblName:SetWidth(200)

			local lblVer = AceGUI:Create("Label")
			lblVer:SetText("[v" .. (m.version or "1.0.0") .. "]")
			lblVer:SetWidth(80)

			local status = GetStatusColor(m.state and m.state.READY, m.state and m.state.ENABLED)
			local lblStatus = AceGUI:Create("Label")
			lblStatus:SetText(status)
			lblStatus:SetWidth(100)

			row:AddChild(lblName)
			row:AddChild(lblVer)
			row:AddChild(lblStatus)
			modGroup:AddChild(row)
		end
	end

	-- Refresh Button
	local btnRefresh = AceGUI:Create("Button")
	btnRefresh:SetText("Status aktualisieren")
	btnRefresh:SetWidth(180)
	btnRefresh:SetCallback("OnClick", function()
		GMS.UI:Navigate(METADATA.INTERN_NAME)
	end)
	scroll:AddChild(btnRefresh)
end

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
