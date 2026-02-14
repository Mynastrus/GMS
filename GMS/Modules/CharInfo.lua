-- ============================================================================
--	GMS/Modules/CharInfo.lua
--	CharInfo MODULE (Ace)
--	- Zugriff auf GMS Ã¼ber AceAddon Registry
--	- UI-Page + RightDock Icon
--	- Zeigt Player-Snapshot + ctx (optional) + Auswahl-Buttons
-- ============================================================================

local _G = _G

-- ###########################################################################
-- #	METADATA (required)
-- ###########################################################################

local METADATA = {
	TYPE         = "MOD",
	INTERN_NAME  = "CHARINFO",
	SHORT_NAME   = "CharInfo",
	DISPLAY_NAME = "Charakterinformationen",
	VERSION      = "1.0.7",
}

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G                         = _G
local GetTime                    = GetTime
local time                       = time
local UnitFullName               = UnitFullName
local UnitClass                  = UnitClass
local UnitRace                   = UnitRace
local UnitLevel                  = UnitLevel
local GetGuildInfo               = GetGuildInfo
local GetSpecialization          = GetSpecialization
local GetSpecializationInfo      = GetSpecializationInfo
local GetAverageItemLevel        = GetAverageItemLevel
local UnitGUID                   = UnitGUID
local UnitExists                 = UnitExists
local UnitIsPlayer               = UnitIsPlayer
local C_Timer                    = C_Timer
local GameFontNormalSmallOutline = GameFontNormalSmallOutline
---@diagnostic enable: undefined-global

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

-- ###########################################################################
-- #	LOG BUFFER + LOCAL_LOG (required)
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		timestamp = time and time() or 0,
		level     = tostring(level or "INFO"),
		type      = METADATA.TYPE,
		source    = METADATA.SHORT_NAME,
		message   = tostring(msg or ""),
		args      = { ... },
	}

	local buffer = GMS._LOG_BUFFER
	local idx = #buffer + 1
	buffer[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		GMS._LOG_NOTIFY(entry, idx)
	end
end

-- ###########################################################################
-- #	MODULE
-- ###########################################################################

local MODULE_NAME = METADATA.INTERN_NAME
local DISPLAY_NAME = METADATA.DISPLAY_NAME

local CHARINFO = GMS:GetModule(MODULE_NAME, true)
if not CHARINFO then
	CHARINFO = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
end

-- Registration
if GMS and type(GMS.RegisterModule) == "function" then
	GMS:RegisterModule(CHARINFO, METADATA)
end

GMS[MODULE_NAME] = CHARINFO

CHARINFO._pageRegistered = CHARINFO._pageRegistered or false
CHARINFO._dockRegistered = CHARINFO._dockRegistered or false
CHARINFO._integrated     = CHARINFO._integrated or false
CHARINFO._ticker         = CHARINFO._ticker or nil

---@class GMSTickerHandle
---@field Cancel fun(self: GMSTickerHandle)

-- DB for character-specific options (migrated to new API)
CHARINFO._options = CHARINFO._options or nil

local OPTIONS_DEFAULTS = {
	autoLog = true, -- Auto-log character on login
	lastUpdate = 0,
}

-- Icon: nimm einen, der bei dir existiert (du kannst ihn per /run testen)
local ICON = "Interface\\Icons\\INV_Misc_Head_Human_01"

-- ###########################################################################
-- #	HELPERS (style aligned)
-- ###########################################################################

local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, err = pcall(fn, ...)
	if not ok then
		LOCAL_LOG("ERROR", "CharInfo error: %s", tostring(err))
		if type(GMS.Print) == "function" then
			GMS:Print("CharInfo Fehler: " .. tostring(err))
		end
	end
	return ok
end

local function UIRef()
	return (GMS and (GMS.UI or GMS:GetModule("UI", true))) or nil
end

local function GetNavContext(consume)
	local ui = UIRef()
	if ui and type(ui.GetNavigationContext) == "function" then
		return ui:GetNavigationContext(consume == true)
	end
	return nil
end

local function SetNavContext(ctx)
	local ui = UIRef()
	if ui and type(ui.SetNavigationContext) == "function" then
		ui:SetNavigationContext(ctx)
		return true
	end
	return false
end

local function OpenSelf()
	local ui = UIRef()
	if ui and type(ui.Open) == "function" then
		ui:Open("CHARINFO")
		return true
	end
	return false
end

local function FormatNameRealm(name, realm)
	name = tostring(name or "")
	realm = tostring(realm or "")
	if name == "" then return "-" end
	if realm ~= "" then
		return name .. "-" .. realm
	end
	return name
end

local function GetPlayerSnapshot()
	local name, realm = UnitFullName("player")
	local className = UnitClass("player") -- localized
	local raceName = UnitRace("player") -- localized
	local level = UnitLevel("player")

	local guildName = GetGuildInfo and GetGuildInfo("player") or nil

	local specName = "-"
	if type(GetSpecialization) == "function" and type(GetSpecializationInfo) == "function" then
		local specIndex = GetSpecialization()
		if specIndex then
			local _, sName = GetSpecializationInfo(specIndex)
			if sName and sName ~= "" then specName = sName end
		end
	end

	local ilvlEquipped = nil
	local ilvlOverall = nil
	if type(GetAverageItemLevel) == "function" then
		local overall, equipped = GetAverageItemLevel()
		ilvlOverall = overall
		ilvlEquipped = equipped
	end

	return {
		name         = name,
		realm        = realm,
		name_full    = FormatNameRealm(name, realm),
		class        = className or "-",
		spec         = specName,
		race         = raceName or "-",
		level        = level or "-",
		guild        = guildName or "-",
		ilvl         = (ilvlEquipped and string.format("%.1f", ilvlEquipped)) or "-",
		ilvl_overall = (ilvlOverall and string.format("%.1f", ilvlOverall)) or "-",
		guid         = (UnitGUID and UnitGUID("player")) or nil,
	}
end

local function GetTargetSnapshot()
	if not (UnitExists and UnitExists("target")) then return nil end
	if not (UnitIsPlayer and UnitIsPlayer("target")) then return nil end

	local name, realm = UnitFullName("target")
	local className = UnitClass("target")
	local raceName = UnitRace("target")
	local level = UnitLevel("target")
	local guid = (UnitGUID and UnitGUID("target")) or nil

	-- Spec / ilvl fÃ¼r target sind ohne Inspect nicht zuverlÃ¤ssig -> bewusst "-"
	return {
		name         = name,
		realm        = realm,
		name_full    = FormatNameRealm(name, realm),
		class        = className or "-",
		spec         = "-",
		race         = raceName or "-",
		level        = level or "-",
		guild        = "-",
		ilvl         = "-",
		ilvl_overall = "-",
		guid         = guid,
	}
end

local function RenderBlock(titleText, lines)
	local out = {}
	out[#out + 1] = "|cff03A9F4" .. tostring(titleText or "") .. "|r"
	for _, l in ipairs(lines or {}) do
		out[#out + 1] = tostring(l)
	end
	return table.concat(out, "\n")
end

local function AddInfoLine(parent, key, value)
	if not parent or type(parent.AddChild) ~= "function" then return end
	local lbl = AceGUI:Create("Label")
	lbl:SetFullWidth(true)
	lbl:SetText(string.format("|cff9d9d9d%s:|r |cffffffff%s|r", tostring(key or "-"), tostring(value or "-")))
	if lbl.label then
		lbl.label:SetFontObject(GameFontNormalSmallOutline)
	end
	parent:AddChild(lbl)
end

local function BuildSnapshotCard(parent, titleText, snap)
	if not parent or type(parent.AddChild) ~= "function" then return end

	local box = AceGUI:Create("InlineGroup")
	box:SetTitle(tostring(titleText or "Info"))
	box:SetFullWidth(true)
	box:SetLayout("List")
	parent:AddChild(box)

	if type(snap) ~= "table" then
		AddInfoLine(box, "Status", "Keine Daten")
		return
	end

	AddInfoLine(box, "Name", snap.name_full or "-")
	AddInfoLine(box, "Level", snap.level or "-")
	AddInfoLine(box, "Rasse", snap.race or "-")
	AddInfoLine(box, "Klasse", snap.class or "-")
	AddInfoLine(box, "Spezialisierung", snap.spec or "-")
	AddInfoLine(box, "Itemlevel", string.format("%s (overall %s)", tostring(snap.ilvl or "-"), tostring(snap.ilvl_overall or "-")))
	AddInfoLine(box, "Gilde", snap.guild or "-")
	AddInfoLine(box, "GUID", snap.guid or "-")
end

-- ###########################################################################
-- #	UI PAGE
-- ###########################################################################

function CHARINFO:TryRegisterPage()
	if self._pageRegistered then return true end

	local ui = UIRef()
	if not ui or type(ui.RegisterPage) ~= "function" then
		return false
	end

	ui:RegisterPage("CHARINFO", 60, DISPLAY_NAME, function(root, id, isCached)
		local ui2 = UIRef()
		local ctx = GetNavContext(true) or nil
		local player = GetPlayerSnapshot()

		local ctxName = ctx and ctx.name_full or nil
		local ctxGuid = ctx and ctx.guid or nil
		local ctxFrom = ctx and (ctx.from or ctx.source) or nil

		if ui2 and type(ui2.Header_BuildIconText) == "function" then
			ui2:Header_BuildIconText({
				icon = ICON,
				text = "|cff03A9F4" .. METADATA.DISPLAY_NAME .. "|r",
				subtext = ctxName and ("Context aktiv: |cffCCCCCC" .. tostring(ctxName) .. "|r") or "Kein Context gesetzt",
			})
		end
		if ui2 and type(ui2.SetStatusText) == "function" then
			ui2:SetStatusText(ctxName and "CHARINFO: ctx aktiv" or "CHARINFO: nur player")
		end

		if isCached then return end

		local wrapper = AceGUI:Create("SimpleGroup")
		wrapper:SetFullWidth(true)
		wrapper:SetFullHeight(true)
		wrapper:SetLayout("List")
		root:AddChild(wrapper)

		local actions = AceGUI:Create("InlineGroup")
		actions:SetTitle("Aktionen")
		actions:SetFullWidth(true)
		actions:SetLayout("Flow")
		wrapper:AddChild(actions)

		local btnSelf = AceGUI:Create("Button")
		btnSelf:SetText("Spieler selbst auswaehlen")
		btnSelf:SetWidth(190)
		btnSelf:SetCallback("OnClick", function()
			SetNavContext({
				from = "charinfo",
				name_full = player.name_full,
				guid = player.guid,
				unit = "player",
			})
			if ui2 and type(ui2.SetStatusText) == "function" then
				ui2:SetStatusText("CHARINFO: ctx = player gesetzt")
			end
			OpenSelf()
		end)
		actions:AddChild(btnSelf)

		local btnTarget = AceGUI:Create("Button")
		btnTarget:SetText("Target auswaehlen")
		btnTarget:SetWidth(160)
		btnTarget:SetCallback("OnClick", function()
			local t = GetTargetSnapshot()
			if not t then
				if ui2 and type(ui2.SetStatusText) == "function" then
					ui2:SetStatusText("CHARINFO: kein Spieler-Target")
				end
				return
			end
			SetNavContext({
				from = "charinfo",
				name_full = t.name_full,
				guid = t.guid,
				unit = "target",
			})
			if ui2 and type(ui2.SetStatusText) == "function" then
				ui2:SetStatusText("CHARINFO: ctx = target gesetzt")
			end
			OpenSelf()
		end)
		actions:AddChild(btnTarget)

		local btnClear = AceGUI:Create("Button")
		btnClear:SetText("Context loeschen")
		btnClear:SetWidth(145)
		btnClear:SetCallback("OnClick", function()
			SetNavContext(nil)
			if ui2 and type(ui2.SetStatusText) == "function" then
				ui2:SetStatusText("CHARINFO: ctx geloescht")
			end
			OpenSelf()
		end)
		actions:AddChild(btnClear)

		local btnRefresh = AceGUI:Create("Button")
		btnRefresh:SetText("Aktualisieren")
		btnRefresh:SetWidth(130)
		btnRefresh:SetCallback("OnClick", function()
			OpenSelf()
		end)
		actions:AddChild(btnRefresh)

		BuildSnapshotCard(wrapper, "Spieler", player)

		local ctxCard = AceGUI:Create("InlineGroup")
		ctxCard:SetTitle("Context")
		ctxCard:SetFullWidth(true)
		ctxCard:SetLayout("List")
		wrapper:AddChild(ctxCard)
		AddInfoLine(ctxCard, "Quelle", ctxFrom or "-")
		AddInfoLine(ctxCard, "Name", ctxName or "-")
		AddInfoLine(ctxCard, "GUID", ctxGuid or "-")

		local opts = (type(CHARINFO._options) == "table") and CHARINFO._options or nil
		local lastUpdate = (opts and tonumber(opts.lastUpdate)) or 0
		AddInfoLine(wrapper, "Letztes Update", (lastUpdate > 0 and tostring(lastUpdate) or "-"))
	end)

	self._pageRegistered = true
	return true
end
function CHARINFO:TryRegisterDockIcon()
	if self._dockRegistered then return true end

	local ui = UIRef()
	if not ui or type(ui.AddRightDockIconTop) ~= "function" then
		return false
	end

	ui:AddRightDockIconTop({
		id = "CHARINFO",
		order = 60,
		selectable = true,
		icon = ICON,
		tooltipTitle = DISPLAY_NAME,
		tooltipText = "Ã–ffnet die Charakter-Info",
		onClick = function()
			local u = UIRef()
			if u and type(u.Open) == "function" then
				u:Open("CHARINFO")
			end
		end,
	})

	self._dockRegistered = true
	return true
end

-- ###########################################################################
-- #	INTEGRATION / RETRY
-- ###########################################################################

function CHARINFO:TryIntegrateWithUIIfAvailable()
	if self._integrated then return true end

	local okPage = self:TryRegisterPage()
	local okDock = self:TryRegisterDockIcon()

	if okPage and okDock then
		self._integrated = true
		if self._ticker then
			local ticker = self._ticker
			---@cast ticker GMSTickerHandle
			pcall(function() ticker:Cancel() end)
		end
		self._ticker = nil
		LOCAL_LOG("INFO", "Integrated with UI")
		return true
	end
	return false
end

function CHARINFO:StartIntegrationTicker()
	if self._integrated then return end
	if self._ticker then return end
	if not C_Timer or type(C_Timer.NewTicker) ~= "function" then return end

	local tries = 0
	self._ticker = C_Timer.NewTicker(0.50, function()
		tries = tries + 1
		if CHARINFO:TryIntegrateWithUIIfAvailable() then return end
		if tries >= 30 then
			if CHARINFO._ticker then
				local ticker = CHARINFO._ticker
				---@cast ticker GMSTickerHandle
				pcall(function() ticker:Cancel() end)
			end
			CHARINFO._ticker = nil
			LOCAL_LOG("WARN", "UI not available (gave up retries)")
		end
	end)
end

-- ###########################################################################
-- #	ACE LIFECYCLE
-- ###########################################################################

function CHARINFO:InitializeOptions()
	-- Register character-specific options using new API
	if GMS and type(GMS.RegisterModuleOptions) == "function" then
		pcall(function()
			GMS:RegisterModuleOptions("CHARINFO", OPTIONS_DEFAULTS, "CHAR")
		end)
	end

	-- Retrieve options table
	if GMS and type(GMS.GetModuleOptions) == "function" then
		local ok, opts = pcall(GMS.GetModuleOptions, GMS, "CHARINFO")
		if ok and opts then
			self._options = opts
		end
	end

	-- Auto-log current player character
	local opts = (type(self._options) == "table") and self._options or nil
	if opts and opts.autoLog then
		local snap = GetPlayerSnapshot()
		if snap and snap.name_full then
			opts.lastUpdate = time and time() or 0
			LOCAL_LOG("INFO", "Character auto-logged: %s", tostring(snap.name_full))
		else
			LOCAL_LOG("WARN", "Character snapshot missing; not auto-logged")
		end
	else
		LOCAL_LOG("DEBUG", "CHARINFO options not available or auto-log disabled")
	end
end

function CHARINFO:OnEnable()
	-- Initialize character-specific options
	SafeCall(CHARINFO.InitializeOptions, CHARINFO)

	-- Ensure we attempt to initialize again when player fully logs in / enters world
	if type(self.RegisterEvent) == "function" then
		self:RegisterEvent("PLAYER_LOGIN", function()
			SafeCall(CHARINFO.InitializeOptions, CHARINFO)
		end)
		self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
			SafeCall(CHARINFO.InitializeOptions, CHARINFO)
		end)
	end

	self:TryIntegrateWithUIIfAvailable()
	self:StartIntegrationTicker()

	if type(self.RegisterEvent) == "function" then
		self:RegisterEvent("PLAYER_LOGIN", function()
			SafeCall(CHARINFO.TryIntegrateWithUIIfAvailable, CHARINFO)
		end)
	end

	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
end

function CHARINFO:OnDisable()
	if self._ticker then
		local ticker = self._ticker
		---@cast ticker GMSTickerHandle
		pcall(function() ticker:Cancel() end)
	end
	self._ticker = nil
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end

