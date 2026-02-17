-- ============================================================================
--	GMS/Locales/enUS.lua
--	English fallback/base locale
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

if type(GMS.RegisterLocale) ~= "function" then return end

GMS:RegisterLocale("enUS", {
	CORE_STARTUP_LOADED = "Addon loaded: Guild Management System v%s",
	CORE_STARTUP_HINT = "Use %s to open the main window and %s for help.",

	SLASH_DISPLAY_NAME = "Chat Input",
	SLASH_HELP_USAGE = "Usage: /gms <subcommand> [args]",
	SLASH_HELP_EXAMPLE = "Example: /gms help",
	SLASH_HELP_NONE = "No subcommands registered.",
	SLASH_UNKNOWN_SUBCOMMAND = "Unknown subcommand: %s",
	SLASH_HELP_RELOAD = "Reloads the UI.",

	UI_STATUS_READY = "Status: ready",
	UI_HEADER_SUB_VERSION = "Version: |cffCCCCCC%s|r",
	UI_HEADER_SUB_ACTIVE = "UI extension active",
	UI_FALLBACK_TITLE = "|cff03A9F4GMS|r - UI is loaded.",
	UI_FALLBACK_HINT_PAGES_INACTIVE = "Pages system is not active (or removed).",
	UI_RESET_WINDOW = "Reset window (position/size)",
	UI_FALLBACK_HINT_NAV_MISSING = "Navigate() active, but PAGES section is missing.",
	UI_FALLBACK_HINT_UI_PAGES_MISSING = "UI_Pages extension missing.",
	UI_CMD_OPEN_HELP = "Opens the GMS UI (/gms ui [page])",

	LOGS_HEADER_TITLE = "Logging Console",
	LOGS_LEVELS = "Levels:",
	LOGS_SELECT_FMT = "Select (%d/5)",
	LOGS_SELECT_ALL = "Select All",
	LOGS_SELECT_NONE = "Select None",
	LOGS_REFRESH = "Refresh",
	LOGS_CLEAR = "Clear",
	LOGS_COPY = "Copy (2000)",
	LOGS_DOCK_TOOLTIP = "Open logs",
	LOGS_SLASH_HELP = "/gms logs - opens the logs UI",
	LOGS_SUB_FALLBACK_DESC = "Opens the logs UI",

	ROSTER_SEARCH = "Search:",
	ROSTER_SHOW_OFFLINE = "Show offline members",
	ROSTER_EMPTY = "No guild members found.",
	ROSTER_STATUS_SEARCH = "|cffb8b8b8Roster:|r showing %d of %d (search: %s)",
	ROSTER_STATUS_FILTERED = "|cffb8b8b8Roster:|r showing %d of %d",
	ROSTER_STATUS_TOTAL = "|cffb8b8b8Roster:|r %d members",
	ROSTER_DOCK_TOOLTIP = "Open roster page",
	ROSTER_CTX_WHISPER = "Whisper",
	ROSTER_CTX_COPY_NAME = "Copy name (with realm)",
	ROSTER_CTX_INVITE = "Invite to group",

	GA_PAGE_TITLE = "Guild Log",
	GA_HEADER_TITLE = "Guild Log",
	GA_HEADER_SUB = "Tracks guild roster changes in a dedicated module log.",
	GA_CHAT_ECHO = "Post new entries in chat",
	GA_REFRESH = "Refresh",
	GA_CLEAR = "Clear",
	GA_EMPTY = "No guild activity entries yet.",
	GA_STATUS_FMT = "Guild Log: %d entries",
	GA_BASELINE = "Initial guild snapshot captured (%d members).",
	GA_DOCK_TOOLTIP = "Open guild activity log",
	GA_SLASH_HELP = "/gms guildlog - opens guild activity log",

	GA_JOIN = "%s joined the guild.",
	GA_REJOIN = "%s rejoined the guild.",
	GA_LEAVE = "%s left the guild.",
	GA_PROMOTE = "%s promoted (%s -> %s).",
	GA_DEMOTE = "%s demoted (%s -> %s).",
	GA_NAME_CHANGED = "%s changed character name to %s.",
	GA_REALM_CHANGED = "%s changed realm from %s to %s.",
	GA_FACTION_CHANGED = "%s changed faction from %s to %s.",
	GA_RACE_CHANGED = "%s changed race from %s to %s.",
	GA_LEVEL_CHANGED = "%s changed level from %d to %d.",
	GA_ONLINE = "%s is now online.",
	GA_OFFLINE = "%s went offline.",
	GA_NOTE_CHANGED = "%s updated public note.",
	GA_OFFICER_NOTE_CHANGED = "%s updated officer note.",
	GA_NOTE_CHANGED_DETAIL = "%s updated public note (%s -> %s).",
	GA_OFFICER_NOTE_CHANGED_DETAIL = "%s updated officer note (%s -> %s).",

	RAIDS_SLASH_SCAN_REQUESTED = "Raids: scan requested.",
	RAIDS_SLASH_SCAN_FAILED = "Raids: scan could not be started.",
	RAIDS_SLASH_REBUILD_STARTED = "Raids: catalog rebuild started.",
	RAIDS_SLASH_REBUILD_FAILED = "Raids: catalog rebuild not available.",
	RAIDS_SLASH_USAGE = "Usage: /gms raids scan",
	RAIDS_SLASH_HELP = "/gms raids scan - trigger a raid lockout scan now",

	CHARINFO_ERROR_FMT = "CharInfo error: %s",
	CHARINFO_NO_DATA = "No data available.",
	CHARINFO_NO_DATA_FOUND_TITLE = "No Data Found",
	CHARINFO_NO_SYNCED_DATA_HINT = "No synced data exists for this character yet. Data will appear after sync/module scans.",
	CHARINFO_CARD_RAID_DATA = "Raid Data",
	CHARINFO_LABEL_BEST = "Best",
	CHARINFO_LABEL_SOURCE = "Source",
	CHARINFO_RAID_DIFF_LFR = "LFR",
	CHARINFO_RAID_DIFF_N = "N",
	CHARINFO_RAID_DIFF_H = "H",
	CHARINFO_RAID_DIFF_M = "M",
	CHARINFO_RAID_DIFF_BEST = "BEST",
	CHARINFO_RAID_TOOLTIP_NO_LOCKOUT = "No current lockout.",
	CHARINFO_RAID_TOOLTIP_LOCKOUT_FMT = "Lockout: %d / %d",
	CHARINFO_RAID_TOOLTIP_BOSS_KILLED = "Killed",
	CHARINFO_RAID_TOOLTIP_BOSS_AVAILABLE = "Available",
	CHARINFO_RAID_TOOLTIP_BOSSLIST_MISSING = "Boss list unavailable.",
	CHARINFO_RAID_NO_PROGRESS = "No raid progress data available for this character.",
	CHARINFO_RAID_ROWS_NOT_AVAILABLE = "Detailed per-raid rows are not available yet.",
	CHARINFO_RAID_DESC_MISSING = "No raid description available.",
	CHARINFO_RAID_WAIT_SCAN = "Waiting for raid scan",
	CHARINFO_RAID_WAIT_MOD_INIT = "Waiting for RAIDS module initialization...",
	CHARINFO_RAID_WAIT_STORE_BIND = "Waiting for character store binding...",
	CHARINFO_RAID_WAIT_SCAN_REASON = "Waiting for raid scan (%s)...",
	CHARINFO_RAID_WAIT_DEFERRED_SCAN = "Waiting for deferred raid statistics scan...",
	CHARINFO_RAID_WAIT_STATS_RUNNING = "Raid statistics scan running...",
	CHARINFO_RAID_WAIT_SAVEDINSTANCES = "Waiting for SavedInstances raid data...",
	CHARINFO_RAID_WAIT_EJ_INIT = "Waiting for Encounter Journal initialization...",
	CHARINFO_RAID_WAIT_FIRST_DATA = "Waiting for first raid data...",
})
