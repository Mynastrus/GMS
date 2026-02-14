-- ============================================================================
--	GMS/Core/Changelog.lua
--	CHANGELOG EXTENSION
--	- Displays all release notes (EN + DE) inside GMS UI
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
local _G = _G
local GetTime = GetTime
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetLocale = GetLocale
---@diagnostic enable: undefined-global

-- ###########################################################################
-- #	METADATA
-- ###########################################################################

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "CHANGELOG",
	SHORT_NAME   = "Changelog",
	DISPLAY_NAME = "Release Notes",
	VERSION      = "1.2.0",
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

	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry

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
	desc = "In-UI release history (EN + DE)",
})

local Changelog = GMS.Changelog or {}
GMS.Changelog = Changelog

Changelog._options = Changelog._options or nil
Changelog._autoShowDone = Changelog._autoShowDone or false

-- ###########################################################################
-- #	RELEASE DATA (all entries are rendered)
-- ###########################################################################

local RELEASES = {
	{
		version = "1.3.10",
		date = "2026-02-14",
		title_en = "Language selection for release notes",
		title_de = "Sprachauswahl fuer Release Notes",
		notes_en = {
			"Added language mode option: AUTO, DE, EN.",
			"AUTO now resolves to German on deDE clients, English otherwise.",
			"Added UI buttons to switch language directly on the changelog page.",
		},
		notes_de = {
			"Sprachmodus-Option hinzugefuegt: AUTO, DE, EN.",
			"AUTO waehlt auf deDE-Clients Deutsch, sonst Englisch.",
			"UI-Buttons zum direkten Sprachwechsel auf der Changelog-Seite hinzugefuegt.",
		},
	},
	{
		version = "1.3.9",
		date = "2026-02-14",
		title_en = "Auto-open for new release notes added",
		title_de = "Auto-Open fuer neue Release Notes hinzugefuegt",
		notes_en = {
			"Added one-time auto-open of changelog on first login after an update.",
			"Added persistent and user-toggleable option to disable auto-open.",
			"Added per-profile tracking of the last seen addon version.",
		},
		notes_de = {
			"Einmaliges Auto-Open des Changelogs beim ersten Login nach einem Update hinzugefuegt.",
			"Persistente und deaktivierbare Option fuer Auto-Open hinzugefuegt.",
			"Profilbasierte Speicherung der zuletzt gesehenen Addon-Version hinzugefuegt.",
		},
	},
	{
		version = "1.3.8",
		date = "2026-02-14",
		title_en = "Changelog extension introduced",
		title_de = "Changelog-Extension eingefuehrt",
		notes_en = {
			"Added in-game changelog page that renders all releases.",
			"Added bilingual release note structure (EN + DE) per release.",
			"Updated project rules for changelog maintenance.",
		},
		notes_de = {
			"Ingame-Changelog-Seite hinzugefuegt, die alle Releases anzeigt.",
			"Zweisprachige Struktur (EN + DE) pro Release eingefuehrt.",
			"Projektregeln fuer die Changelog-Pflege erweitert.",
		},
	},
	{
		version = "1.3.7",
		date = "2026-02-14",
		title_en = "Security and rules compliance update",
		title_de = "Security- und Rule-Compliance-Update",
		notes_en = {
			"Comm sender validation hardened against spoofed packet sources.",
			"UI active-page persistence fixed and SavedVariables aligned.",
			"Permissions and lifecycle compliance fixes applied.",
		},
		notes_de = {
			"Comm-Sender-Validierung gegen gespoofte Paketquellen gehaertet.",
			"UI-Active-Page-Persistenz repariert und SavedVariables abgeglichen.",
			"Permissions- und Lifecycle-Compliance-Fixes umgesetzt.",
		},
	},
	{
		version = "1.3.6",
		date = "2026-02-14",
		title_en = "Permissions persistence stabilization",
		title_de = "Stabilisierung der Permissions-Persistenz",
		notes_en = {
			"Resolved persistence issues in permissions profile data.",
		},
		notes_de = {
			"Persistenzprobleme in den Permissions-Profildaten behoben.",
		},
	},
	{
		version = "1.0.1",
		date = "2026-02-14",
		title_en = "First tagged baseline",
		title_de = "Erster getaggter Stand",
		notes_en = {
			"Repository baseline release tag.",
		},
		notes_de = {
			"Baseline-Release-Tag des Repositories.",
		},
	},
}

local CHANGELOG_OPTIONS_DEFAULTS = {
	showOnNewVersion = {
		type = "toggle",
		name = "Neue Release Notes beim Login automatisch anzeigen",
		default = true,
	},
	languageMode = {
		type = "string",
		name = "Sprache (AUTO/DE/EN)",
		default = "AUTO",
	},
}

local function GetCurrentAddonVersion()
	return tostring((GMS and GMS.VERSION) or "")
end

local function HasReleaseEntry(version)
	local v = tostring(version or "")
	if v == "" then return false end
	for i = 1, #RELEASES do
		if tostring(RELEASES[i].version or "") == v then
			return true
		end
	end
	return false
end

local function EnsureOptions()
	if not GMS or type(GMS.RegisterModuleOptions) ~= "function" then
		return nil
	end

	pcall(function()
		GMS:RegisterModuleOptions(METADATA.INTERN_NAME, CHANGELOG_OPTIONS_DEFAULTS, "PROFILE")
	end)

	if type(GMS.GetModuleOptions) ~= "function" then
		return nil
	end

	local ok, opts = pcall(GMS.GetModuleOptions, GMS, METADATA.INTERN_NAME)
	if not ok or type(opts) ~= "table" then
		return nil
	end

	if opts.showOnNewVersion == nil then
		opts.showOnNewVersion = true
	end
	opts.languageMode = tostring(opts.languageMode or "AUTO"):upper()
	if opts.languageMode ~= "AUTO" and opts.languageMode ~= "DE" and opts.languageMode ~= "EN" then
		opts.languageMode = "AUTO"
	end
	if type(opts.lastSeenVersion) ~= "string" then
		opts.lastSeenVersion = ""
	end
	if type(opts.lastSeenAt) ~= "number" then
		opts.lastSeenAt = 0
	end

	Changelog._options = opts
	return opts
end

local function ResolveLanguageMode()
	local opts = Changelog._options or EnsureOptions()
	local mode = (type(opts) == "table" and tostring(opts.languageMode or "AUTO") or "AUTO"):upper()
	if mode == "DE" then return "DE" end
	if mode == "EN" then return "EN" end
	local locale = tostring((GetLocale and GetLocale()) or "")
	if locale == "deDE" then
		return "DE"
	end
	return "EN"
end

local function MarkCurrentVersionSeen(reason)
	local opts = Changelog._options or EnsureOptions()
	if type(opts) ~= "table" then return end

	local current = GetCurrentAddonVersion()
	if current == "" then return end

	opts.lastSeenVersion = current
	opts.lastSeenAt = now() or 0
	LOCAL_LOG("INFO", "Marked changelog as seen", current, reason or "unknown")
end

local function TryAutoOpenOnLogin()
	if Changelog._autoShowDone then
		return
	end

	local opts = Changelog._options or EnsureOptions()
	if type(opts) ~= "table" then
		LOCAL_LOG("WARN", "Changelog options unavailable for auto-open")
		return
	end

	if opts.showOnNewVersion ~= true then
		Changelog._autoShowDone = true
		LOCAL_LOG("DEBUG", "Auto-open disabled by profile option")
		return
	end

	local current = GetCurrentAddonVersion()
	if current == "" then
		LOCAL_LOG("WARN", "Current addon version unavailable")
		return
	end

	if tostring(opts.lastSeenVersion or "") == current then
		Changelog._autoShowDone = true
		LOCAL_LOG("DEBUG", "Current version already seen", current)
		return
	end

	if not HasReleaseEntry(current) then
		LOCAL_LOG("WARN", "No release entry for current version", current)
		Changelog._autoShowDone = true
		return
	end

	local tries = 0
	local function attemptOpen()
		tries = tries + 1
		if GMS.UI and type(GMS.UI.Open) == "function" then
			GMS.UI:Open(METADATA.INTERN_NAME)
			MarkCurrentVersionSeen("auto-login-open")
			Changelog._autoShowDone = true
			LOCAL_LOG("INFO", "Auto-opened changelog for new version", current)
			return
		end

		if tries < 20 and C_Timer and C_Timer.After then
			C_Timer.After(0.5, attemptOpen)
		else
			LOCAL_LOG("WARN", "Failed to auto-open changelog (UI unavailable)")
		end
	end

	attemptOpen()
end

local function RenderNotes(lines)
	if type(lines) ~= "table" or #lines == 0 then
		return "- n/a"
	end

	local out = {}
	for i = 1, #lines do
		out[#out + 1] = "- " .. tostring(lines[i] or "")
	end
	return table.concat(out, "\n")
end

local function BuildReleaseBlock(parent, release)
	local box = AceGUI:Create("InlineGroup")
	box:SetTitle(string.format("v%s (%s)", tostring(release.version or "?"), tostring(release.date or "?")))
	box:SetFullWidth(true)
	box:SetLayout("Flow")
	parent:AddChild(box)

	local mode = ResolveLanguageMode()
	local titleText = (mode == "DE") and tostring(release.title_de or "-") or tostring(release.title_en or "-")
	local notesText = (mode == "DE") and RenderNotes(release.notes_de) or RenderNotes(release.notes_en)

	local title = AceGUI:Create("Label")
	title:SetFullWidth(true)
	title:SetText("|cff03A9F4" .. mode .. "|r: " .. titleText)
	box:AddChild(title)

	local notes = AceGUI:Create("Label")
	notes:SetFullWidth(true)
	notes:SetText(notesText)
	box:AddChild(notes)
end

local function BuildChangelogPage(root, id, isCached)
	if GMS.UI and type(GMS.UI.Header_BuildIconText) == "function" then
		GMS.UI:Header_BuildIconText({
			icon = "Interface\\Icons\\INV_Scroll_03",
			text = "|cff03A9F4" .. METADATA.DISPLAY_NAME .. "|r",
			subtext = "All releases shown (EN + DE)",
		})
	end

	if GMS.UI and type(GMS.UI.SetStatusText) == "function" then
		GMS.UI:SetStatusText("CHANGELOG: " .. tostring(#RELEASES) .. " releases loaded (" .. ResolveLanguageMode() .. ")")
	end

	MarkCurrentVersionSeen("manual-open")

	if isCached then return end

	root:SetLayout("Fill")

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	root:AddChild(scroll)

	local languageRow = AceGUI:Create("InlineGroup")
	languageRow:SetTitle("Language / Sprache")
	languageRow:SetFullWidth(true)
	languageRow:SetLayout("Flow")
	scroll:AddChild(languageRow)

	local function SetLanguageMode(mode)
		local opts = Changelog._options or EnsureOptions()
		if type(opts) ~= "table" then return end
		opts.languageMode = tostring(mode or "AUTO"):upper()
		if GMS.UI and type(GMS.UI.Navigate) == "function" then
			GMS.UI:Navigate(METADATA.INTERN_NAME)
		end
	end

	local btnAuto = AceGUI:Create("Button")
	btnAuto:SetText("AUTO")
	btnAuto:SetWidth(120)
	btnAuto:SetCallback("OnClick", function() SetLanguageMode("AUTO") end)
	languageRow:AddChild(btnAuto)

	local btnDe = AceGUI:Create("Button")
	btnDe:SetText("Deutsch")
	btnDe:SetWidth(120)
	btnDe:SetCallback("OnClick", function() SetLanguageMode("DE") end)
	languageRow:AddChild(btnDe)

	local btnEn = AceGUI:Create("Button")
	btnEn:SetText("English")
	btnEn:SetWidth(120)
	btnEn:SetCallback("OnClick", function() SetLanguageMode("EN") end)
	languageRow:AddChild(btnEn)

	local active = AceGUI:Create("Label")
	active:SetFullWidth(true)
	active:SetText("Active language: " .. ResolveLanguageMode())
	languageRow:AddChild(active)

	for i = 1, #RELEASES do
		BuildReleaseBlock(scroll, RELEASES[i])
	end
end

local function RegisterInUI()
	if not GMS.UI or type(GMS.UI.RegisterPage) ~= "function" then
		return false
	end

	GMS.UI:RegisterPage(METADATA.INTERN_NAME, 95, METADATA.DISPLAY_NAME, BuildChangelogPage)

	if type(GMS.UI.AddRightDockIconBottom) == "function" then
		GMS.UI:AddRightDockIconBottom({
			id = METADATA.INTERN_NAME,
			order = 2,
			selectable = true,
			icon = "Interface\\Icons\\INV_Scroll_03",
			tooltipTitle = METADATA.DISPLAY_NAME,
			tooltipText = "Shows all release notes",
			onClick = function()
				if GMS.UI and type(GMS.UI.Open) == "function" then
					GMS.UI:Open(METADATA.INTERN_NAME)
				end
			end,
		})
	end

	return true
end

local function RegisterSlash()
	if type(GMS.Slash_RegisterSubCommand) ~= "function" then
		return false
	end

	GMS:Slash_RegisterSubCommand("changelog", function()
		if GMS.UI and type(GMS.UI.Open) == "function" then
			GMS.UI:Open(METADATA.INTERN_NAME)
		end
	end, {
		help = "Opens release notes (/gms changelog)",
		alias = { "notes", "releases" },
		owner = METADATA.INTERN_NAME,
	})

	return true
end

local function Init()
	EnsureOptions()

	local okUI = RegisterInUI()
	local okSlash = RegisterSlash()

	if okUI then
		LOCAL_LOG("INFO", "Changelog page registered", #RELEASES)
	end
	if okSlash then
		LOCAL_LOG("INFO", "Changelog slash command registered")
	end

	if not okUI and C_Timer and C_Timer.After then
		C_Timer.After(0.5, Init)
	end
end

Init()

if not Changelog._loginFrame and CreateFrame then
	Changelog._loginFrame = CreateFrame("Frame")
	Changelog._loginFrame:RegisterEvent("PLAYER_LOGIN")
	Changelog._loginFrame:SetScript("OnEvent", function(_, event)
		if event ~= "PLAYER_LOGIN" then return end
		TryAutoOpenOnLogin()
	end)
end

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)
LOCAL_LOG("INFO", "Changelog extension loaded", METADATA.VERSION)
