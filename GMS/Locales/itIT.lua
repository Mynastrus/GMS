-- ============================================================================
--	GMS/Locales/itIT.lua
--	Italian locale
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

if type(GMS.RegisterLocale) ~= "function" then return end

GMS:RegisterLocale("itIT", {
	CORE_STARTUP_LOADED = "Addon caricato: Guild Management System v%s",
	CORE_STARTUP_HINT = "Usa %s per aprire la finestra principale e %s per l'aiuto.",

	SLASH_DISPLAY_NAME = "Input chat",
	SLASH_HELP_USAGE = "Uso: /gms <subcommand> [args]",
	SLASH_HELP_EXAMPLE = "Esempio: /gms help",
	SLASH_HELP_NONE = "Nessun sottocomando registrato.",
	SLASH_UNKNOWN_SUBCOMMAND = "Sottocomando sconosciuto: %s",
	SLASH_HELP_RELOAD = "Ricarica l'interfaccia.",

	UI_STATUS_READY = "Stato: pronto",
	UI_HEADER_SUB_VERSION = "Versione: |cffCCCCCC%s|r",
	UI_HEADER_SUB_ACTIVE = "Estensione UI attiva",
	UI_FALLBACK_TITLE = "|cff03A9F4GMS|r - UI caricata.",
	UI_FALLBACK_HINT_PAGES_INACTIVE = "Il sistema pagine non e attivo (o rimosso).",
	UI_RESET_WINDOW = "Reimposta finestra (posizione/dimensione)",
	UI_FALLBACK_HINT_NAV_MISSING = "Navigate() attivo, ma manca la sezione PAGES.",
	UI_FALLBACK_HINT_UI_PAGES_MISSING = "Estensione UI_Pages mancante.",
	UI_CMD_OPEN_HELP = "Apre la UI di GMS (/gms ui [page])",

	LOGS_HEADER_TITLE = "Console log",
	LOGS_LEVELS = "Livelli:",
	LOGS_SELECT_FMT = "Selezione (%d/5)",
	LOGS_SELECT_ALL = "Seleziona tutto",
	LOGS_SELECT_NONE = "Deseleziona tutto",
	LOGS_REFRESH = "Aggiorna",
	LOGS_CLEAR = "Pulisci",
	LOGS_COPY = "Copia (2000)",
	LOGS_DOCK_TOOLTIP = "Apri log",
	LOGS_SLASH_HELP = "/gms logs - apre la UI log",
	LOGS_SUB_FALLBACK_DESC = "Apre la UI log",

	ROSTER_SEARCH = "Cerca:",
	ROSTER_SHOW_OFFLINE = "Mostra membri offline",
	ROSTER_EMPTY = "Nessun membro di gilda trovato.",
	ROSTER_STATUS_SEARCH = "|cffb8b8b8Roster:|r mostra %d di %d (ricerca: %s)",
	ROSTER_STATUS_FILTERED = "|cffb8b8b8Roster:|r mostra %d di %d",
	ROSTER_STATUS_TOTAL = "|cffb8b8b8Roster:|r %d membri",
	ROSTER_DOCK_TOOLTIP = "Apri pagina roster",
	ROSTER_CTX_WHISPER = "Sussurra",
	ROSTER_CTX_COPY_NAME = "Copia nome (con reame)",
	ROSTER_CTX_INVITE = "Invita nel gruppo",

	GA_PAGE_TITLE = "Registro gilda",
	GA_HEADER_TITLE = "Registro gilda",
	GA_HEADER_SUB = "Traccia i cambiamenti del roster di gilda in un log dedicato al modulo.",
	GA_CHAT_ECHO = "Pubblica le nuove voci in chat",
	GA_REFRESH = "Aggiorna",
	GA_CLEAR = "Pulisci",
	GA_EMPTY = "Nessuna voce attivita gilda per ora.",
	GA_STATUS_FMT = "Registro gilda: %d voci",
	GA_BASELINE = "Snapshot iniziale della gilda acquisito (%d membri).",
	GA_DOCK_TOOLTIP = "Apri registro attivita gilda",
	GA_SLASH_HELP = "/gms guildlog - apre il registro attivita gilda",

	GA_JOIN = "%s si e unito alla gilda.",
	GA_REJOIN = "%s e rientrato nella gilda.",
	GA_LEAVE = "%s ha lasciato la gilda.",
	GA_PROMOTE = "%s promosso (%s -> %s).",
	GA_DEMOTE = "%s retrocesso (%s -> %s).",
	GA_NAME_CHANGED = "%s ha cambiato nome personaggio in %s.",
	GA_REALM_CHANGED = "%s ha cambiato reame da %s a %s.",
	GA_FACTION_CHANGED = "%s ha cambiato fazione da %s a %s.",
	GA_RACE_CHANGED = "%s ha cambiato razza da %s a %s.",
	GA_LEVEL_CHANGED = "%s ha cambiato livello da %d a %d.",
	GA_ONLINE = "%s e ora online.",
	GA_OFFLINE = "%s e andato offline.",
	GA_NOTE_CHANGED = "%s ha aggiornato la nota pubblica.",
	GA_OFFICER_NOTE_CHANGED = "%s ha aggiornato la nota ufficiale.",
	GA_NOTE_CHANGED_DETAIL = "%s ha aggiornato la nota pubblica (%s -> %s).",
	GA_OFFICER_NOTE_CHANGED_DETAIL = "%s ha aggiornato la nota ufficiale (%s -> %s).",
})
