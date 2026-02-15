-- ============================================================================
--	GMS/Locales/frFR.lua
--	French locale
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

if type(GMS.RegisterLocale) ~= "function" then return end

GMS:RegisterLocale("frFR", {
	CORE_STARTUP_LOADED = "Addon charge : Guild Management System v%s",
	CORE_STARTUP_HINT = "Utilisez %s pour ouvrir la fenetre principale et %s pour l'aide.",

	SLASH_DISPLAY_NAME = "Entree chat",
	SLASH_HELP_USAGE = "Utilisation : /gms <subcommand> [args]",
	SLASH_HELP_EXAMPLE = "Exemple : /gms help",
	SLASH_HELP_NONE = "Aucune sous-commande enregistree.",
	SLASH_UNKNOWN_SUBCOMMAND = "Sous-commande inconnue : %s",
	SLASH_HELP_RELOAD = "Recharge l'interface.",

	UI_STATUS_READY = "Statut : pret",
	UI_HEADER_SUB_VERSION = "Version : |cffCCCCCC%s|r",
	UI_HEADER_SUB_ACTIVE = "Extension UI active",
	UI_FALLBACK_TITLE = "|cff03A9F4GMS|r - L'interface est chargee.",
	UI_FALLBACK_HINT_PAGES_INACTIVE = "Le systeme de pages n'est pas actif (ou supprime).",
	UI_RESET_WINDOW = "Reinitialiser la fenetre (position/taille)",
	UI_FALLBACK_HINT_NAV_MISSING = "Navigate() est actif, mais la section PAGES est absente.",
	UI_FALLBACK_HINT_UI_PAGES_MISSING = "Extension UI_Pages manquante.",
	UI_CMD_OPEN_HELP = "Ouvre l'UI GMS (/gms ui [page])",

	LOGS_HEADER_TITLE = "Console des journaux",
	LOGS_LEVELS = "Niveaux :",
	LOGS_SELECT_FMT = "Selection (%d/5)",
	LOGS_SELECT_ALL = "Tout selectionner",
	LOGS_SELECT_NONE = "Tout deselectionner",
	LOGS_REFRESH = "Actualiser",
	LOGS_CLEAR = "Vider",
	LOGS_COPY = "Copier (2000)",
	LOGS_DOCK_TOOLTIP = "Ouvrir les journaux",
	LOGS_SLASH_HELP = "/gms logs - ouvre l'UI des journaux",
	LOGS_SUB_FALLBACK_DESC = "Ouvre l'UI des journaux",

	ROSTER_SEARCH = "Recherche :",
	ROSTER_SHOW_OFFLINE = "Afficher les membres hors ligne",
	ROSTER_EMPTY = "Aucun membre de guilde trouve.",
	ROSTER_STATUS_SEARCH = "|cffb8b8b8Roster:|r affichage %d sur %d (recherche : %s)",
	ROSTER_STATUS_FILTERED = "|cffb8b8b8Roster:|r affichage %d sur %d",
	ROSTER_STATUS_TOTAL = "|cffb8b8b8Roster:|r %d membres",
	ROSTER_DOCK_TOOLTIP = "Ouvrir la page roster",
	ROSTER_CTX_WHISPER = "Chuchoter",
	ROSTER_CTX_COPY_NAME = "Copier le nom (avec royaume)",
	ROSTER_CTX_INVITE = "Inviter dans le groupe",

	GA_PAGE_TITLE = "Journal de guilde",
	GA_HEADER_TITLE = "Journal de guilde",
	GA_HEADER_SUB = "Suit les changements du roster de guilde dans un journal dedie au module.",
	GA_CHAT_ECHO = "Publier les nouvelles entrees dans le chat",
	GA_REFRESH = "Actualiser",
	GA_CLEAR = "Vider",
	GA_EMPTY = "Aucune entree d'activite de guilde pour le moment.",
	GA_STATUS_FMT = "Journal de guilde : %d entrees",
	GA_BASELINE = "Instantane initial de la guilde capture (%d membres).",
	GA_DOCK_TOOLTIP = "Ouvrir le journal d'activite de guilde",
	GA_SLASH_HELP = "/gms guildlog - ouvre le journal d'activite de guilde",

	GA_JOIN = "%s a rejoint la guilde.",
	GA_REJOIN = "%s a rejoint a nouveau la guilde.",
	GA_LEAVE = "%s a quitte la guilde.",
	GA_PROMOTE = "%s promu (%s -> %s).",
	GA_DEMOTE = "%s retrograde (%s -> %s).",
	GA_NAME_CHANGED = "%s a change le nom du personnage en %s.",
	GA_REALM_CHANGED = "%s a change de royaume de %s a %s.",
	GA_FACTION_CHANGED = "%s a change de faction de %s a %s.",
	GA_RACE_CHANGED = "%s a change de race de %s a %s.",
	GA_LEVEL_CHANGED = "%s a change de niveau de %d a %d.",
	GA_ONLINE = "%s est maintenant en ligne.",
	GA_OFFLINE = "%s est passe hors ligne.",
	GA_NOTE_CHANGED = "%s a mis a jour la note publique.",
	GA_OFFICER_NOTE_CHANGED = "%s a mis a jour la note d'officier.",
	GA_NOTE_CHANGED_DETAIL = "%s a mis a jour la note publique (%s -> %s).",
	GA_OFFICER_NOTE_CHANGED_DETAIL = "%s a mis a jour la note d'officier (%s -> %s).",
})
