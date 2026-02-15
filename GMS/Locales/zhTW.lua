-- ============================================================================
--	GMS/Locales/zhTW.lua
--	Chinese (Traditional) locale
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

if type(GMS.RegisterLocale) ~= "function" then return end

GMS:RegisterLocale("zhTW", {
	CORE_STARTUP_LOADED = "插件已載入: Guild Management System v%s",
	CORE_STARTUP_HINT = "使用 %s 開啟主視窗，使用 %s 查看說明。",

	SLASH_DISPLAY_NAME = "聊天輸入",
	SLASH_HELP_USAGE = "用法: /gms <subcommand> [args]",
	SLASH_HELP_EXAMPLE = "範例: /gms help",
	SLASH_HELP_NONE = "沒有已註冊的子命令。",
	SLASH_UNKNOWN_SUBCOMMAND = "未知子命令: %s",
	SLASH_HELP_RELOAD = "重新載入介面。",

	UI_STATUS_READY = "狀態: 就緒",
	UI_HEADER_SUB_VERSION = "版本: |cffCCCCCC%s|r",
	UI_HEADER_SUB_ACTIVE = "UI 擴充已啟用",
	UI_FALLBACK_TITLE = "|cff03A9F4GMS|r - UI 已載入。",
	UI_FALLBACK_HINT_PAGES_INACTIVE = "頁面系統未啟用（或已移除）。",
	UI_RESET_WINDOW = "重設視窗（位置/大小）",
	UI_FALLBACK_HINT_NAV_MISSING = "Navigate() 已啟用，但缺少 PAGES 區塊。",
	UI_FALLBACK_HINT_UI_PAGES_MISSING = "缺少 UI_Pages 擴充。",
	UI_CMD_OPEN_HELP = "開啟 GMS UI (/gms ui [page])",

	LOGS_HEADER_TITLE = "日誌主控台",
	LOGS_LEVELS = "等級:",
	LOGS_SELECT_FMT = "選擇 (%d/5)",
	LOGS_SELECT_ALL = "全選",
	LOGS_SELECT_NONE = "全不選",
	LOGS_REFRESH = "重新整理",
	LOGS_CLEAR = "清空",
	LOGS_COPY = "複製 (2000)",
	LOGS_DOCK_TOOLTIP = "開啟日誌",
	LOGS_SLASH_HELP = "/gms logs - 開啟日誌 UI",
	LOGS_SUB_FALLBACK_DESC = "開啟日誌 UI",

	ROSTER_SEARCH = "搜尋:",
	ROSTER_SHOW_OFFLINE = "顯示離線成員",
	ROSTER_EMPTY = "找不到公會成員。",
	ROSTER_STATUS_SEARCH = "|cffb8b8b8Roster:|r 顯示 %d / %d (搜尋: %s)",
	ROSTER_STATUS_FILTERED = "|cffb8b8b8Roster:|r 顯示 %d / %d",
	ROSTER_STATUS_TOTAL = "|cffb8b8b8Roster:|r %d 名成員",
	ROSTER_DOCK_TOOLTIP = "開啟名冊頁面",
	ROSTER_CTX_WHISPER = "密語",
	ROSTER_CTX_COPY_NAME = "複製名稱（含伺服器）",
	ROSTER_CTX_INVITE = "邀請進隊伍",

	GA_PAGE_TITLE = "公會日誌",
	GA_HEADER_TITLE = "公會日誌",
	GA_HEADER_SUB = "在專用模組日誌中追蹤公會名冊變更。",
	GA_CHAT_ECHO = "在聊天中顯示新條目",
	GA_REFRESH = "重新整理",
	GA_CLEAR = "清空",
	GA_EMPTY = "目前沒有公會活動紀錄。",
	GA_STATUS_FMT = "公會日誌: %d 筆紀錄",
	GA_BASELINE = "已建立初始公會快照（%d 名成員）。",
	GA_DOCK_TOOLTIP = "開啟公會活動日誌",
	GA_SLASH_HELP = "/gms guildlog - 開啟公會活動日誌",

	GA_JOIN = "%s 加入了公會。",
	GA_REJOIN = "%s 重新加入了公會。",
	GA_LEAVE = "%s 離開了公會。",
	GA_PROMOTE = "%s 已晉升 (%s -> %s)。",
	GA_DEMOTE = "%s 已降階 (%s -> %s)。",
	GA_NAME_CHANGED = "%s 將角色名稱改為 %s。",
	GA_REALM_CHANGED = "%s 將伺服器從 %s 改為 %s。",
	GA_FACTION_CHANGED = "%s 將陣營從 %s 改為 %s。",
	GA_RACE_CHANGED = "%s 將種族從 %s 改為 %s。",
	GA_LEVEL_CHANGED = "%s 的等級由 %d 變為 %d。",
	GA_ONLINE = "%s 現在上線。",
	GA_OFFLINE = "%s 已離線。",
	GA_NOTE_CHANGED = "%s 更新了公開備註。",
	GA_OFFICER_NOTE_CHANGED = "%s 更新了幹部備註。",
	GA_NOTE_CHANGED_DETAIL = "%s 更新了公開備註 (%s -> %s)。",
	GA_OFFICER_NOTE_CHANGED_DETAIL = "%s 更新了幹部備註 (%s -> %s)。",
})
