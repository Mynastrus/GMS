-- ============================================================================
--	GMS/Locales/deDE.lua
--	German locale example
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

if type(GMS.RegisterLocale) ~= "function" then return end

GMS:RegisterLocale("deDE", {
	CORE_STARTUP_LOADED = "Addon geladen: Guild Management System v%s",
	CORE_STARTUP_HINT = "Mit %s kannst du das Hauptfenster aufrufen und mit %s die Hilfe.",

	SLASH_DISPLAY_NAME = "Chateingabe",
	SLASH_HELP_USAGE = "Verwendung: /gms <subcommand> [args]",
	SLASH_HELP_EXAMPLE = "Beispiel: /gms help",
	SLASH_HELP_NONE = "Keine Subcommands registriert.",
	SLASH_UNKNOWN_SUBCOMMAND = "Unbekannter Subcommand: %s",
	SLASH_HELP_RELOAD = "Laedt die UI neu.",

	UI_STATUS_READY = "Status: bereit",
	UI_HEADER_SUB_VERSION = "Version: |cffCCCCCC%s|r",
	UI_HEADER_SUB_ACTIVE = "UI Extension aktiv",
	UI_FALLBACK_TITLE = "|cff03A9F4GMS|r - UI ist geladen.",
	UI_FALLBACK_HINT_PAGES_INACTIVE = "Pages-System ist nicht aktiv (oder entfernt).",
	UI_RESET_WINDOW = "Fenster zuruecksetzen (Position/Groesse)",
	UI_FALLBACK_HINT_NAV_MISSING = "Navigate() aktiv, aber PAGES-Section fehlt.",
	UI_FALLBACK_HINT_UI_PAGES_MISSING = "UI_Pages Extension fehlt.",
	UI_CMD_OPEN_HELP = "Oeffnet die GMS UI (/gms ui [page])",

	LOGS_HEADER_TITLE = "Logging Console",
	LOGS_LEVELS = "Levels:",
	LOGS_SELECT_FMT = "Select (%d/5)",
	LOGS_SELECT_ALL = "Alle waehlen",
	LOGS_SELECT_NONE = "Nichts waehlen",
	LOGS_REFRESH = "Aktualisieren",
	LOGS_CLEAR = "Leeren",
	LOGS_COPY = "Kopieren (2000)",
	LOGS_DOCK_TOOLTIP = "Logs anzeigen",
	LOGS_SLASH_HELP = "/gms logs - oeffnet die Logs UI",
	LOGS_SUB_FALLBACK_DESC = "Oeffnet die Logs UI",

	ROSTER_SEARCH = "Suche:",
	ROSTER_SHOW_OFFLINE = "Offlinemitglieder anzeigen",
	ROSTER_EMPTY = "Keine Gildenmitglieder gefunden.",
	ROSTER_STATUS_SEARCH = "|cffb8b8b8Roster:|r angezeigt %d von %d (Suche: %s)",
	ROSTER_STATUS_FILTERED = "|cffb8b8b8Roster:|r angezeigt %d von %d",
	ROSTER_STATUS_TOTAL = "|cffb8b8b8Roster:|r %d Mitglieder",
	ROSTER_DOCK_TOOLTIP = "Oeffnet die Roster-Page",
	ROSTER_CTX_WHISPER = "Anfluestern",
	ROSTER_CTX_COPY_NAME = "Name kopieren (inkl. Realm)",
	ROSTER_CTX_INVITE = "In Gruppe einladen",
})

