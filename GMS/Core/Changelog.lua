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
	VERSION      = "1.3.7",
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
		version = "1.3.25",
		date = "2026-02-14",
		title_en = "CharInfo redesign and packaging metadata update",
		title_de = "CharInfo-Redesign und Paket-Metadaten-Update",
		notes_en = {
			"CharInfo page was reworked to a cleaner card-based layout with a dedicated actions section.",
			"Player snapshot and context are now displayed as structured key/value lines for faster scanning.",
			"Added refresh action and removed legacy debug-heavy page content.",
			"Added CurseForge project metadata to TOC: X-Curse-Project-ID: 863660.",
		},
		notes_de = {
			"Die CharInfo-Seite wurde auf ein aufgeraeumtes, kartenbasiertes Layout mit eigener Aktionssektion umgestellt.",
			"Spieler-Snapshot und Context werden jetzt als strukturierte Key/Value-Zeilen fuer schnelleres Erfassen angezeigt.",
			"Refresh-Aktion hinzugefuegt und den alten debuglastigen Seiteninhalt entfernt.",
			"CurseForge-Projektmetadaten im TOC ergaenzt: X-Curse-Project-ID: 863660.",
		},
	},
	{
		version = "1.3.24",
		date = "2026-02-14",
		title_en = "Roster polish: row sizing, context actions, and hover isolation",
		title_de = "Roster-Feinschliff: Zeilenhoehe, Kontextaktionen und Hover-Isolation",
		notes_en = {
			"Roster row height increased for cleaner spacing and hover fit.",
			"Context menu now opens at cursor position and invite/whisper actions were hardened for roster names.",
			"Self-invite is blocked in the context menu.",
			"Hover tooltip content was compacted and refined, including guild notes.",
			"Roster hover/tooltip effects are now restricted to the Roster page only and no longer leak into other pages.",
		},
		notes_de = {
			"Die Zeilenhoehe im Roster wurde fuer sauberere Abstaende und besseren Hover-Fit erhoeht.",
			"Das Kontextmenue oeffnet jetzt an der Mausposition; Invite/Whisper-Aktionen wurden fuer Roster-Namen robuster gemacht.",
			"Selbst-Einladungen werden im Kontextmenue blockiert.",
			"Der Hover-Tooltip wurde kompakter und strukturierter gestaltet, inkl. Gildennotizen.",
			"Hover-/Tooltip-Effekte sind jetzt strikt auf die Roster-Seite begrenzt und erscheinen nicht mehr auf anderen Seiten.",
		},
	},
	{
		version = "1.3.23",
		date = "2026-02-14",
		title_en = "Roster UX update: compact tooltips, context menu, and stable layout",
		title_de = "Roster-UX-Update: kompakte Tooltips, Kontextmenue und stabiles Layout",
		notes_en = {
			"Roster now includes new member columns for Last Online, item level, Mythic+ score, raid status, and known GMS version.",
			"Member context menu on right-click added: whisper, copy full name with realm, and invite to group.",
			"Tooltip was reworked into a compact table layout with class-colored name and guild notes.",
			"Header/content alignment was stabilized and column/header width mismatches were fixed.",
			"NEW/NEU marker logic was fixed so seen releases are no longer marked as new.",
		},
		notes_de = {
			"Das Roster enthaelt jetzt neue Mitgliederspalten fuer Zuletzt online, Itemlevel, Mythic+-Wertung, Raidstatus und bekannte GMS-Version.",
			"Kontextmenue per Rechtsklick auf Spieler hinzugefuegt: Anfluestern, Vollnamen mit Realm kopieren und in Gruppe einladen.",
			"Tooltip auf kompaktes Tabellenlayout umgestellt, inkl. Klassenfarbe beim Namen und Gildennotizen.",
			"Header-/Content-Ausrichtung stabilisiert und Breitenabweichungen zwischen Titelzeile und Spalten behoben.",
			"NEW/NEU-Markierungslogik korrigiert, sodass gesehene Releases nicht mehr als neu markiert werden.",
		},
	},
	{
		version = "1.3.22",
		date = "2026-02-14",
		title_en = "Roster hotfix: visibility filter function initialization",
		title_de = "Roster-Hotfix: Initialisierung der Sichtbarkeits-Filterfunktion",
		notes_en = {
			"Fixed Lua runtime error in Roster where FilterMembersByVisibility could be called before local initialization.",
			"Added local forward declaration so async roster build can safely call the filter function.",
		},
		notes_de = {
			"Lua-Laufzeitfehler im Roster behoben, bei dem FilterMembersByVisibility vor der lokalen Initialisierung aufgerufen werden konnte.",
			"Lokale Forward-Declaration ergaenzt, damit der asynchrone Roster-Build die Filterfunktion sicher aufrufen kann.",
		},
	},
	{
		version = "1.3.21",
		date = "2026-02-14",
		title_en = "Logs polish and major roster UX/performance update",
		title_de = "Logs-Feinschliff und groesseres Roster-UX/Performance-Update",
		notes_en = {
			"Logs: empty messages are filtered out from list and copy export.",
			"Logs: level selector now uses a robust dropdown menu and reflows correctly on resize/new entries.",
			"Roster: reduced UI churn via debounced roster updates and safer incremental/full rebuild decisions.",
			"Roster: guild header now shows guild name prominently, plus server/faction, with right-aligned online/offline toggles.",
			"Roster: added leading presence bullet per member (green online, gray offline, yellow AFK, red DND).",
			"Roster: sort indicator visibility fixed in header.",
		},
		notes_de = {
			"Logs: leere Messages werden in Liste und Copy-Export nicht mehr angezeigt.",
			"Logs: der Level-Selektor nutzt jetzt ein robustes Dropdown-Menue und reflowt korrekt bei Resize/neuen Eintraegen.",
			"Roster: UI-Last reduziert durch entprellte Roster-Updates und robustere Entscheidungen zwischen inkrementellem Update und Full-Rebuild.",
			"Roster: Header zeigt den Gildennamen prominent sowie Server/Fraktion; Online/Offline-Filter sind rechtsbuendig klickbar.",
			"Roster: fuehrender Presence-Bullet pro Spieler hinzugefuegt (gruen online, grau offline, gelb AFK, rot DND).",
			"Roster: Sichtbarkeit des Sortierindikators im Header korrigiert.",
		},
	},
	{
		version = "1.3.20",
		date = "2026-02-14",
		title_en = "Logs console redesign and flexible level filtering",
		title_de = "Logs-Konsole ueberarbeitet und Level-Filter flexibilisiert",
		notes_en = {
			"Logs list layout was compacted with adaptive columns so entries remain on a single line at default window size.",
			"Logs controls were moved into the global page header, and entries now render directly in content without an extra InlineGroup.",
			"Level filtering now uses a multi-select dropdown menu (Select All/None + TRACE/DEBUG/INFO/WARN/ERROR) with persistent per-level visibility.",
			"Legacy min-level setting is migrated automatically to the new per-level visibility flags.",
			"Logs dock icon now uses the bottom right-dock lane (with top-lane fallback for compatibility).",
		},
		notes_de = {
			"Das Layout der Logs-Liste wurde verdichtet und nutzt adaptive Spalten, sodass Eintraege in der Standardfenstergroesse einzeilig bleiben.",
			"Die Logs-Steuerung wurde in den globalen Seiten-Header verschoben; die Eintraege werden nun direkt im Content ohne zusaetzliche InlineGroup gerendert.",
			"Der Level-Filter nutzt jetzt ein Multi-Select-Dropdown (Alles/Keins + TRACE/DEBUG/INFO/WARN/ERROR) mit persistenter Sichtbarkeit pro Level.",
			"Das bisherige Min-Level-Setting wird automatisch auf die neuen Sichtbarkeits-Flags pro Level migriert.",
			"Das Logs-Dock-Icon wird jetzt im unteren RightDock-Bereich registriert (mit Top-Fallback fuer Kompatibilitaet).",
		},
	},
	{
		version = "1.3.19",
		date = "2026-02-14",
		title_en = "Visual NEW marker for unseen release entries",
		title_de = "Visueller NEU-Marker fuer ungesehene Release-Eintraege",
		notes_en = {
			"Release entries newer than the last seen changelog version are now marked with NEW.",
			"Marker text is locale-dependent (EN: NEW, DE: NEU).",
		},
		notes_de = {
			"Release-Eintraege neuer als die zuletzt gesehene Changelog-Version werden jetzt mit NEU markiert.",
			"Marker-Text ist locale-abhaengig (EN: NEW, DE: NEU).",
		},
	},
	{
		version = "1.3.16",
		date = "2026-02-14",
		title_en = "Dedicated SavedVariable persistence for auto-open state",
		title_de = "Dedizierte SavedVariable-Persistenz fuer Auto-Open-Status",
		notes_en = {
			"Added standalone SavedVariable storage for changelog seen state.",
			"Auto-open seen-version check now uses profile, AceDB global, and standalone fallback.",
			"This prevents repeated opening when AceDB namespaces are delayed or unavailable.",
		},
		notes_de = {
			"Eigenstaendige SavedVariable-Speicherung fuer den Changelog-Status hinzugefuegt.",
			"Seen-Version-Pruefung nutzt jetzt Profil, AceDB-Global und eigenstaendigen Fallback.",
			"Damit wird wiederholtes Oeffnen verhindert, auch wenn AceDB-Namespace verzoegert ist.",
		},
	},
	{
		version = "1.3.15",
		date = "2026-02-14",
		title_en = "Persisted seen-version fallback storage",
		title_de = "Persistenter Fallback fuer gesehene Version",
		notes_en = {
			"Added global fallback persistence for last seen changelog version in GMS_DB.",
			"Auto-open check now reads seen version from profile and global fallback.",
			"Seen version write now updates both profile options and global fallback.",
		},
		notes_de = {
			"Globalen Fallback fuer persistente lastSeenVersion in GMS_DB hinzugefuegt.",
			"Auto-Open prueft gesehene Version jetzt aus Profil und globalem Fallback.",
			"Beim Speichern wird die gesehene Version jetzt in Profil und global geschrieben.",
		},
	},
	{
		version = "1.3.14",
		date = "2026-02-14",
		title_en = "Auto-open repeat prevention",
		title_de = "Wiederholtes Auto-Open verhindert",
		notes_en = {
			"Auto-open now marks the current version as seen immediately after opening the changelog.",
			"This prevents repeated opening on every reload for the same version.",
		},
		notes_de = {
			"Auto-Open markiert die aktuelle Version jetzt direkt nach dem Oeffnen als gesehen.",
			"Damit wird wiederholtes Oeffnen bei jedem Reload fuer dieselbe Version verhindert.",
		},
	},
	{
		version = "1.3.13",
		date = "2026-02-14",
		title_en = "Auto-open trigger hardening",
		title_de = "Auto-Open Trigger gehaertet",
		notes_en = {
			"Auto-open now triggers from PLAYER_LOGIN and PLAYER_ENTERING_WORLD.",
			"Auto-open no longer depends on a matching release entry for the current version.",
			"Option handling is now tolerant: only explicit false disables auto-open.",
		},
		notes_de = {
			"Auto-Open wird jetzt von PLAYER_LOGIN und PLAYER_ENTERING_WORLD ausgeloest.",
			"Auto-Open haengt nicht mehr von einem exakt passenden Release-Eintrag ab.",
			"Options-Handling ist toleranter: nur explizites false deaktiviert Auto-Open.",
		},
	},
	{
		version = "1.3.12",
		date = "2026-02-14",
		title_en = "Reliable auto-open after reload/login",
		title_de = "Zuverlaessiges Auto-Open nach Reload/Login",
		notes_en = {
			"Auto-open now only marks release notes as seen when the CHANGELOG page is actually active.",
			"Added retries if UI/pages are not fully registered yet during login.",
		},
		notes_de = {
			"Auto-Open markiert Release Notes jetzt erst als gesehen, wenn die CHANGELOG-Seite wirklich aktiv ist.",
			"Retry-Logik hinzugefuegt, falls UI/Pages beim Login noch nicht vollstaendig registriert sind.",
		},
	},
	{
		version = "1.3.11",
		date = "2026-02-14",
		title_en = "Locale-bound language and reliable auto-open",
		title_de = "Clientgebundene Sprache und zuverlaessiges Auto-Open",
		notes_en = {
			"Release note language is now bound to client locale.",
			"Date format is now locale-aware (DE: DD.MM.YYYY, EN: MM/DD/YYYY).",
			"Auto-open for new releases now retries until options/UI are available.",
		},
		notes_de = {
			"Die Sprache der Release Notes ist jetzt an die Client-Locale gebunden.",
			"Datumsformat ist jetzt locale-abhaengig (DE: DD.MM.YYYY, EN: MM/DD/YYYY).",
			"Auto-Open fuer neue Releases versucht es jetzt erneut, bis Optionen/UI verfuegbar sind.",
		},
	},
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
}

local function GetCurrentAddonVersion()
	local v = tostring((GMS and GMS.VERSION) or "")
	v = v:gsub("^%s+", ""):gsub("%s+$", "")
	return v
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

local function IsAutoOpenEnabled(opts)
	if type(opts) ~= "table" then return true end
	-- Only an explicit boolean false disables the feature.
	return opts.showOnNewVersion ~= false
end

local function EnsureStandaloneState()
	if type(_G.GMS_Changelog_DB) ~= "table" then
		---@diagnostic disable-next-line: inject-field
		_G.GMS_Changelog_DB = {}
	end
	return _G.GMS_Changelog_DB
end

local function GetGlobalSeenVersion()
	if not GMS or not GMS.db or type(GMS.db.global) ~= "table" then
		return ""
	end
	local v = GMS.db.global.gmsChangelogLastSeenVersion
	return tostring(v or "")
end

local function SetGlobalSeenVersion(version)
	if not GMS or not GMS.db or type(GMS.db.global) ~= "table" then
		return
	end
	GMS.db.global.gmsChangelogLastSeenVersion = tostring(version or "")
	GMS.db.global.gmsChangelogLastSeenAt = now() or 0
end

local function GetStandaloneSeenVersion()
	local state = EnsureStandaloneState()
	return tostring(state.lastSeenVersion or "")
end

local function SetStandaloneSeenVersion(version)
	local state = EnsureStandaloneState()
	state.lastSeenVersion = tostring(version or "")
	state.lastSeenAt = now() or 0
end

local function GetEffectiveSeenVersion(opts)
	local profileSeen = (type(opts) == "table") and tostring(opts.lastSeenVersion or "") or ""
	if profileSeen ~= "" then
		return profileSeen
	end
	local globalSeen = GetGlobalSeenVersion()
	if globalSeen ~= "" then
		return globalSeen
	end
	return GetStandaloneSeenVersion()
end

local function IsReleaseNewForSeenVersion(releaseVersion, seenVersion)
	local target = tostring(releaseVersion or "")
	local seen = tostring(seenVersion or "")
	if target == "" then return false end
	if seen == "" then return true end
	if target == seen then return false end

	for i = 1, #RELEASES do
		local v = tostring(RELEASES[i].version or "")
		if v == seen then
			return false
		end
		if v == target then
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
	local locale = tostring((GetLocale and GetLocale()) or "")
	if locale == "deDE" then
		return "DE"
	end
	return "EN"
end

local function FormatDateByLanguage(isoDate, languageMode)
	local y, m, d = tostring(isoDate or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y or not m or not d then
		return tostring(isoDate or "?")
	end

	if languageMode == "DE" then
		return d .. "." .. m .. "." .. y
	end
	return m .. "/" .. d .. "/" .. y
end

local function MarkCurrentVersionSeen(reason)
	local opts = Changelog._options or EnsureOptions()

	local current = GetCurrentAddonVersion()
	if current == "" then return end

	if type(opts) == "table" then
		opts.lastSeenVersion = current
		opts.lastSeenAt = now() or 0
	end
	SetGlobalSeenVersion(current)
	SetStandaloneSeenVersion(current)
	LOCAL_LOG("INFO", "Marked changelog as seen", current, reason or "unknown")
end

local function TryAutoOpenOnLogin(attempt)
	attempt = tonumber(attempt) or 1
	if Changelog._autoShowDone then
		return
	end

	local opts = Changelog._options or EnsureOptions()
	if type(opts) ~= "table" then
		if attempt < 20 and C_Timer and C_Timer.After then
			C_Timer.After(0.5, function()
				TryAutoOpenOnLogin(attempt + 1)
			end)
		else
			LOCAL_LOG("WARN", "Changelog options unavailable for auto-open")
		end
		return
	end

	if not IsAutoOpenEnabled(opts) then
		Changelog._autoShowDone = true
		LOCAL_LOG("DEBUG", "Auto-open disabled by profile option")
		return
	end

	local current = GetCurrentAddonVersion()
	if current == "" then
		LOCAL_LOG("WARN", "Current addon version unavailable")
		return
	end

	if GetEffectiveSeenVersion(opts) == current then
		Changelog._autoShowDone = true
		LOCAL_LOG("DEBUG", "Current version already seen", current)
		return
	end

	if not HasReleaseEntry(current) then
		LOCAL_LOG("WARN", "No release entry for current version (still trying auto-open)", current)
	end

	local tries = 0
	local function attemptOpen()
		tries = tries + 1
		if GMS.UI and type(GMS.UI.Open) == "function" then
			-- Ensure page exists before opening; UI may be up before page registration finished.
			if not (GMS.UI._pages and GMS.UI._pages[METADATA.INTERN_NAME]) then
				RegisterInUI()
			end

			if GMS.UI._pages and GMS.UI._pages[METADATA.INTERN_NAME] then
				GMS.UI:Open(METADATA.INTERN_NAME)
				MarkCurrentVersionSeen("auto-login-open")
				Changelog._autoShowDone = true
				LOCAL_LOG("INFO", "Auto-opened changelog for new version", current)
				return
			end
		end

		if tries < 40 and C_Timer and C_Timer.After then
			C_Timer.After(0.5, attemptOpen)
		else
			LOCAL_LOG("WARN", "Failed to auto-open changelog (page not available/active)")
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

local function BuildReleaseBlock(parent, release, isNew)
	local mode = ResolveLanguageMode()
	local formattedDate = FormatDateByLanguage(release.date, mode)

	local box = AceGUI:Create("InlineGroup")
	box:SetTitle(string.format("v%s (%s)", tostring(release.version or "?"), formattedDate))
	box:SetFullWidth(true)
	box:SetLayout("Flow")
	parent:AddChild(box)

	local titleText = (mode == "DE") and tostring(release.title_de or "-") or tostring(release.title_en or "-")
	local notesText = (mode == "DE") and RenderNotes(release.notes_de) or RenderNotes(release.notes_en)
	local newLabel = (mode == "DE") and "NEU" or "NEW"
	local newBadge = isNew and ("  |cff00ff00[" .. newLabel .. "]|r") or ""

	local title = AceGUI:Create("Label")
	title:SetFullWidth(true)
	title:SetText("|cff03A9F4" .. titleText .. "|r" .. newBadge)
	box:AddChild(title)

	local notes = AceGUI:Create("Label")
	notes:SetFullWidth(true)
	notes:SetText(notesText)
	box:AddChild(notes)
end

local function BuildChangelogPage(root, id, isCached)
	local opts = Changelog._options or EnsureOptions()
	local seenBeforeOpen = GetEffectiveSeenVersion(opts)

	if GMS.UI and type(GMS.UI.Header_BuildIconText) == "function" then
		local mode = ResolveLanguageMode()
		GMS.UI:Header_BuildIconText({
			icon = "Interface\\Icons\\INV_Scroll_03",
			text = "|cff03A9F4" .. METADATA.DISPLAY_NAME .. "|r",
			subtext = (mode == "DE") and "Alle Releases werden angezeigt" or "All releases are shown",
		})
	end

	if GMS.UI and type(GMS.UI.SetStatusText) == "function" then
		GMS.UI:SetStatusText("CHANGELOG: " .. tostring(#RELEASES) .. " releases loaded (" .. ResolveLanguageMode() .. ")")
	end

	if isCached and type(root.ReleaseChildren) == "function" then
		root:ReleaseChildren()
	end

	root:SetLayout("Fill")

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	root:AddChild(scroll)

	for i = 1, #RELEASES do
		local release = RELEASES[i]
		local isNew = IsReleaseNewForSeenVersion(release.version, seenBeforeOpen)
		BuildReleaseBlock(scroll, release, isNew)
	end

	MarkCurrentVersionSeen("manual-open")
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
	Changelog._loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	Changelog._loginFrame:SetScript("OnEvent", function(_, event)
		if event ~= "PLAYER_LOGIN" and event ~= "PLAYER_ENTERING_WORLD" then return end
		if C_Timer and C_Timer.After then
			C_Timer.After(1.0, function()
				TryAutoOpenOnLogin()
			end)
		else
			TryAutoOpenOnLogin()
		end
	end)
end

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)
LOCAL_LOG("INFO", "Changelog extension loaded", METADATA.VERSION)
