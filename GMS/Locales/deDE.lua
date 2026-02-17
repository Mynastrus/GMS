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
	SLASH_HELP_RELOAD = "Lädt die UI neu.",

	UI_STATUS_READY = "Status: bereit",
	UI_HEADER_SUB_VERSION = "Version: |cffCCCCCC%s|r",
	UI_HEADER_SUB_ACTIVE = "UI Extension aktiv",
	UI_FALLBACK_TITLE = "|cff03A9F4GMS|r - UI ist geladen.",
	UI_FALLBACK_HINT_PAGES_INACTIVE = "Pages-System ist nicht aktiv (oder entfernt).",
	UI_RESET_WINDOW = "Fenster zurücksetzen (Position/Größe)",
	UI_FALLBACK_HINT_NAV_MISSING = "Navigate() aktiv, aber PAGES-Section fehlt.",
	UI_FALLBACK_HINT_UI_PAGES_MISSING = "UI_Pages Extension fehlt.",
	UI_CMD_OPEN_HELP = "Öffnet die GMS UI (/gms ui [page])",

	LOGS_HEADER_TITLE = "Logging Console",
	LOGS_LEVELS = "Levels:",
	LOGS_SELECT_FMT = "Select (%d/5)",
	LOGS_SELECT_ALL = "Alle wählen",
	LOGS_SELECT_NONE = "Nichts wählen",
	LOGS_REFRESH = "Aktualisieren",
	LOGS_CLEAR = "Leeren",
	LOGS_COPY = "Kopieren (2000)",
	LOGS_DOCK_TOOLTIP = "Logs anzeigen",
	LOGS_SLASH_HELP = "/gms logs - öffnet die Logs UI",
	LOGS_SUB_FALLBACK_DESC = "Öffnet die Logs UI",

	ROSTER_SEARCH = "Suche:",
	ROSTER_SHOW_OFFLINE = "Offlinemitglieder anzeigen",
	ROSTER_EMPTY = "Keine Gildenmitglieder gefunden.",
	ROSTER_STATUS_SEARCH = "|cffb8b8b8Roster:|r angezeigt %d von %d (Suche: %s)",
	ROSTER_STATUS_FILTERED = "|cffb8b8b8Roster:|r angezeigt %d von %d",
	ROSTER_STATUS_TOTAL = "|cffb8b8b8Roster:|r %d Mitglieder",
	ROSTER_DOCK_TOOLTIP = "Öffnet die Roster-Page",
	ROSTER_CTX_WHISPER = "Anflüstern",
	ROSTER_CTX_COPY_NAME = "Name kopieren (inkl. Realm)",
	ROSTER_CTX_INVITE = "In Gruppe einladen",

	GA_PAGE_TITLE = "Gildenlog",
	GA_HEADER_TITLE = "Gildenlog",
	GA_HEADER_SUB = "Protokolliert Gilden-Roster-Änderungen im eigenen Modul-Log.",
	GA_CHAT_ECHO = "Neue Einträge im Chat ausgeben",
	GA_REFRESH = "Aktualisieren",
	GA_CLEAR = "Leeren",
	GA_EMPTY = "Noch keine Gildenaktivitäts-Einträge.",
	GA_STATUS_FMT = "Gildenlog: %d Einträge",
	GA_BASELINE = "Initialer Gilden-Snapshot erfasst (%d Mitglieder).",
	GA_DOCK_TOOLTIP = "Gildenaktivitäts-Log öffnen",
	GA_SLASH_HELP = "/gms guildlog - öffnet das Gildenaktivitäts-Log",

	GA_JOIN = "%s ist der Gilde beigetreten.",
	GA_REJOIN = "%s ist der Gilde erneut beigetreten.",
	GA_LEAVE = "%s hat die Gilde verlassen.",
	GA_PROMOTE = "%s wurde befördert (%s -> %s).",
	GA_DEMOTE = "%s wurde degradiert (%s -> %s).",
	GA_NAME_CHANGED = "%s hat den Charakternamen zu %s geändert.",
	GA_REALM_CHANGED = "%s hat den Server von %s zu %s gewechselt.",
	GA_FACTION_CHANGED = "%s hat die Fraktion von %s zu %s gewechselt.",
	GA_RACE_CHANGED = "%s hat das Volk von %s zu %s gewechselt.",
	GA_LEVEL_CHANGED = "%s hat das Level von %d auf %d geändert.",
	GA_ONLINE = "%s ist jetzt online.",
	GA_OFFLINE = "%s ist jetzt offline.",
	GA_NOTE_CHANGED = "%s hat die öffentliche Notiz geändert.",
	GA_OFFICER_NOTE_CHANGED = "%s hat die Offiziersnotiz geändert.",
	GA_NOTE_CHANGED_DETAIL = "%s hat die öffentliche Notiz geändert (%s -> %s).",
	GA_OFFICER_NOTE_CHANGED_DETAIL = "%s hat die Offiziersnotiz geändert (%s -> %s).",

	RAIDS_SLASH_SCAN_REQUESTED = "Raids: Scan angefordert.",
	RAIDS_SLASH_SCAN_FAILED = "Raids: Scan konnte nicht gestartet werden.",
	RAIDS_SLASH_REBUILD_STARTED = "Raids: Katalog-Neuaufbau gestartet.",
	RAIDS_SLASH_REBUILD_FAILED = "Raids: Katalog-Neuaufbau nicht verfügbar.",
	RAIDS_SLASH_USAGE = "Verwendung: /gms raids scan",
	RAIDS_SLASH_HELP = "/gms raids scan - startet jetzt einen Raid-Lockout-Scan",

	CHARINFO_ERROR_FMT = "CharInfo Fehler: %s",
	CHARINFO_NO_DATA = "Keine Daten verfügbar.",
	CHARINFO_NO_DATA_FOUND_TITLE = "Keine Daten gefunden",
	CHARINFO_NO_SYNCED_DATA_HINT = "Für diesen Charakter liegen noch keine synchronisierten Daten vor. Daten erscheinen nach Sync/Modul-Scans.",
	CHARINFO_CARD_RAID_DATA = "Raid-Daten",
	CHARINFO_LABEL_BEST = "Best",
	CHARINFO_LABEL_SOURCE = "Quelle",
	CHARINFO_RAID_DIFF_LFR = "LFR",
	CHARINFO_RAID_DIFF_N = "N",
	CHARINFO_RAID_DIFF_H = "H",
	CHARINFO_RAID_DIFF_M = "M",
	CHARINFO_RAID_DIFF_BEST = "BEST",
	CHARINFO_RAID_TOOLTIP_NO_LOCKOUT = "Kein aktueller Lockout.",
	CHARINFO_RAID_TOOLTIP_LOCKOUT_FMT = "Lockout: %d / %d",
	CHARINFO_RAID_TOOLTIP_BOSS_KILLED = "Besiegt",
	CHARINFO_RAID_TOOLTIP_BOSS_AVAILABLE = "Verfügbar",
	CHARINFO_RAID_TOOLTIP_BOSSLIST_MISSING = "Bossliste nicht verfügbar.",
	CHARINFO_RAID_NO_PROGRESS = "Keine Raid-Fortschrittsdaten für diesen Charakter verfügbar.",
	CHARINFO_RAID_ROWS_NOT_AVAILABLE = "Detaillierte Raid-Zeilen sind noch nicht verfügbar.",
	CHARINFO_RAID_DESC_MISSING = "Keine Raidbeschreibung verfügbar.",
	CHARINFO_RAID_WAIT_SCAN = "Warte auf Raidscan",
	CHARINFO_RAID_WAIT_MOD_INIT = "Warte auf RAIDS-Modulinitialisierung...",
	CHARINFO_RAID_WAIT_STORE_BIND = "Warte auf Charakter-Speicherbindung...",
	CHARINFO_RAID_WAIT_SCAN_REASON = "Warte auf Raidscan (%s)...",
	CHARINFO_RAID_WAIT_DEFERRED_SCAN = "Warte auf verzögerten Raid-Statistikscan...",
	CHARINFO_RAID_WAIT_STATS_RUNNING = "Raid-Statistikscan läuft...",
	CHARINFO_RAID_WAIT_SAVEDINSTANCES = "Warte auf SavedInstances-Raiddaten...",
	CHARINFO_RAID_WAIT_EJ_INIT = "Warte auf Encounter-Journal-Initialisierung...",
	CHARINFO_RAID_WAIT_FIRST_DATA = "Warte auf erste Raid-Daten...",
})
