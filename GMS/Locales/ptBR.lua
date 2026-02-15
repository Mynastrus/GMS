-- ============================================================================
--	GMS/Locales/ptBR.lua
--	Portuguese (Brazil) locale
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

if type(GMS.RegisterLocale) ~= "function" then return end

GMS:RegisterLocale("ptBR", {
	CORE_STARTUP_LOADED = "Addon carregado: Guild Management System v%s",
	CORE_STARTUP_HINT = "Use %s para abrir a janela principal e %s para ajuda.",

	SLASH_DISPLAY_NAME = "Entrada do chat",
	SLASH_HELP_USAGE = "Uso: /gms <subcommand> [args]",
	SLASH_HELP_EXAMPLE = "Exemplo: /gms help",
	SLASH_HELP_NONE = "Nenhum subcomando registrado.",
	SLASH_UNKNOWN_SUBCOMMAND = "Subcomando desconhecido: %s",
	SLASH_HELP_RELOAD = "Recarrega a interface.",

	UI_STATUS_READY = "Status: pronto",
	UI_HEADER_SUB_VERSION = "Versao: |cffCCCCCC%s|r",
	UI_HEADER_SUB_ACTIVE = "Extensao de UI ativa",
	UI_FALLBACK_TITLE = "|cff03A9F4GMS|r - UI carregada.",
	UI_FALLBACK_HINT_PAGES_INACTIVE = "O sistema de paginas nao esta ativo (ou foi removido).",
	UI_RESET_WINDOW = "Redefinir janela (posicao/tamanho)",
	UI_FALLBACK_HINT_NAV_MISSING = "Navigate() ativo, mas a secao PAGES esta ausente.",
	UI_FALLBACK_HINT_UI_PAGES_MISSING = "Extensao UI_Pages ausente.",
	UI_CMD_OPEN_HELP = "Abre a UI do GMS (/gms ui [page])",

	LOGS_HEADER_TITLE = "Console de logs",
	LOGS_LEVELS = "Niveis:",
	LOGS_SELECT_FMT = "Selecao (%d/5)",
	LOGS_SELECT_ALL = "Selecionar tudo",
	LOGS_SELECT_NONE = "Desmarcar tudo",
	LOGS_REFRESH = "Atualizar",
	LOGS_CLEAR = "Limpar",
	LOGS_COPY = "Copiar (2000)",
	LOGS_DOCK_TOOLTIP = "Abrir logs",
	LOGS_SLASH_HELP = "/gms logs - abre a UI de logs",
	LOGS_SUB_FALLBACK_DESC = "Abre a UI de logs",

	ROSTER_SEARCH = "Buscar:",
	ROSTER_SHOW_OFFLINE = "Mostrar membros offline",
	ROSTER_EMPTY = "Nenhum membro da guilda encontrado.",
	ROSTER_STATUS_SEARCH = "|cffb8b8b8Roster:|r mostrando %d de %d (busca: %s)",
	ROSTER_STATUS_FILTERED = "|cffb8b8b8Roster:|r mostrando %d de %d",
	ROSTER_STATUS_TOTAL = "|cffb8b8b8Roster:|r %d membros",
	ROSTER_DOCK_TOOLTIP = "Abrir pagina de roster",
	ROSTER_CTX_WHISPER = "Sussurrar",
	ROSTER_CTX_COPY_NAME = "Copiar nome (com reino)",
	ROSTER_CTX_INVITE = "Convidar para o grupo",

	GA_PAGE_TITLE = "Registro da guilda",
	GA_HEADER_TITLE = "Registro da guilda",
	GA_HEADER_SUB = "Rastreia mudancas no roster da guilda em um log dedicado do modulo.",
	GA_CHAT_ECHO = "Publicar novas entradas no chat",
	GA_REFRESH = "Atualizar",
	GA_CLEAR = "Limpar",
	GA_EMPTY = "Ainda nao ha entradas de atividade da guilda.",
	GA_STATUS_FMT = "Registro da guilda: %d entradas",
	GA_BASELINE = "Snapshot inicial da guilda capturado (%d membros).",
	GA_DOCK_TOOLTIP = "Abrir registro de atividade da guilda",
	GA_SLASH_HELP = "/gms guildlog - abre o registro de atividade da guilda",

	GA_JOIN = "%s entrou na guilda.",
	GA_REJOIN = "%s voltou para a guilda.",
	GA_LEAVE = "%s saiu da guilda.",
	GA_PROMOTE = "%s promovido (%s -> %s).",
	GA_DEMOTE = "%s rebaixado (%s -> %s).",
	GA_NAME_CHANGED = "%s mudou o nome do personagem para %s.",
	GA_REALM_CHANGED = "%s mudou de reino de %s para %s.",
	GA_FACTION_CHANGED = "%s mudou de faccao de %s para %s.",
	GA_RACE_CHANGED = "%s mudou de raca de %s para %s.",
	GA_LEVEL_CHANGED = "%s mudou de nivel de %d para %d.",
	GA_ONLINE = "%s esta online agora.",
	GA_OFFLINE = "%s ficou offline.",
	GA_NOTE_CHANGED = "%s atualizou a nota publica.",
	GA_OFFICER_NOTE_CHANGED = "%s atualizou a nota de oficial.",
	GA_NOTE_CHANGED_DETAIL = "%s atualizou a nota publica (%s -> %s).",
	GA_OFFICER_NOTE_CHANGED_DETAIL = "%s atualizou a nota de oficial (%s -> %s).",
})
