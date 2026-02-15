-- ============================================================================
--	GMS/Locales/esES.lua
--	Spanish (Spain) locale
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

if type(GMS.RegisterLocale) ~= "function" then return end

GMS:RegisterLocale("esES", {
	CORE_STARTUP_LOADED = "Addon cargado: Guild Management System v%s",
	CORE_STARTUP_HINT = "Usa %s para abrir la ventana principal y %s para la ayuda.",

	SLASH_DISPLAY_NAME = "Entrada de chat",
	SLASH_HELP_USAGE = "Uso: /gms <subcommand> [args]",
	SLASH_HELP_EXAMPLE = "Ejemplo: /gms help",
	SLASH_HELP_NONE = "No hay subcomandos registrados.",
	SLASH_UNKNOWN_SUBCOMMAND = "Subcomando desconocido: %s",
	SLASH_HELP_RELOAD = "Recarga la interfaz.",

	UI_STATUS_READY = "Estado: listo",
	UI_HEADER_SUB_VERSION = "Version: |cffCCCCCC%s|r",
	UI_HEADER_SUB_ACTIVE = "Extension de UI activa",
	UI_FALLBACK_TITLE = "|cff03A9F4GMS|r - La UI esta cargada.",
	UI_FALLBACK_HINT_PAGES_INACTIVE = "El sistema de paginas no esta activo (o fue eliminado).",
	UI_RESET_WINDOW = "Restablecer ventana (posicion/tamano)",
	UI_FALLBACK_HINT_NAV_MISSING = "Navigate() esta activo, pero falta la seccion PAGES.",
	UI_FALLBACK_HINT_UI_PAGES_MISSING = "Falta la extension UI_Pages.",
	UI_CMD_OPEN_HELP = "Abre la UI de GMS (/gms ui [page])",

	LOGS_HEADER_TITLE = "Consola de registros",
	LOGS_LEVELS = "Niveles:",
	LOGS_SELECT_FMT = "Seleccion (%d/5)",
	LOGS_SELECT_ALL = "Seleccionar todo",
	LOGS_SELECT_NONE = "Deseleccionar todo",
	LOGS_REFRESH = "Actualizar",
	LOGS_CLEAR = "Limpiar",
	LOGS_COPY = "Copiar (2000)",
	LOGS_DOCK_TOOLTIP = "Abrir registros",
	LOGS_SLASH_HELP = "/gms logs - abre la UI de registros",
	LOGS_SUB_FALLBACK_DESC = "Abre la UI de registros",

	ROSTER_SEARCH = "Buscar:",
	ROSTER_SHOW_OFFLINE = "Mostrar miembros desconectados",
	ROSTER_EMPTY = "No se encontraron miembros de la hermandad.",
	ROSTER_STATUS_SEARCH = "|cffb8b8b8Roster:|r mostrando %d de %d (busqueda: %s)",
	ROSTER_STATUS_FILTERED = "|cffb8b8b8Roster:|r mostrando %d de %d",
	ROSTER_STATUS_TOTAL = "|cffb8b8b8Roster:|r %d miembros",
	ROSTER_DOCK_TOOLTIP = "Abrir pagina de roster",
	ROSTER_CTX_WHISPER = "Susurrar",
	ROSTER_CTX_COPY_NAME = "Copiar nombre (con reino)",
	ROSTER_CTX_INVITE = "Invitar al grupo",

	GA_PAGE_TITLE = "Registro de hermandad",
	GA_HEADER_TITLE = "Registro de hermandad",
	GA_HEADER_SUB = "Rastrea cambios del roster de hermandad en un registro dedicado del modulo.",
	GA_CHAT_ECHO = "Publicar nuevas entradas en el chat",
	GA_REFRESH = "Actualizar",
	GA_CLEAR = "Limpiar",
	GA_EMPTY = "Aun no hay entradas de actividad de hermandad.",
	GA_STATUS_FMT = "Registro de hermandad: %d entradas",
	GA_BASELINE = "Instantanea inicial de la hermandad capturada (%d miembros).",
	GA_DOCK_TOOLTIP = "Abrir registro de actividad de hermandad",
	GA_SLASH_HELP = "/gms guildlog - abre el registro de actividad de hermandad",

	GA_JOIN = "%s se unio a la hermandad.",
	GA_REJOIN = "%s se volvio a unir a la hermandad.",
	GA_LEAVE = "%s dejo la hermandad.",
	GA_PROMOTE = "%s ascendido (%s -> %s).",
	GA_DEMOTE = "%s degradado (%s -> %s).",
	GA_NAME_CHANGED = "%s cambio el nombre del personaje a %s.",
	GA_REALM_CHANGED = "%s cambio de reino de %s a %s.",
	GA_FACTION_CHANGED = "%s cambio de faccion de %s a %s.",
	GA_RACE_CHANGED = "%s cambio de raza de %s a %s.",
	GA_LEVEL_CHANGED = "%s cambio de nivel de %d a %d.",
	GA_ONLINE = "%s ahora esta en linea.",
	GA_OFFLINE = "%s se desconecto.",
	GA_NOTE_CHANGED = "%s actualizo la nota publica.",
	GA_OFFICER_NOTE_CHANGED = "%s actualizo la nota de oficial.",
	GA_NOTE_CHANGED_DETAIL = "%s actualizo la nota publica (%s -> %s).",
	GA_OFFICER_NOTE_CHANGED_DETAIL = "%s actualizo la nota de oficial (%s -> %s).",
})
