-- ============================================================================
--	GMS/Core/Settings.lua
--	SETTINGS EXTENSION
--	- Global Settings & Module Options UI
--	- Integrates with GMS.UI (Registers "SETTINGS" page)
--	- Integrates with SlashCommands (/gms options, /gms settings, /gms o)
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

local AceGUI = LibStub("AceGUI-3.0", true)

-- ###########################################################################
-- #	METADATA (Required by PROJECT RULES Section 2)
-- ###########################################################################

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "SETTINGS",
	SHORT_NAME   = "Settings",
	DISPLAY_NAME = "Einstellungen",
	VERSION      = "1.1.4",
}

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G = _G
local GetTime = GetTime
---@diagnostic enable: undefined-global

-- ###########################################################################
-- #	LOGGING (Required by PROJECT RULES Section 4)
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return type(GetTime) == "function" and GetTime() or nil
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

	local buf = GMS._LOG_BUFFER
	local idx = #buf + 1
	buf[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		pcall(GMS._LOG_NOTIFY, entry, idx)
	end
end

local function ST(key, fallback, ...)
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

local function ResolveMetaName(entry, fallback)
	if type(GMS.ResolveRegistryDisplayName) == "function" then
		return GMS:ResolveRegistryDisplayName(entry, fallback)
	end
	if type(entry) == "table" then
		return tostring(entry.displayName or entry.name or entry.key or fallback or "")
	end
	return tostring(fallback or "")
end

-- ###########################################################################
-- #	EXTENSION REGISTRATION
-- ###########################################################################

if type(GMS.RegisterExtension) == "function" then
	GMS:RegisterExtension({
		key = METADATA.INTERN_NAME,
		name = METADATA.SHORT_NAME,
		displayName = METADATA.DISPLAY_NAME,
		version = METADATA.VERSION,
		desc = "Modular Settings UI & Slash Integration",
	})
end

-- ###########################################################################
-- #	UI: HELPERS
-- ###########################################################################

local function CreateHeading(parent, text)
	local label = AceGUI:Create("Heading")
	label:SetText(text)
	label:SetFullWidth(true)
	parent:AddChild(label)
	return label
end

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
-- #	UI: OPTIONS BUILDER (Right Pane)
-- ###########################################################################

local function BuildOptionsForTarget(container, targetType, targetKey)
	container:ReleaseChildren()

	local reg = nil
	if GMS.DB and GMS.DB._registrations then
		reg = GMS.DB._registrations[targetKey]
	end

	local options = GMS:GetModuleOptions(targetKey)
	local displayName = targetKey

	if targetType == "EXT" then
		if GMS.REGISTRY and GMS.REGISTRY.EXT and GMS.REGISTRY.EXT[targetKey] then
			displayName = ResolveMetaName(GMS.REGISTRY.EXT[targetKey], targetKey)
		end
	elseif targetType == "MOD" then
		if GMS.REGISTRY and GMS.REGISTRY.MOD and GMS.REGISTRY.MOD[targetKey] then
			displayName = ResolveMetaName(GMS.REGISTRY.MOD[targetKey], targetKey)
		end
	elseif targetType == "GEN" then
		displayName = ST("SETTINGS_CORE_TITLE", "Core addon settings")
		targetKey = "CORE"
	end

	CreateHeading(container, displayName)

	if not options or not reg or not reg.defaults then
		local lbl = AceGUI:Create("Label")
		lbl:SetText(ST("SETTINGS_NO_OPTIONS", "No configurable options found for this item."))
		lbl:SetFullWidth(true)
		container:AddChild(lbl)
		return
	end

	-- Sort keys for consistency
	local keys = {}
	for k in pairs(reg.defaults) do table.insert(keys, k) end
	table.sort(keys)

	for _, key in ipairs(keys) do
		local defaultVal = reg.defaults[key]
		local val = options[key]
		local valType = type(val)
		local optDisplayName = key

		-- Extraction of metadata if defaultVal is a table
		if type(defaultVal) == "table" then
			optDisplayName = defaultVal.name or key
		end

		-- Support for "execute" (button) type
		if type(defaultVal) == "table" and defaultVal.type == "execute" then
			local btn = AceGUI:Create("Button")
			btn:SetText(optDisplayName)
			btn:SetFullWidth(true)
			btn:SetCallback("OnClick", function()
				if type(defaultVal.func) == "function" then
					LOCAL_LOG("INFO", "Executing command", targetKey, key)
					defaultVal.func()
				end
			end)
			container:AddChild(btn)
		elseif valType == "boolean" or (type(defaultVal) == "table" and defaultVal.type == "toggle") then
			local cb = AceGUI:Create("CheckBox")
			cb:SetLabel(optDisplayName)
			cb:SetValue(val)
			cb:SetCallback("OnValueChanged", function(_, _, newValue)
				options[key] = newValue
				LOCAL_LOG("INFO", "Option changed", targetKey, key, newValue)

				-- Notify system via AceEvent
				if type(GMS.SendMessage) == "function" then
					GMS:SendMessage("GMS_CONFIG_CHANGED", targetKey, key, newValue)
				end
			end)
			container:AddChild(cb)
		elseif (type(defaultVal) == "table" and defaultVal.type == "range") or
			(valType == "number" and type(defaultVal) == "table" and defaultVal.type == "range") then
			local slider = AceGUI:Create("Slider")
			slider:SetLabel(optDisplayName)
			slider:SetValue(val)
			if type(defaultVal) == "table" then
				slider:SetSliderValues(defaultVal.min or 1, defaultVal.max or 100, defaultVal.step or 1)
			else
				slider:SetSliderValues(1, 100, 1)
			end
			slider:SetCallback("OnValueChanged", function(_, _, newValue)
				options[key] = newValue
				LOCAL_LOG("INFO", "Option changed", targetKey, key, newValue)
				if type(GMS.SendMessage) == "function" then
					GMS:SendMessage("GMS_CONFIG_CHANGED", targetKey, key, newValue)
				end
			end)
			container:AddChild(slider)
		elseif valType == "string" or valType == "number" then
			local eb = AceGUI:Create("EditBox")
			eb:SetLabel(optDisplayName)
			eb:SetText(tostring(val))
			eb:SetCallback("OnEnterPressed", function(_, _, newValue)
				if valType == "number" then
					local n = tonumber(newValue)
					if n then options[key] = n end
				else
					options[key] = newValue
				end
				LOCAL_LOG("INFO", "Option changed", targetKey, key, newValue)
				if type(GMS.SendMessage) == "function" then
					GMS:SendMessage("GMS_CONFIG_CHANGED", targetKey, key, newValue)
				end
			end)
			container:AddChild(eb)
		end
	end
end

local function BuildDashboardStartPage(container)
	container:ReleaseChildren()
	container:SetLayout("Flow")

	local intro = AceGUI:Create("Label")
	intro:SetFullWidth(true)
	intro:SetText(ST("SETTINGS_DASHBOARD_INTRO", "System status (as before in dashboard)."))
	container:AddChild(intro)

	local extGroup = AceGUI:Create("InlineGroup")
	extGroup:SetTitle(ST("SETTINGS_EXTENSIONS_TITLE", "Extensions (core system)"))
	extGroup:SetFullWidth(true)
	extGroup:SetLayout("Flow")
	container:AddChild(extGroup)

	if GMS.REGISTRY and GMS.REGISTRY.EXT then
		local extKeys = {}
		for k in pairs(GMS.REGISTRY.EXT) do table.insert(extKeys, k) end
		table.sort(extKeys)
		for _, k in ipairs(extKeys) do
			local e = GMS.REGISTRY.EXT[k]
			local row = AceGUI:Create("SimpleGroup")
			row:SetFullWidth(true)
			row:SetLayout("Flow")

			local lblName = AceGUI:Create("Label")
			lblName:SetText("- |cff03A9F4" .. ResolveMetaName(e, k) .. "|r")
			lblName:SetWidth(240)
			row:AddChild(lblName)

			local lblVer = AceGUI:Create("Label")
			lblVer:SetText("[v" .. tostring(e.version or "1.0.0") .. "]")
			lblVer:SetWidth(90)
			row:AddChild(lblVer)

			local lblState = AceGUI:Create("Label")
			lblState:SetText(GetStatusColor(e.state and e.state.READY, e.state and e.state.ENABLED))
			lblState:SetWidth(180)
			row:AddChild(lblState)

			extGroup:AddChild(row)
		end
	end

	local modGroup = AceGUI:Create("InlineGroup")
	modGroup:SetTitle(ST("SETTINGS_MODULES_TITLE", "Modules (features)"))
	modGroup:SetFullWidth(true)
	modGroup:SetLayout("Flow")
	container:AddChild(modGroup)

	if GMS.REGISTRY and GMS.REGISTRY.MOD then
		local modKeys = {}
		for k in pairs(GMS.REGISTRY.MOD) do table.insert(modKeys, k) end
		table.sort(modKeys)
		for _, k in ipairs(modKeys) do
			local m = GMS.REGISTRY.MOD[k]
			local row = AceGUI:Create("SimpleGroup")
			row:SetFullWidth(true)
			row:SetLayout("Flow")

			local lblName = AceGUI:Create("Label")
			lblName:SetText("- |cffffcc00" .. ResolveMetaName(m, k) .. "|r")
			lblName:SetWidth(240)
			row:AddChild(lblName)

			local lblVer = AceGUI:Create("Label")
			lblVer:SetText("[v" .. tostring(m.version or "1.0.0") .. "]")
			lblVer:SetWidth(90)
			row:AddChild(lblVer)

			local lblState = AceGUI:Create("Label")
			lblState:SetText(GetStatusColor(m.state and m.state.READY, m.state and m.state.ENABLED))
			lblState:SetWidth(180)
			row:AddChild(lblState)

			modGroup:AddChild(row)
		end
	end

	local btnRefresh = AceGUI:Create("Button")
	btnRefresh:SetText(ST("SETTINGS_STATUS_REFRESH", "Refresh status"))
	btnRefresh:SetWidth(180)
	btnRefresh:SetCallback("OnClick", function()
		BuildDashboardStartPage(container)
	end)
	container:AddChild(btnRefresh)
end

local function BuildLanguagePage(container)
	container:ReleaseChildren()
	container:SetLayout("Flow")

	local intro = AceGUI:Create("Label")
	intro:SetFullWidth(true)
	intro:SetText(ST("SETTINGS_LANG_INTRO", "Waehle die Addon-Sprache aus und klicke auf Anwenden."))
	container:AddChild(intro)

	local modeCurrent = "AUTO"
	if type(GMS.db) == "table" and type(GMS.db.profile) == "table" then
		modeCurrent = string.upper(tostring(GMS.db.profile.addonLanguageMode or "AUTO"))
	end

	local list = {
		AUTO = ST("SETTINGS_LANG_AUTO", "Automatisch (Clientsprache)"),
	}

	local localeLabelByCode = {
		enUS = ST("SETTINGS_LANG_ENUS", "English (US)"),
		enGB = ST("SETTINGS_LANG_ENGB", "English (UK)"),
		deDE = ST("SETTINGS_LANG_DEDE", "Deutsch"),
		frFR = ST("SETTINGS_LANG_FRFR", "Franzoesisch"),
		esES = ST("SETTINGS_LANG_ESES", "Spanisch (ES)"),
		esMX = ST("SETTINGS_LANG_ESMX", "Spanisch (MX)"),
		itIT = ST("SETTINGS_LANG_ITIT", "Italiano"),
		ptBR = ST("SETTINGS_LANG_PTBR", "Portugiesisch (BR)"),
		ruRU = ST("SETTINGS_LANG_RURU", "Ð ÑƒÑÑÐºÐ¸Ð¹"),
		koKR = ST("SETTINGS_LANG_KOKR", "í•œêµ­ì–´"),
		zhCN = ST("SETTINGS_LANG_ZHCN", "ç®€ä½“ä¸­æ–‡"),
		zhTW = ST("SETTINGS_LANG_ZHTW", "ç¹é«”ä¸­æ–‡"),
	}

	local codes = {}
	local data = GMS.LOCALE and GMS.LOCALE.data or nil
	if type(data) == "table" then
		for code, strings in pairs(data) do
			if type(code) == "string" and type(strings) == "table" then
				codes[#codes + 1] = code
			end
		end
	end
	table.sort(codes, function(a, b) return tostring(a) < tostring(b) end)
	for i = 1, #codes do
		local code = codes[i]
		list[code] = localeLabelByCode[code] or code
	end

	local dd = AceGUI:Create("Dropdown")
	dd:SetLabel(ST("SETTINGS_LANG_LABEL", "Sprache"))
	dd:SetList(list)
	dd:SetValue(list[modeCurrent] and modeCurrent or "AUTO")
	dd:SetWidth(320)
	container:AddChild(dd)

	local apply = AceGUI:Create("Button")
	apply:SetText(ST("SETTINGS_LANG_APPLY", "Anwenden"))
	apply:SetWidth(180)
	apply:SetCallback("OnClick", function()
		local selected = tostring(dd:GetValue() or "AUTO")
		if selected == "" then selected = "AUTO" end
		local ok = (type(GMS.SetLanguageMode) == "function") and GMS:SetLanguageMode(selected) or false
		if ok then
			LOCAL_LOG("INFO", "Language mode changed", selected)
			if type(GMS.Print) == "function" then
				local shown = list[selected] or selected
				GMS:Print(ST("SETTINGS_LANG_APPLIED_FMT", "Sprache angewendet: %s", shown))
			end
			if GMS.UI then
				-- Force page rebuild so cached pages pick up new locale strings instantly.
				local cache = GMS.UI._pageContainers
				if type(cache) == "table" then
					for pageID, container in pairs(cache) do
						if type(container) == "table" and container.frame then
							container.frame:Hide()
						end
						cache[pageID] = nil
					end
				end
				GMS.UI._lastNavTime = nil
				if type(GMS.UI.Navigate) == "function" then
					local page = tostring(GMS.UI._page or "SETTINGS")
					GMS.UI:Navigate(page)
				end
			end
		else
			if type(GMS.Print) == "function" then
				GMS:Print(ST("SETTINGS_LANG_APPLY_FAILED", "Sprache konnte nicht angewendet werden."))
			end
		end
	end)
	container:AddChild(apply)
end

-- ###########################################################################
-- #	UI: TREE DATA BUILDER
-- ###########################################################################

local function GetTreeData()
	local tree = {
		{
			value = "GEN_ROOT",
			text = ST("SETTINGS_TREE_GENERAL", "General"),
			children = {
				{ value = "GEN:DASHBOARD", text = ST("SETTINGS_TREE_DASHBOARD", "Home page (dashboard)") },
				{ value = "GEN:LANGUAGE", text = ST("SETTINGS_LANG_NAV", "Sprache") },
				{ value = "GEN:CORE", text = ST("SETTINGS_TREE_CORE", "Core settings") }
			},
		},
		{
			value = "EXT_ROOT",
			text = ST("SETTINGS_EXTENSIONS_TITLE", "Extensions (core system)"),
			children = {},
		},
		{
			value = "MOD_ROOT",
			text = ST("SETTINGS_MODULES_TITLE", "Modules (features)"),
			children = {},
		},
	}

	-- Extensions
	if GMS.REGISTRY and GMS.REGISTRY.EXT then
		local extKeys = {}
		for k in pairs(GMS.REGISTRY.EXT) do table.insert(extKeys, k) end
		table.sort(extKeys, function(a, b)
			local da = ResolveMetaName(GMS.REGISTRY.EXT[a], a)
			local db = ResolveMetaName(GMS.REGISTRY.EXT[b], b)
			return da < db
		end)
		for _, k in ipairs(extKeys) do
			local ext = GMS.REGISTRY.EXT[k]
			table.insert(tree[2].children, {
				value = "EXT:" .. k,
				text = ResolveMetaName(ext, k),
			})
		end
	end

	-- Modules
	if GMS.REGISTRY and GMS.REGISTRY.MOD then
		local modKeys = {}
		for k in pairs(GMS.REGISTRY.MOD) do table.insert(modKeys, k) end
		table.sort(modKeys, function(a, b)
			local da = ResolveMetaName(GMS.REGISTRY.MOD[a], a)
			local db = ResolveMetaName(GMS.REGISTRY.MOD[b], b)
			return da < db
		end)
		for _, k in ipairs(modKeys) do
			local mod = GMS.REGISTRY.MOD[k]
			table.insert(tree[3].children, {
				value = "MOD:" .. k,
				text = ResolveMetaName(mod, k),
			})
		end
	end

	return tree
end

-- ###########################################################################
-- #	UI: MAIN PAGE BUILDER
-- ###########################################################################

local function BuildSettingsPage(root, id, isCached)
	if GMS.UI and type(GMS.UI.Header_BuildDefault) == "function" then
		GMS.UI:Header_BuildDefault()
	end

	if isCached then return end

	root:SetLayout("Fill")

	local treeGroup = AceGUI:Create("TreeGroup")
	treeGroup:SetFullWidth(true)
	treeGroup:SetFullHeight(true)
	treeGroup:SetTree(GetTreeData())
	treeGroup:SetLayout("List")

	treeGroup:SetCallback("OnGroupSelected", function(self, _, group)
		local rawGroup = tostring(group or "")
		local leaf = rawGroup:match("([^\001]+)$") or rawGroup
		local targetType, targetKey = leaf:match("^([^:]+):(.+)$")

		if targetType and targetKey then
			if targetType == "GEN" and targetKey == "DASHBOARD" then
				BuildDashboardStartPage(self)
			elseif targetType == "GEN" and targetKey == "LANGUAGE" then
				BuildLanguagePage(self)
			else
				BuildOptionsForTarget(self, targetType, targetKey)
			end
		else
			self:ReleaseChildren()
			local lbl = AceGUI:Create("Label")
			lbl:SetText(ST("SETTINGS_SELECT_HINT", "Please select a module or extension from the list on the left."))
			lbl:SetFullWidth(true)
			self:AddChild(lbl)
		end
	end)

	root:AddChild(treeGroup)

	-- Select first logical group if available
	treeGroup:SelectByPath("GEN_ROOT", "GEN:DASHBOARD")
end

-- ###########################################################################
-- #	UI: INTEGRATION
-- ###########################################################################

local function RegisterSettingsPage()
	if GMS.UI and type(GMS.UI.RegisterPage) == "function" then
		GMS.UI:RegisterPage("SETTINGS", 100, METADATA.DISPLAY_NAME, BuildSettingsPage)
	end
end

-- ###########################################################################
-- #	SLASH COMMANDS
-- ###########################################################################

local function RegisterSlashCommands()
	if type(GMS.Slash_RegisterSubCommand) == "function" then
		local handler = function()
			if GMS.UI and type(GMS.UI.Navigate) == "function" then
				GMS.UI:Show()
				GMS.UI:Navigate("SETTINGS")
			end
		end

		GMS:Slash_RegisterSubCommand("options", handler,
			{ helpKey = "SETTINGS_SLASH_HELP", helpFallback = "/gms options - opens GMS settings", alias = { "settings", "o" }, owner = METADATA.INTERN_NAME })
	end
end

-- ###########################################################################
-- #	BOOTSTRAP
-- ###########################################################################

-- Try immediate registration if UI is already loaded
RegisterSettingsPage()
RegisterSlashCommands()

-- Also hook into OnReady for safety
GMS:OnReady("EXT:UI_PAGES", RegisterSettingsPage)
GMS:OnReady("EXT:SLASH", RegisterSlashCommands)

-- ###########################################################################
-- #	READY (Required by PROJECT RULES Section 7)
-- ###########################################################################

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)

LOCAL_LOG("INFO", "Settings extension loaded", METADATA.VERSION)
