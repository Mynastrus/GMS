-- ============================================================================
--	GMS/Locales/ruRU.lua
--	Russian locale
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

if type(GMS.RegisterLocale) ~= "function" then return end

GMS:RegisterLocale("ruRU", {
	CORE_STARTUP_LOADED = "Аддон загружен: Guild Management System v%s",
	CORE_STARTUP_HINT = "Используйте %s, чтобы открыть главное окно, и %s для справки.",

	SLASH_DISPLAY_NAME = "Ввод чата",
	SLASH_HELP_USAGE = "Использование: /gms <подкоманда> [аргументы]",
	SLASH_HELP_EXAMPLE = "Пример: /gms help",
	SLASH_HELP_NONE = "Подкоманды не зарегистрированы.",
	SLASH_UNKNOWN_SUBCOMMAND = "Неизвестная подкоманда: %s",
	SLASH_HELP_RELOAD = "Перезагружает интерфейс.",

	UI_STATUS_READY = "Статус: готово",
	UI_HEADER_SUB_VERSION = "Версия: |cffCCCCCC%s|r",
	UI_HEADER_SUB_ACTIVE = "Расширение UI активно",
	UI_FALLBACK_TITLE = "|cff03A9F4GMS|r - UI загружен.",
	UI_FALLBACK_HINT_PAGES_INACTIVE = "Система страниц не активна (или удалена).",
	UI_RESET_WINDOW = "Сбросить окно (позиция/размер)",
	UI_FALLBACK_HINT_NAV_MISSING = "Navigate() активна, но раздел PAGES отсутствует.",
	UI_FALLBACK_HINT_UI_PAGES_MISSING = "Расширение UI_Pages отсутствует.",
	UI_CMD_OPEN_HELP = "Открывает UI GMS (/gms ui [page])",

	LOGS_HEADER_TITLE = "Консоль логов",
	LOGS_LEVELS = "Уровни:",
	LOGS_SELECT_FMT = "Выбор (%d/5)",
	LOGS_SELECT_ALL = "Выбрать все",
	LOGS_SELECT_NONE = "Снять выбор",
	LOGS_REFRESH = "Обновить",
	LOGS_CLEAR = "Очистить",
	LOGS_COPY = "Копировать (2000)",
	LOGS_DOCK_TOOLTIP = "Открыть логи",
	LOGS_SLASH_HELP = "/gms logs - открывает UI логов",
	LOGS_SUB_FALLBACK_DESC = "Открывает UI логов",

	ROSTER_SEARCH = "Поиск:",
	ROSTER_SHOW_OFFLINE = "Показывать офлайн участников",
	ROSTER_EMPTY = "Участники гильдии не найдены.",
	ROSTER_STATUS_SEARCH = "|cffb8b8b8Состав:|r показано %d из %d (поиск: %s)",
	ROSTER_STATUS_FILTERED = "|cffb8b8b8Состав:|r показано %d из %d",
	ROSTER_STATUS_TOTAL = "|cffb8b8b8Состав:|r %d участников",
	ROSTER_DOCK_TOOLTIP = "Открыть страницу состава",
	ROSTER_CTX_WHISPER = "Шепот",
	ROSTER_CTX_COPY_NAME = "Копировать имя (с миром)",
	ROSTER_CTX_INVITE = "Пригласить в группу",

	GA_PAGE_TITLE = "Журнал гильдии",
	GA_HEADER_TITLE = "Журнал гильдии",
	GA_HEADER_SUB = "Отслеживает изменения состава гильдии в отдельном журнале модуля.",
	GA_CHAT_ECHO = "Писать новые записи в чат",
	GA_REFRESH = "Обновить",
	GA_CLEAR = "Очистить",
	GA_EMPTY = "Пока нет записей активности гильдии.",
	GA_STATUS_FMT = "Журнал гильдии: %d записей",
	GA_BASELINE = "Зафиксирован начальный снимок гильдии (%d участников).",
	GA_DOCK_TOOLTIP = "Открыть журнал активности гильдии",
	GA_SLASH_HELP = "/gms guildlog - открывает журнал активности гильдии",

	GA_JOIN = "%s вступил в гильдию.",
	GA_REJOIN = "%s вернулся в гильдию.",
	GA_LEAVE = "%s покинул гильдию.",
	GA_PROMOTE = "%s повышен (%s -> %s).",
	GA_DEMOTE = "%s понижен (%s -> %s).",
	GA_NAME_CHANGED = "%s изменил имя персонажа на %s.",
	GA_REALM_CHANGED = "%s сменил мир с %s на %s.",
	GA_FACTION_CHANGED = "%s сменил фракцию с %s на %s.",
	GA_RACE_CHANGED = "%s сменил расу с %s на %s.",
	GA_LEVEL_CHANGED = "%s сменил уровень с %d на %d.",
	GA_ONLINE = "%s теперь онлайн.",
	GA_OFFLINE = "%s ушел офлайн.",
	GA_NOTE_CHANGED = "%s обновил публичную заметку.",
	GA_OFFICER_NOTE_CHANGED = "%s обновил офицерскую заметку.",
	GA_NOTE_CHANGED_DETAIL = "%s обновил публичную заметку (%s -> %s).",
	GA_OFFICER_NOTE_CHANGED_DETAIL = "%s обновил офицерскую заметку (%s -> %s).",
})
