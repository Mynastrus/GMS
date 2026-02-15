-- ============================================================================
--	GMS/Locales/koKR.lua
--	Korean locale
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

if type(GMS.RegisterLocale) ~= "function" then return end

GMS:RegisterLocale("koKR", {
	CORE_STARTUP_LOADED = "애드온 로드됨: Guild Management System v%s",
	CORE_STARTUP_HINT = "%s 로 메인 창을 열고 %s 로 도움말을 확인하세요.",

	SLASH_DISPLAY_NAME = "채팅 입력",
	SLASH_HELP_USAGE = "사용법: /gms <subcommand> [args]",
	SLASH_HELP_EXAMPLE = "예시: /gms help",
	SLASH_HELP_NONE = "등록된 하위 명령이 없습니다.",
	SLASH_UNKNOWN_SUBCOMMAND = "알 수 없는 하위 명령: %s",
	SLASH_HELP_RELOAD = "UI를 다시 불러옵니다.",

	UI_STATUS_READY = "상태: 준비됨",
	UI_HEADER_SUB_VERSION = "버전: |cffCCCCCC%s|r",
	UI_HEADER_SUB_ACTIVE = "UI 확장 활성화됨",
	UI_FALLBACK_TITLE = "|cff03A9F4GMS|r - UI가 로드되었습니다.",
	UI_FALLBACK_HINT_PAGES_INACTIVE = "페이지 시스템이 비활성 상태입니다(또는 제거됨).",
	UI_RESET_WINDOW = "창 초기화 (위치/크기)",
	UI_FALLBACK_HINT_NAV_MISSING = "Navigate()는 활성화되어 있지만 PAGES 섹션이 없습니다.",
	UI_FALLBACK_HINT_UI_PAGES_MISSING = "UI_Pages 확장이 없습니다.",
	UI_CMD_OPEN_HELP = "GMS UI를 엽니다 (/gms ui [page])",

	LOGS_HEADER_TITLE = "로그 콘솔",
	LOGS_LEVELS = "레벨:",
	LOGS_SELECT_FMT = "선택 (%d/5)",
	LOGS_SELECT_ALL = "모두 선택",
	LOGS_SELECT_NONE = "모두 해제",
	LOGS_REFRESH = "새로고침",
	LOGS_CLEAR = "지우기",
	LOGS_COPY = "복사 (2000)",
	LOGS_DOCK_TOOLTIP = "로그 열기",
	LOGS_SLASH_HELP = "/gms logs - 로그 UI를 엽니다",
	LOGS_SUB_FALLBACK_DESC = "로그 UI를 엽니다",

	ROSTER_SEARCH = "검색:",
	ROSTER_SHOW_OFFLINE = "오프라인 멤버 표시",
	ROSTER_EMPTY = "길드원을 찾을 수 없습니다.",
	ROSTER_STATUS_SEARCH = "|cffb8b8b8Roster:|r %d / %d 표시 중 (검색: %s)",
	ROSTER_STATUS_FILTERED = "|cffb8b8b8Roster:|r %d / %d 표시 중",
	ROSTER_STATUS_TOTAL = "|cffb8b8b8Roster:|r 멤버 %d명",
	ROSTER_DOCK_TOOLTIP = "명단 페이지 열기",
	ROSTER_CTX_WHISPER = "귓속말",
	ROSTER_CTX_COPY_NAME = "이름 복사 (서버 포함)",
	ROSTER_CTX_INVITE = "파티 초대",

	GA_PAGE_TITLE = "길드 로그",
	GA_HEADER_TITLE = "길드 로그",
	GA_HEADER_SUB = "길드 명단 변경 사항을 전용 모듈 로그에 기록합니다.",
	GA_CHAT_ECHO = "새 항목을 채팅에 출력",
	GA_REFRESH = "새로고침",
	GA_CLEAR = "지우기",
	GA_EMPTY = "아직 길드 활동 기록이 없습니다.",
	GA_STATUS_FMT = "길드 로그: 항목 %d개",
	GA_BASELINE = "초기 길드 스냅샷을 저장했습니다 (%d명).",
	GA_DOCK_TOOLTIP = "길드 활동 로그 열기",
	GA_SLASH_HELP = "/gms guildlog - 길드 활동 로그를 엽니다",

	GA_JOIN = "%s 님이 길드에 가입했습니다.",
	GA_REJOIN = "%s 님이 길드에 다시 가입했습니다.",
	GA_LEAVE = "%s 님이 길드를 떠났습니다.",
	GA_PROMOTE = "%s 승급 (%s -> %s).",
	GA_DEMOTE = "%s 강등 (%s -> %s).",
	GA_NAME_CHANGED = "%s 님이 캐릭터 이름을 %s(으)로 변경했습니다.",
	GA_REALM_CHANGED = "%s 님이 서버를 %s에서 %s(으)로 변경했습니다.",
	GA_FACTION_CHANGED = "%s 님이 진영을 %s에서 %s(으)로 변경했습니다.",
	GA_RACE_CHANGED = "%s 님이 종족을 %s에서 %s(으)로 변경했습니다.",
	GA_LEVEL_CHANGED = "%s 님의 레벨이 %d에서 %d(으)로 변경되었습니다.",
	GA_ONLINE = "%s 님이 접속했습니다.",
	GA_OFFLINE = "%s 님이 접속 종료했습니다.",
	GA_NOTE_CHANGED = "%s 님이 공개 메모를 수정했습니다.",
	GA_OFFICER_NOTE_CHANGED = "%s 님이 관리자 메모를 수정했습니다.",
	GA_NOTE_CHANGED_DETAIL = "%s 님이 공개 메모를 수정했습니다 (%s -> %s).",
	GA_OFFICER_NOTE_CHANGED_DETAIL = "%s 님이 관리자 메모를 수정했습니다 (%s -> %s).",
})
