-- ============================================================================
--	GMS/Core/Logs.lua
--	LOGS EXTENSION (no GMS:NewModule)
--	- Ingest: Ã¼bernimmt EintrÃ¤ge aus GMS._LOG_BUFFER in eigenen Ringbuffer
--	- Ringbuffer persistiert via AceDB (falls verfÃ¼gbar), sonst in-memory
--	- Notify Hook: LOCAL_LOG schreibt Buffer (SoT) + optional _LOG_NOTIFY(entry, idx)
--	  Logs.lua installiert _LOG_NOTIFY und ingested gebatched
--	- UI Page (AceGUI) + Live-Update (Notify + optional Ticker)
--	- Slash: /gms logs -> Ã¶ffnet LOGS Page
--	- UI Integration: kompatibel mit GMS.UI:RegisterPage(id, order, title, buildFn)
--	- RightDock: nutzt GMS.UI:AddRightDockIconBottom(...)
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G                 = _G
local GetTime            = GetTime
local date               = date
local type               = type
local tostring           = tostring
local select             = select
local pairs              = pairs
local rawget             = rawget
local pcall              = pcall
local print              = print
local ipairs             = ipairs
local C_Timer            = C_Timer
local table              = table
local tonumber           = tonumber
local CreateFrame        = CreateFrame
local UIParent           = UIParent
local EasyMenu           = EasyMenu
local UIDropDownMenu_Initialize = UIDropDownMenu_Initialize
local UIDropDownMenu_CreateInfo = UIDropDownMenu_CreateInfo
local UIDropDownMenu_AddButton  = UIDropDownMenu_AddButton
local ToggleDropDownMenu        = ToggleDropDownMenu
local ChatFrame_OpenChat = ChatFrame_OpenChat
---@diagnostic enable: undefined-global

-- ###########################################################################
-- #	METADATA (PROJECT STANDARD - REQUIRED)
-- ###########################################################################

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "LOGS",
	SHORT_NAME   = "Logs",
	DISPLAY_NAME = "Logging Console",
	VERSION      = "1.1.20",
}

-- ###########################################################################
-- #	PROJECT STANDARD: GLOBAL LOG BUFFER + LOCAL_LOG()
-- #	ORDER FIX: Buffer first, then Notify(entry, idx)
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return GetTime and GetTime() or nil
end

-- Local-only logger for this file
local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time   = now(),
		level  = tostring(level or "INFO"),
		type   = tostring(METADATA.TYPE),
		source = tostring(METADATA.SHORT_NAME),
		msg    = tostring(msg or ""),
	}

	local n = select("#", ...)
	if n > 0 then
		entry.data = {}
		for i = 1, n do
			entry.data[i] = select(i, ...)
		end
	end

	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		GMS._LOG_NOTIFY(entry, idx)
	end
end

-- ###########################################################################

GMS:RegisterExtension({
	key = "LOGS",
	name = "LOGS",
	displayName = "Logs",
	version = METADATA.VERSION,
	desc = "Logging + UI page (ingest global log buffer)",
})

-- Prevent double-load
if GMS.LOGS then return end

local AceDB = LibStub("AceDB-3.0", true)
local AceGUI = LibStub("AceGUI-3.0", true) -- optional

local LOGS = {}
GMS.LOGS = LOGS

-- ###########################################################################
-- #	CONSTS / DEFAULTS
-- ###########################################################################

LOGS.LEVELS = { TRACE = 1, DEBUG = 2, INFO = 3, WARN = 4, ERROR = 5 }
LOGS.LEVEL_NAMES = { [1] = "TRACE", [2] = "DEBUG", [3] = "INFO", [4] = "WARN", [5] = "ERROR" }

-- Registry Defaults (zentral verwaltet via GMS:RegisterModuleOptions)
local REG_DEFAULTS = {
	maxEntries = 400,
	logTRACE   = false,
	logDEBUG   = false,
	logINFO    = true,
	logWARN    = true,
	logERROR   = true,
	viewTRACE  = false,
	viewDEBUG  = false,
	viewINFO   = true,
	viewWARN   = true,
	viewERROR  = true,
}

local COLORS = {
	TRACE = "|cff9d9d9d",
	DEBUG = "|cff4da6ff",
	INFO  = "|cff4dff88",
	WARN  = "|cffffd24d",
	ERROR = "|cffff4d4d",
}

LOGS._db = nil
LOGS._entries = nil
LOGS._ui = nil

LOGS._uiRegistered = false
LOGS._dockRegistered = false
LOGS._slashRegistered = false

LOGS._ticker = nil

-- Notify batching (avoid ingest per log line)
LOGS._notifyPending = false
LOGS._notifyScheduled = false

-- ###########################################################################
-- #	HELPERS
-- ###########################################################################

local function clamp(n, lo, hi)
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

local function toLevel(level)
	if type(level) == "number" then return clamp(level, 1, 5) end
	if type(level) == "string" then return LOGS.LEVELS[level:upper()] or LOGS.LEVELS.INFO end
	return LOGS.LEVELS.INFO
end

local function levelName(n)
	return LOGS.LEVEL_NAMES[n] or "INFO"
end

local VIEW_LEVEL_KEYS = { "TRACE", "DEBUG", "INFO", "WARN", "ERROR" }
local VIEW_LEVEL_DEFAULTS = {
	TRACE = false,
	DEBUG = false,
	INFO = true,
	WARN = true,
	ERROR = true,
}

local function ensureViewLevelFilter(p)
	local hasAny = false
	for i = 1, #VIEW_LEVEL_KEYS do
		local key = VIEW_LEVEL_KEYS[i]
		if p["view" .. key] ~= nil then
			hasAny = true
			break
		end
	end

	if not hasAny then
		local legacyMin = tonumber(p.minLevel)
		if legacyMin then
			for i = 1, #VIEW_LEVEL_KEYS do
				local key = VIEW_LEVEL_KEYS[i]
				p["view" .. key] = (i >= legacyMin)
			end
		else
			for i = 1, #VIEW_LEVEL_KEYS do
				local key = VIEW_LEVEL_KEYS[i]
				p["view" .. key] = VIEW_LEVEL_DEFAULTS[key]
			end
		end
	else
		for i = 1, #VIEW_LEVEL_KEYS do
			local key = VIEW_LEVEL_KEYS[i]
			if p["view" .. key] == nil then
				p["view" .. key] = VIEW_LEVEL_DEFAULTS[key]
			end
		end
	end
end

local function nowReadable(fmt)
	if type(date) == "function" then
		return date(fmt or "%Y-%m-%d %H:%M:%S")
	end
	return ""
end

local function profile()
	local p = GMS:GetModuleOptions("LOGS") or REG_DEFAULTS
	ensureViewLevelFilter(p)
	return p
end

local function isLevelVisible(levelOrName)
	local p = profile()
	local name = nil
	if type(levelOrName) == "number" then
		name = levelName(levelOrName)
	elseif type(levelOrName) == "string" then
		name = tostring(levelOrName):upper()
	end
	if not name or name == "" then
		return true
	end
	return p["view" .. name] == true
end

local function isEntryVisible(entry)
	if type(entry) ~= "table" then return false end
	local msg = tostring(entry.msg or "")
	msg = msg:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "" then
		return false
	end
	local lvl = entry.levelNum
	if type(lvl) ~= "number" then
		lvl = toLevel(entry.level)
	end
	return isLevelVisible(lvl)
end

local function setAllVisibleLevels(flag)
	local p = profile()
	local v = flag and true or false
	for i = 1, #VIEW_LEVEL_KEYS do
		local key = VIEW_LEVEL_KEYS[i]
		p["view" .. key] = v
	end
end

local function countVisibleLevels()
	local count = 0
	for i = 1, #VIEW_LEVEL_KEYS do
		if isLevelVisible(VIEW_LEVEL_KEYS[i]) then
			count = count + 1
		end
	end
	return count
end

local function allowForOutput(levelNum)
	local name = levelName(levelNum)
	return profile()["log" .. name] == true
end

local function chatPrint(msg)
	if type(GMS.Printf) == "function" then
		GMS:Printf("%s", msg)
	elseif type(GMS.Print) == "function" then
		GMS:Print(msg)
	else
		print(msg)
	end
end

-- JSON-ish / readable stringify (safe, bounded)
local function _escapeStr(s)
	s = tostring(s)
	s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
	return "\"" .. s .. "\""
end

local function _isArray(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" then return false end
		n = n + 1
	end
	for i = 1, n do
		if rawget(t, i) == nil then return false end
	end
	return true
end

local function _jsonish(v, seen, depth, maxDepth, maxItems)
	local tv = type(v)
	if tv == "nil" then return "null" end
	if tv == "number" then return tostring(v) end
	if tv == "boolean" then return v and "true" or "false" end
	if tv == "string" then return _escapeStr(v) end
	if tv == "function" then return "\"<function>\"" end
	if tv == "userdata" then return "\"<userdata>\"" end
	if tv == "thread" then return "\"<thread>\"" end
	if tv ~= "table" then return _escapeStr(tostring(v)) end

	if seen[v] then return "\"<cycle>\"" end
	seen[v] = true

	if depth >= maxDepth then
		seen[v] = nil
		return "\"<maxDepth>\""
	end

	local out = {}
	local count = 0

	if _isArray(v) then
		out[#out + 1] = "["
		for i = 1, #v do
			count = count + 1
			if count > maxItems then
				out[#out + 1] = "\"<truncated>\""
				break
			end
			if i > 1 then out[#out + 1] = "," end
			out[#out + 1] = _jsonish(v[i], seen, depth + 1, maxDepth, maxItems)
		end
		out[#out + 1] = "]"
	else
		out[#out + 1] = "{"
		local first = true
		for k, val in pairs(v) do
			count = count + 1
			if count > maxItems then
				if not first then out[#out + 1] = "," end
				out[#out + 1] = _escapeStr("<truncated>") .. ":" .. _escapeStr("true")
				break
			end
			if not first then out[#out + 1] = "," end
			first = false
			local kk = _escapeStr(type(k) == "string" and k or tostring(k))
			out[#out + 1] = kk .. ":" .. _jsonish(val, seen, depth + 1, maxDepth, maxItems)
		end
		out[#out + 1] = "}"
	end

	seen[v] = nil
	return table.concat(out, "")
end

local function dataSuffixFromData(data)
	if type(data) ~= "table" or #data == 0 then return "" end
	local parts = {}
	for i = 1, #data do
		local v = data[i]
		if type(v) == "table" then
			parts[#parts + 1] = _jsonish(v, {}, 0, 4, 80)
		else
			parts[#parts + 1] = tostring(v)
		end
	end
	return " | data=" .. table.concat(parts, " ")
end

local function trimToMax()
	local prof = profile()
	local max = clamp(tonumber(prof.maxEntries) or 400, 50, 5000)

	local entries = LOGS._entries
	if not entries then return end

	while #entries > max do
		table.remove(entries, 1)
	end
end

-- ###########################################################################
-- #	INGEST: GLOBAL BUFFER -> PERSISTED RINGBUFFER
-- ###########################################################################

local function _mapGlobalEntry(e)
	local lvl = toLevel(e.level)

	local srcType = tostring(e.type or "")
	local srcName = tostring(e.source or "")

	local base = tostring(e.msg or "")
	local suffix = dataSuffixFromData(e.data)
	local msg = base .. suffix

	return {
		time     = nowReadable(profile().timestampFormat or "%Y-%m-%d %H:%M:%S"),
		levelNum = lvl,
		level    = levelName(lvl),

		type   = srcType,
		source = srcName,

		msg = msg,

		-- optional: raw timing from GetTime()
		t = e.time,
	}
end

function LOGS:IngestGlobalBuffer()
	local buf = GMS._LOG_BUFFER
	if type(buf) ~= "table" then return 0 end

	local ldb = GMS.logging_db
	if not ldb then return 0 end

	local start = (ldb.profile.ingestPos or 0) + 1
	local last = #buf
	if start > last then return 0 end

	local entries = LOGS._entries
	if not entries then
		LOGS._entries = ldb.char.logs
		entries = LOGS._entries
	end

	local added = 0
	local prof = profile()
	for i = start, last do
		local e = buf[i]
		if type(e) == "table" then
			local mapped = _mapGlobalEntry(e)
			if prof["log" .. mapped.level] then
				entries[#entries + 1] = mapped
				added = added + 1
			end
		end
	end

	ldb.profile.ingestPos = last
	trimToMax()
	return added
end

-- ###########################################################################
-- #	NOTIFY HOOK (batched ingest + optional live UI prepend)
-- ###########################################################################

local function _scheduleNotifyIngest()
	if LOGS._notifyScheduled then
		LOGS._notifyPending = true
		return
	end

	LOGS._notifyScheduled = true
	LOGS._notifyPending = false

	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(0, function()
			LOGS._notifyScheduled = false

			local added = LOGS:IngestGlobalBuffer()
			if added <= 0 then return end

			-- live UI: prepend only newly ingested entries (cheap)
			if LOGS._ui and LOGS._ui.prependEntry then
				local entries = LOGS._entries or {}
				for i = #entries - added + 1, #entries do
					local e = entries[i]
					if e and isEntryVisible(e) then
						pcall(LOGS._ui.prependEntry, e)
					end
				end
			end

			-- if more logs came in during schedule window, run once again
			if LOGS._notifyPending then
				_scheduleNotifyIngest()
			end
		end)
	else
		LOGS._notifyScheduled = false
		LOGS:IngestGlobalBuffer()
	end
end

-- Install notify handler: called by EVERY file's LOCAL_LOG after writing to buffer
GMS._LOG_NOTIFY = function(_entry, _idx)
	_scheduleNotifyIngest()
end

-- ###########################################################################
-- #	INIT / DB
-- ###########################################################################

function LOGS:Init()
	-- Register options in main GMS_DB
	GMS:RegisterModuleOptions("LOGS", REG_DEFAULTS, "PROFILE")

	-- Use GMS_Logging_DB for character-specific log data
	if GMS.logging_db then
		LOGS._db = GMS.logging_db
		-- Reference directly, DO NOT re-assign the table to the proxy
		LOGS._entries = GMS.logging_db.char.logs

		-- Ensure ingestPos is valid
		GMS.logging_db.profile.ingestPos = tonumber(GMS.logging_db.profile.ingestPos) or 0

		trimToMax()
		LOCAL_LOG("INFO", "Logging initialized (GMS_Logging_DB char-scoped)")
	else
		LOCAL_LOG("WARN", "GMS.logging_db not available; fallback to in-memory only")
		LOGS._entries = LOGS._entries or {}
	end
end

-- PUBLIC CONFIG
function GMS:Logs_SetLevel(level)
	local lvl = toLevel(level)
	local p = profile()
	p.minLevel = lvl
	for i = 1, #VIEW_LEVEL_KEYS do
		local key = VIEW_LEVEL_KEYS[i]
		p["view" .. key] = (i >= lvl)
	end
end

function GMS:Logs_GetLevel()
	local p = profile()
	if p.minLevel then
		return p.minLevel
	end
	for i = 1, #VIEW_LEVEL_KEYS do
		if p["view" .. VIEW_LEVEL_KEYS[i]] == true then
			return i
		end
	end
	return LOGS.LEVELS.INFO
end

function GMS:Logs_EnableChat(v) profile().chat = not not v end

function GMS:Logs_IsChatEnabled() return not not profile().chat end

function GMS:Logs_SetMaxEntries(n) profile().maxEntries = clamp(tonumber(n) or 400, 50, 5000); trimToMax() end

function GMS:Logs_GetMaxEntries() return profile().maxEntries end

function GMS:Logs_Clear()
	local p = profile()
	p.entries = {}
	LOGS._entries = p.entries
	if LOGS._db then LOGS._db.profile.entries = LOGS._entries end

	-- optional: ingest cursor bleibt (damit wir nicht alles erneut reinziehen)
	if LOGS._ui and LOGS._ui.scroller then
		pcall(function() LOGS._ui.scroller:ReleaseChildren() end)
	end
	LOCAL_LOG("INFO", "Logs cleared")
end

function GMS:Logs_GetEntries(n, minLevel)
	local entries = LOGS._entries or {}
	local want = tonumber(n) or #entries
	if want < 1 then want = 1 end
	if want > #entries then want = #entries end
	local lvl = minLevel and toLevel(minLevel) or 1
	local out = {}
	for i = #entries, 1, -1 do
		if #out >= want then break end
		local e = entries[i]
		if e and (e.levelNum or 1) >= lvl then out[#out + 1] = e end
	end
	return out
end

-- ###########################################################################
-- #	OPTIONAL: LEGACY API (kept)
-- #	GMS:LOG(level, module, msg, ...)
-- #	-> schreibt in den Buffer (SoT) + notify
-- ###########################################################################

function GMS:LOG(level, module, msg, ...)
	GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

	local entry = {
		time   = now(),
		level  = tostring(level or "INFO"),
		type   = "CORE",
		source = tostring(module or "GMS"),
		msg    = tostring(msg or ""),
	}

	local n = select("#", ...)
	if n > 0 then
		entry.data = {}
		for i = 1, n do
			entry.data[i] = select(i, ...)
		end
	end

	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		GMS._LOG_NOTIFY(entry, idx)
	end
end

-- ###########################################################################
-- #	UI BRIDGE (match GMS/Core/UI.lua API)
-- ###########################################################################

local function UI_Open(name)
	if type(GMS.UI_Open) == "function" then return GMS:UI_Open(name) end
	if GMS.UI and type(GMS.UI.Open) == "function" then return GMS.UI:Open(name) end
	if GMS.UI and type(GMS.UI.Navigate) == "function" then
		GMS.UI:Show()
		return GMS.UI:Navigate(name)
	end
end

local function UI_RegisterPage_Compat(pageId, order, title, buildFn)
	if not (GMS.UI and type(GMS.UI.RegisterPage) == "function") then return false end
	return GMS.UI:RegisterPage(pageId, order, title, buildFn) == true
end

local function UI_RegisterDockIcon_Compat(pageId, title)
	if not (GMS.UI and (type(GMS.UI.AddRightDockIconBottom) == "function" or type(GMS.UI.AddRightDockIconTop) == "function")) then return false end
	local addIcon = GMS.UI.AddRightDockIconBottom or GMS.UI.AddRightDockIconTop
	addIcon(GMS.UI, {
		id = pageId,
		order = 90,
		selectable = true,
		icon = "Interface\\Icons\\INV_Misc_Note_05",
		tooltipTitle = title or pageId,
		tooltipText = (type(GMS.T) == "function" and GMS:T("LOGS_DOCK_TOOLTIP")) or "Open logs",
		onClick = function()
			if GMS.UI and type(GMS.UI.Navigate) == "function" then
				GMS.UI:Navigate(pageId)
			else
				UI_Open(pageId)
			end
		end,
	})
	return true
end

-- ###########################################################################
-- #	UI PAGE
-- ###########################################################################

local function BuildLogRow(entry, totalWidth)
	local function OneLine(text)
		local s = tostring(text or "")
		s = s:gsub("[\r\n]+", " ")
		s = s:gsub("%s%s+", " ")
		return s:gsub("^%s+", ""):gsub("%s+$", "")
	end

	local available = tonumber(totalWidth) or 900
	if available < 520 then available = 520 end

	-- Keep headroom for group/frame padding + spacing so Flow does not wrap.
	local inner = available - 56
	if inner < 420 then inner = 420 end

	local COL_TIME = 126
	local COL_LEVEL = 56
	local COL_SOURCE = math.floor(inner * 0.22)
	if COL_SOURCE < 110 then COL_SOURCE = 110 end
	if COL_SOURCE > 190 then COL_SOURCE = 190 end

	local msgWidth = inner - (COL_TIME + COL_LEVEL + COL_SOURCE)
	if msgWidth < 220 then
		local deficit = 220 - msgWidth
		COL_SOURCE = math.max(90, COL_SOURCE - deficit)
		msgWidth = inner - (COL_TIME + COL_LEVEL + COL_SOURCE)
	end
	if msgWidth < 180 then
		local deficit = 180 - msgWidth
		COL_TIME = math.max(108, COL_TIME - deficit)
		msgWidth = inner - (COL_TIME + COL_LEVEL + COL_SOURCE)
	end
	if msgWidth < 140 then msgWidth = 140 end

	local grp = AceGUI:Create("SimpleGroup")
	grp:SetFullWidth(true)
	grp:SetLayout("Flow")

	local color = COLORS[entry.level] or "|cffffffff"
	local timeText = OneLine(entry.time or "")
	local levelText = OneLine(entry.level or "INFO")
	local typeText = OneLine(entry.type or "-")
	local sourceText = OneLine(entry.source or "-")

	local function ResolveDisplayName(srcType, srcName)
		local t = tostring(srcType or "")
		local s = tostring(srcName or "")
		if s == "" then return "-" end

		local reg = nil
		if GMS and GMS.REGISTRY then
			if t == "EXT" then reg = GMS.REGISTRY.EXT end
			if t == "MOD" then reg = GMS.REGISTRY.MOD end
		end
		if type(reg) ~= "table" then
			return s
		end

		local su = s:upper()
		for _, meta in pairs(reg) do
			local key = tostring(meta.key or ""):upper()
			local name = tostring(meta.name or ""):upper()
			local display = tostring(meta.displayName or "")
			local displayU = display:upper()
			if su == key or su == name or su == displayU then
				return (display ~= "" and display) or s
			end
		end
		return s
	end

	local displayName = ResolveDisplayName(typeText, sourceText)

	local lTime = AceGUI:Create("Label")
	lTime:SetWidth(COL_TIME)
	lTime:SetText("|cffb0b0b0" .. timeText .. "|r")
	if lTime.label then
		lTime.label:SetWordWrap(false)
		lTime.label:SetMaxLines(1)
	end
	grp:AddChild(lTime)

	local lType = AceGUI:Create("Label")
	lType:SetWidth(COL_LEVEL)
	lType:SetText(color .. levelText .. "|r")
	if lType.label then
		lType.label:SetWordWrap(false)
		lType.label:SetMaxLines(1)
	end
	grp:AddChild(lType)

	local lSource = AceGUI:Create("Label")
	lSource:SetWidth(COL_SOURCE)
	lSource:SetText("|cff03A9F4" .. displayName .. "|r")
	if lSource.label then
		lSource.label:SetWordWrap(false)
		lSource.label:SetMaxLines(1)
	end
	grp:AddChild(lSource)

	local msg = OneLine(entry.msg or "")
	if msg ~= "" then
		local body = AceGUI:Create("Label")
		body:SetWidth(msgWidth)
		body:SetText("|cffd8d8d8" .. msg .. "|r")
		if body.label then
			body.label:SetWordWrap(false)
			body.label:SetMaxLines(1)
		end
		grp:AddChild(body)
	end

	return grp
end

local function RegisterLogsUI()
	if LOGS._uiRegistered then return true end
	if not AceGUI then
		LOCAL_LOG("WARN", "AceGUI not available; cannot register Logs UI page")
		return false
	end

	if not (GMS.UI and type(GMS.UI.RegisterPage) == "function") then
		return false
	end

	local PAGE_ID = "LOGS"
	local TITLE = "Logs"

	local function BuildLogsHeaderControls()
		if not (GMS.UI and type(GMS.UI.GetHeaderContent) == "function") then return end
		local header = GMS.UI:GetHeaderContent()
		if not header then return end
		if header.SetLayout then header:SetLayout("Flow") end

		local function TriggerRender()
			if LOGS._ui and type(LOGS._ui.renderAll) == "function" then
				LOGS._ui.renderAll()
			end
		end

		local title = AceGUI:Create("Label")
		title:SetText("|cff03A9F4" .. ((type(GMS.T) == "function" and GMS:T("LOGS_HEADER_TITLE")) or "Logging Console") .. "|r")
		title:SetWidth(160)
		header:AddChild(title)

		local levelLabel = AceGUI:Create("Label")
		levelLabel:SetText((type(GMS.T) == "function" and GMS:T("LOGS_LEVELS")) or "Levels:")
		levelLabel:SetWidth(46)
		header:AddChild(levelLabel)

		local levelBtn = AceGUI:Create("Button")
		levelBtn:SetWidth(160)
		local function UpdateLevelButtonText()
			local c = countVisibleLevels()
			levelBtn:SetText((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_FMT", c)) or string.format("Select (%d/5)", c))
		end
		local function ShowLevelMenu()
			if type(CreateFrame) ~= "function" then return end
			LOGS._levelMenuFrame = LOGS._levelMenuFrame or CreateFrame("Frame", "GMS_LOGS_LEVEL_MENU", UIParent, "UIDropDownMenuTemplate")
			if type(UIDropDownMenu_Initialize) == "function" and type(ToggleDropDownMenu) == "function" then
				UIDropDownMenu_Initialize(LOGS._levelMenuFrame, function(_, level)
					level = level or 1
					if level ~= 1 or type(UIDropDownMenu_AddButton) ~= "function" then return end

					local function AddEntry(text, notCheckable, checked, keepShownOnClick, func, disabled)
						local info = type(UIDropDownMenu_CreateInfo) == "function" and UIDropDownMenu_CreateInfo() or {}
						info.text = text
						info.notCheckable = notCheckable and true or false
						info.checked = checked
						info.keepShownOnClick = keepShownOnClick and true or false
						info.isNotRadio = true
						info.func = func
						info.disabled = disabled and true or false
						UIDropDownMenu_AddButton(info, level)
					end

					AddEntry((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_ALL")) or "Select All", true, false, false, function()
						setAllVisibleLevels(true)
						UpdateLevelButtonText()
						TriggerRender()
					end, false)

					AddEntry((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_NONE")) or "Select None", true, false, false, function()
						setAllVisibleLevels(false)
						UpdateLevelButtonText()
						TriggerRender()
					end, false)

					AddEntry(" ", true, false, false, nil, true)

					for i = 1, #VIEW_LEVEL_KEYS do
						local levelKey = VIEW_LEVEL_KEYS[i]
						AddEntry(levelKey, false, isLevelVisible(levelKey), true, function()
							local p = profile()
							local k = "view" .. levelKey
							p[k] = not p[k]
							UpdateLevelButtonText()
							TriggerRender()
						end, false)
					end
				end, "MENU")

				local anchor = (levelBtn and levelBtn.frame) or "cursor"
				ToggleDropDownMenu(1, nil, LOGS._levelMenuFrame, anchor, 0, 0)
			elseif type(EasyMenu) == "function" then
				local menu = {}
				menu[#menu + 1] = { text = ((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_ALL")) or "Select All"), notCheckable = true, func = function()
					setAllVisibleLevels(true); UpdateLevelButtonText(); TriggerRender()
				end }
				menu[#menu + 1] = { text = ((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_NONE")) or "Select None"), notCheckable = true, func = function()
					setAllVisibleLevels(false); UpdateLevelButtonText(); TriggerRender()
				end }
				menu[#menu + 1] = { text = " ", disabled = true, notCheckable = true }
				for i = 1, #VIEW_LEVEL_KEYS do
					local levelKey = VIEW_LEVEL_KEYS[i]
					menu[#menu + 1] = {
						text = levelKey,
						keepShownOnClick = true,
						isNotRadio = true,
						checked = isLevelVisible(levelKey),
						func = function()
							local p = profile()
							local k = "view" .. levelKey
							p[k] = not p[k]
							UpdateLevelButtonText()
							TriggerRender()
						end,
					}
				end
				EasyMenu(menu, LOGS._levelMenuFrame, "cursor", 0, 0, "MENU")
			end
		end
		levelBtn:SetCallback("OnClick", function()
			ShowLevelMenu()
		end)
		UpdateLevelButtonText()
		header:AddChild(levelBtn)

		local btnRefresh = AceGUI:Create("Button")
		btnRefresh:SetText((type(GMS.T) == "function" and GMS:T("LOGS_REFRESH")) or "Refresh")
		btnRefresh:SetWidth(110)
		btnRefresh:SetCallback("OnClick", function()
			TriggerRender()
		end)
		header:AddChild(btnRefresh)

		local btnClear = AceGUI:Create("Button")
		btnClear:SetText((type(GMS.T) == "function" and GMS:T("LOGS_CLEAR")) or "Clear")
		btnClear:SetWidth(110)
		btnClear:SetCallback("OnClick", function()
			GMS:Logs_Clear()
			TriggerRender()
		end)
		header:AddChild(btnClear)

		local btnCopy = AceGUI:Create("Button")
		btnCopy:SetText((type(GMS.T) == "function" and GMS:T("LOGS_COPY")) or "Copy (2000)")
		btnCopy:SetWidth(130)
		btnCopy:SetCallback("OnClick", function()
			LOGS:IngestGlobalBuffer()

			local entries = GMS:Logs_GetEntries(2000, 1)
			local lines = {}
			for i = 1, #entries do
				local e = entries[i]
				if isEntryVisible(e) then
					local origin = ""
					if (e.type and e.type ~= "") or (e.source and e.source ~= "") then
						origin = string.format(" [%s:%s]", e.type or "", e.source or "")
					end
					lines[#lines + 1] = string.format("[%s][%s]%s %s", e.level, e.time or "", origin, e.msg or "")
				end
			end
			local text = table.concat(lines, "\n")
			if type(ChatFrame_OpenChat) == "function" then
				ChatFrame_OpenChat(text)
			else
				chatPrint(text)
			end
		end)
		header:AddChild(btnCopy)
	end

	local function BuildPage(root, id, isCached)
		BuildLogsHeaderControls()
		if isCached then
			if LOGS._ui and type(LOGS._ui.renderAll) == "function" then
				LOGS._ui.renderAll()
			end
			return
		end
		root:SetLayout("Fill")

		local scroller = AceGUI:Create("ScrollFrame")
		scroller:SetLayout("List")
		scroller:SetFullWidth(true)
		scroller:SetFullHeight(true)
		root:AddChild(scroller)

		local function RenderAll()
			LOGS:IngestGlobalBuffer()

			scroller:ReleaseChildren()
			local entries = LOGS._entries or {}
			local contentWidth = (scroller.content and scroller.content.GetWidth and scroller.content:GetWidth()) or
				(scroller.frame and scroller.frame.GetWidth and scroller.frame:GetWidth()) or
				(root and root.frame and root.frame.GetWidth and root.frame:GetWidth()) or 900
			contentWidth = math.max(520, contentWidth - 24)
			for i = #entries, 1, -1 do
				local e = entries[i]
				if e and isEntryVisible(e) then
					scroller:AddChild(BuildLogRow(e, contentWidth))
				end
			end
		end

		local function PrependEntry(entry)
			if not scroller or not scroller.children then
				RenderAll()
				return
			end
			-- Always do a full re-render to keep column widths and line layout in sync.
			RenderAll()
		end

		LOGS._ui = {
			scroller = scroller,
			renderAll = RenderAll,
			prependEntry = PrependEntry,
		}

		local resizeToken = 0
		local function ScheduleRenderAll()
			resizeToken = resizeToken + 1
			local token = resizeToken
			if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
				C_Timer.After(0.05, function()
					if token ~= resizeToken then return end
					if LOGS._ui and type(LOGS._ui.renderAll) == "function" then
						LOGS._ui.renderAll()
					end
				end)
			else
				RenderAll()
			end
		end

		local function ScheduleInitialLayoutPass()
			if root and root.DoLayout then
				root:DoLayout()
			end
			if scroller and scroller.DoLayout then
				scroller:DoLayout()
			end
			ScheduleRenderAll()
			if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
				C_Timer.After(0.15, function()
					if LOGS._ui and type(LOGS._ui.renderAll) == "function" then
						LOGS._ui.renderAll()
					end
				end)
			end
		end
		if scroller.frame and type(scroller.frame.HookScript) == "function" then
			scroller.frame:HookScript("OnSizeChanged", function()
				ScheduleRenderAll()
			end)
		end
		if root.frame and type(root.frame.HookScript) == "function" then
			root.frame:HookScript("OnSizeChanged", function()
				ScheduleRenderAll()
			end)
		end

		RenderAll()
		ScheduleInitialLayoutPass()
	end

	local okPage = UI_RegisterPage_Compat(PAGE_ID, 90, TITLE, BuildPage)
	if not okPage then return false end

	if not LOGS._dockRegistered then
		LOGS._dockRegistered = UI_RegisterDockIcon_Compat(PAGE_ID, TITLE) == true
	end

	LOGS._uiRegistered = true
	LOCAL_LOG("INFO", "UI page registered (UI:RegisterPage compat)")
	return true
end

-- ###########################################################################
-- #	SLASH: /gms logs (match project slash API)
-- ###########################################################################

local function RegisterLogsSlash()
	if LOGS._slashRegistered then return true end

	if type(GMS.Slash_RegisterSubCommand) == "function" then
		GMS:Slash_RegisterSubCommand("logs", function()
			UI_Open("LOGS")
		end, {
			help = (type(GMS.T) == "function" and GMS:T("LOGS_SLASH_HELP")) or "/gms logs - opens the logs UI",
			alias = { "log" },
			owner = "LOGS",
		})

		LOGS._slashRegistered = true
		LOCAL_LOG("INFO", "Slash subcommand registered via GMS:Slash_RegisterSubCommand")
		return true
	end

	local SC = GMS.SlashCommands
	if type(SC) ~= "table" then return false end

	if type(SC.RegisterSubCommand) == "function" then
		SC:RegisterSubCommand("logs", {
			title = "Logs",
			help = (type(GMS.T) == "function" and GMS:T("LOGS_SLASH_HELP")) or "/gms logs - opens the logs UI",
			handler = function() UI_Open("LOGS") end,
		})
		LOGS._slashRegistered = true
		LOCAL_LOG("INFO", "Slash subcommand registered via SlashCommands:RegisterSubCommand")
		return true
	end

	SC.SUB = SC.SUB or {}
	SC.SUB.logs = SC.SUB.logs or {}
	SC.SUB.logs.title = SC.SUB.logs.title or "Logs"
	SC.SUB.logs.desc = SC.SUB.logs.desc or ((type(GMS.T) == "function" and GMS:T("LOGS_SUB_FALLBACK_DESC")) or "Opens the logs UI")
	SC.SUB.logs.run = function()
		UI_Open("LOGS")
	end

	LOGS._slashRegistered = true
	LOCAL_LOG("INFO", "Slash subcommand registered via SC.SUB fallback")
	return true
end

-- ###########################################################################
-- #	LIVE INGEST (ticker) - optional (notify already handles most cases)
-- ###########################################################################

local function StartTicker()
	if LOGS._ticker then return end
	if type(C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then return end

	LOGS._ticker = C_Timer.NewTicker(1.0, function()
		local added = LOGS:IngestGlobalBuffer()
		if added > 0 and LOGS._ui and LOGS._ui.prependEntry then
			local entries = LOGS._entries or {}
			for i = #entries - added + 1, #entries do
				local e = entries[i]
				if e and isEntryVisible(e) then
					pcall(LOGS._ui.prependEntry, e)
				end
			end
		end
	end)
end

-- ###########################################################################
-- #	DEFERRED BOOT
-- ###########################################################################

local function TryAll()
	RegisterLogsUI()
	RegisterLogsSlash()
	StartTicker()
end

LOGS:Init()

-- initial ingest (pull any early logs)
LOGS:IngestGlobalBuffer()

-- try immediate
TryAll()

-- try again when UI/Slash become ready
GMS:OnReady("EXT:SLASH", function()
	RegisterLogsSlash()
end)

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)

GMS:SetReady("EXT:LOGS")
LOCAL_LOG("INFO", "EXT:LOGS READY")

