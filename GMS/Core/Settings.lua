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
	TYPE         = "EXTENSION",
	INTERN_NAME  = "SETTINGS",
	SHORT_NAME   = "Settings",
	DISPLAY_NAME = "Einstellungen",
	VERSION      = "1.0.0",
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
-- #	UI: PAGE BUILDER
-- ###########################################################################

local function CreateHeading(parent, text)
	local label = AceGUI:Create("Heading")
	label:SetText(text)
	label:SetFullWidth(true)
	parent:AddChild(label)
	return label
end

local function BuildOptionsForModule(container, modName, reg)
	if not reg or not reg.defaults then return end

	local options = GMS:GetModuleOptions(modName)
	if not options then return end

	CreateHeading(container, reg.name or modName)

	-- Sort keys for consistency
	local keys = {}
	for k in pairs(reg.defaults) do table.insert(keys, k) end
	table.sort(keys)

	for _, key in ipairs(keys) do
		local val = options[key]
		local valType = type(val)

		if valType == "boolean" then
			local cb = AceGUI:Create("CheckBox")
			cb:SetLabel(key)
			cb:SetValue(val)
			cb:SetCallback("OnValueChanged", function(_, _, newValue)
				options[key] = newValue
				LOCAL_LOG("INFO", "Option changed", modName, key, newValue)
			end)
			container:AddChild(cb)
		elseif valType == "string" or valType == "number" then
			local eb = AceGUI:Create("EditBox")
			eb:SetLabel(key)
			eb:SetText(tostring(val))
			eb:SetCallback("OnEnterPressed", function(_, _, newValue)
				if valType == "number" then
					local n = tonumber(newValue)
					if n then options[key] = n end
				else
					options[key] = newValue
				end
				LOCAL_LOG("INFO", "Option changed", modName, key, options[key])
			end)
			container:AddChild(eb)
		end
	end
end

local function BuildSettingsPage(root)
	root:SetLayout("Fill")

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	root:AddChild(scroll)

	local intro = AceGUI:Create("Label")
	intro:SetText("Hier kannst du alle Einstellungen für GMS und seine Module anpassen.")
	intro:SetFullWidth(true)
	scroll:AddChild(intro)

	-- Iterate over registered module options
	if GMS.DB and GMS.DB._registrations then
		-- Sort module names
		local modNames = {}
		for name in pairs(GMS.DB._registrations) do table.insert(modNames, name) end
		table.sort(modNames)

		for _, name in ipairs(modNames) do
			BuildOptionsForModule(scroll, name, GMS.DB._registrations[name])
		end
	else
		LOCAL_LOG("WARN", "GMS.DB._registrations not found")
	end
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
GMS:OnReady("EXT:UI", RegisterSettingsPage)
GMS:OnReady("EXT:SLASH", RegisterSlashCommands)

-- ###########################################################################
-- #	READY (Required by PROJECT RULES Section 7)
-- ###########################################################################

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)

LOCAL_LOG("INFO", "Settings extension loaded", METADATA.VERSION)
