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
	VERSION      = "1.1.1",
}

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
			displayName = GMS.REGISTRY.EXT[targetKey].displayName or GMS.REGISTRY.EXT[targetKey].name or targetKey
		end
	elseif targetType == "MOD" then
		if GMS.REGISTRY and GMS.REGISTRY.MOD and GMS.REGISTRY.MOD[targetKey] then
			displayName = GMS.REGISTRY.MOD[targetKey].displayName or GMS.REGISTRY.MOD[targetKey].name or targetKey
		end
	elseif targetType == "GEN" then
		displayName = "Zentrale Addon-Einstellungen"
		targetKey = "CORE"
	end

	CreateHeading(container, displayName)

	if not options or not reg or not reg.defaults then
		local lbl = AceGUI:Create("Label")
		lbl:SetText("Keine konfigurierbaren Optionen für dieses Element gefunden.")
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

-- ###########################################################################
-- #	UI: TREE DATA BUILDER
-- ###########################################################################

local function GetTreeData()
	local tree = {
		{
			value = "GEN_ROOT",
			text = "Allgemein",
			children = {
				{ value = "GEN:CORE", text = "Zentrale Einstellungen" }
			},
		},
		{
			value = "EXT_ROOT",
			text = "Erweiterungen (Extensions)",
			children = {},
		},
		{
			value = "MOD_ROOT",
			text = "Module",
			children = {},
		},
	}

	-- Extensions
	if GMS.REGISTRY and GMS.REGISTRY.EXT then
		local extKeys = {}
		for k in pairs(GMS.REGISTRY.EXT) do table.insert(extKeys, k) end
		table.sort(extKeys, function(a, b)
			local da = GMS.REGISTRY.EXT[a].displayName or a
			local db = GMS.REGISTRY.EXT[b].displayName or b
			return da < db
		end)
		for _, k in ipairs(extKeys) do
			local ext = GMS.REGISTRY.EXT[k]
			table.insert(tree[2].children, {
				value = "EXT:" .. k,
				text = ext.displayName or ext.name or k,
			})
		end
	end

	-- Modules
	if GMS.REGISTRY and GMS.REGISTRY.MOD then
		local modKeys = {}
		for k in pairs(GMS.REGISTRY.MOD) do table.insert(modKeys, k) end
		table.sort(modKeys, function(a, b)
			local da = GMS.REGISTRY.MOD[a].displayName or a
			local db = GMS.REGISTRY.MOD[b].displayName or b
			return da < db
		end)
		for _, k in ipairs(modKeys) do
			local mod = GMS.REGISTRY.MOD[k]
			table.insert(tree[3].children, {
				value = "MOD:" .. k,
				text = mod.displayName or mod.name or k,
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
		local parts = {}
		for p in string.gmatch(group, "([^:]+)") do
			table.insert(parts, p)
		end

		local targetType = parts[1]
		local targetKey = parts[2]

		if targetType and targetKey then
			BuildOptionsForTarget(self, targetType, targetKey)
		else
			self:ReleaseChildren()
			local lbl = AceGUI:Create("Label")
			lbl:SetText("Bitte wähle ein Modul oder eine Extension aus der Liste links aus.")
			lbl:SetFullWidth(true)
			self:AddChild(lbl)
		end
	end)

	root:AddChild(treeGroup)

	-- Select first logical group if available
	treeGroup:SelectByPath("GEN_ROOT", "GEN:CORE")
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
			{ help = "Öffnet die GMS-Einstellungen", alias = { "settings", "o" }, owner = METADATA.INTERN_NAME })
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
