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

local function RenderDashboard(root)
	if not GMS.UI then return end

	-- Header
	GMS.UI:Header_BuildDefault()
	GMS.UI:SetStatusText("DASHBOARD: Systemstatus geladen")

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
		"Willkommen bei |cff03A9F4GMS – Guild Management Suite|r.\n" ..
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
			local lbl = AceGUI:Create("Label")
			lbl:SetFullWidth(true)
			local status = GetStatusColor(e.state and e.state.READY)
			lbl:SetText(string.format("- |cff03A9F4%s|r [v%s]: %s", e.displayName or e.key, e.version or "1.0.0", status))
			extGroup:AddChild(lbl)
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
			local lbl = AceGUI:Create("Label")
			lbl:SetFullWidth(true)
			local status = GetStatusColor(m.state and m.state.READY, m.state and m.state.ENABLED)
			lbl:SetText(string.format("- |cffffcc00%s|r [v%s]: %s", m.displayName or m.key, m.version or "1.0.0", status))
			modGroup:AddChild(lbl)
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
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(0.5, Init)
		end
		return
	end

	GMS.UI:RegisterPage(METADATA.INTERN_NAME, 0, "Dashboard", RenderDashboard)
	LOCAL_LOG("INFO", "DASHBOARD page registered")
end

Init()

-- ###########################################################################
-- #	READY
-- ###########################################################################

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)
LOCAL_LOG("INFO", "Dashboard logic loaded")
