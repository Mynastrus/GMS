-- ============================================================================
--	GMS/Core/Logs.lua
--	LOGS EXTENSION (no GMS:NewModule)
--	- Ingest: übernimmt Einträge aus GMS._LOG_BUFFER in eigenen Ringbuffer
--	- Ringbuffer persistiert via AceDB (falls verfügbar), sonst in-memory
--	- Notify Hook: LOCAL_LOG schreibt Buffer (SoT) + optional _LOG_NOTIFY(entry, idx)
--	  Logs.lua installiert _LOG_NOTIFY und ingested gebatched
--	- UI Page (AceGUI) + Live-Update (Notify + optional Ticker)
--	- Slash: /gms logs -> öffnet LOGS Page
--	- UI Integration: kompatibel mit GMS.UI:RegisterPage(id, order, title, buildFn)
--	- RightDock: nutzt GMS.UI:AddRightDockIconTop(...)
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- ###########################################################################
-- #	METADATA (PROJECT STANDARD - REQUIRED)
-- ###########################################################################

local METADATA = {
	TYPE         = "EXT", -- CORE | EXT | MOD
	INTERN_NAME  = "LOGS",
	SHORT_NAME   = "LOGS",
	DISPLAY_NAME = "Logs",
	VERSION      = "1.0.2",
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

local function nowReadable(fmt)
	if type(date) == "function" then
		return date(fmt or "%Y-%m-%d %H:%M:%S")
	end
	return ""
end

local function profile()
	return GMS:GetModuleOptions("LOGS") or REG_DEFAULTS
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
	local p = profile()
	local max = clamp(tonumber(p.maxEntries) or 400, 50, 5000)
	p.maxEntries = max

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

	local p = profile()
	p.ingestPos = tonumber(p.ingestPos) or 0

	local start = p.ingestPos + 1
	local last = #buf
	if start > last then return 0 end

	local entries = LOGS._entries
	if not entries then
		LOGS._entries = {}
		entries = LOGS._entries
		if LOGS._db then LOGS._db.profile.entries = entries end
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

	prof.ingestPos = last
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
				local minLvl = profile().minLevel or LOGS.LEVELS.INFO
				for i = #entries - added + 1, #entries do
					local e = entries[i]
					if e and (e.levelNum or 1) >= minLvl then
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
	GMS:RegisterModuleOptions("LOGS", REG_DEFAULTS, "PROFILE")

	if GMS.logging_db then
		LOGS._db = GMS.logging_db
		LOGS._entries = GMS.logging_db.char.logs or {}
		GMS.logging_db.char.logs = LOGS._entries

		local p = profile()
		p.ingestPos = tonumber(p.ingestPos) or 0
		trimToMax()

		LOCAL_LOG("INFO", "Logging initialized (GMS_Logging_DB char-scoped)")
	else
		LOCAL_LOG("WARN", "GMS.logging_db not available; fallback to in-memory only")
		LOGS._entries = {}
	end
end

-- PUBLIC CONFIG
function GMS:Logs_SetLevel(level) profile().minLevel = toLevel(level) end

function GMS:Logs_GetLevel() return profile().minLevel end

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
	if not (GMS.UI and type(GMS.UI.AddRightDockIconTop) == "function") then return false end
	GMS.UI:AddRightDockIconTop({
		id = pageId,
		order = 90,
		selectable = true,
		icon = "Interface\\Icons\\INV_Misc_Note_05",
		tooltipTitle = title or pageId,
		tooltipText = "Logs anzeigen",
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

local function BuildLogRow(entry)
	local grp = AceGUI:Create("SimpleGroup")
	grp:SetFullWidth(true)
	grp:SetLayout("List")

	local color = COLORS[entry.level] or "|cffffffff"
	local origin = ""
	if (entry.type and entry.type ~= "") or (entry.source and entry.source ~= "") then
		origin = string.format(" [%s:%s]", entry.type or "", entry.source or "")
	end

	local header = string.format("%s[%s]%s %s%s", color, entry.level, "|r", entry.time or "", origin)

	local hdr = AceGUI:Create("Label")
	hdr:SetText(header)
	hdr:SetFullWidth(true)
	grp:AddChild(hdr)

	local body = AceGUI:Create("Label")
	body:SetText(color .. (entry.msg or "") .. "|r")
	body:SetFullWidth(true)
	grp:AddChild(body)

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

	local function BuildPage(root)
		root:SetLayout("List")

		local header = AceGUI:Create("InlineGroup")
		header:SetTitle("Logs")
		header:SetFullWidth(true)
		header:SetLayout("Flow")
		root:AddChild(header)

		local btnRefresh = AceGUI:Create("Button")
		btnRefresh:SetText("Refresh")
		btnRefresh:SetWidth(120)
		header:AddChild(btnRefresh)

		local btnClear = AceGUI:Create("Button")
		btnClear:SetText("Clear")
		btnClear:SetWidth(120)
		header:AddChild(btnClear)

		local btnCopy = AceGUI:Create("Button")
		btnCopy:SetText("Copy")
		btnCopy:SetWidth(120)
		header:AddChild(btnCopy)

		local listGroup = AceGUI:Create("InlineGroup")
		listGroup:SetTitle("Entries (newest first)")
		listGroup:SetFullWidth(true)
		listGroup:SetLayout("Fill")
		root:AddChild(listGroup)

		local scroller = AceGUI:Create("ScrollFrame")
		scroller:SetLayout("List")
		scroller:SetFullWidth(true)
		scroller:SetFullHeight(true)
		listGroup:AddChild(scroller)

		-- Make entries container consume remaining height under the header (AceGUI List-parent workaround)
		local function UpdateEntriesHeight()
			if not (root and root.frame and header and header.frame and listGroup and listGroup.frame) then return end

			local rootH = root.frame:GetHeight() or 0
			local headerH = header.frame:GetHeight() or 0

			local padding = 28
			local minH = 140

			local avail = rootH - headerH - padding
			if avail < minH then avail = minH end

			listGroup:SetHeight(avail)
			scroller:SetFullHeight(true)

			if root.DoLayout then root:DoLayout() end
		end

		UpdateEntriesHeight()
		if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
			C_Timer.After(0, UpdateEntriesHeight)
		end

		if root.frame and type(root.frame.HookScript) == "function" then
			root.frame:HookScript("OnSizeChanged", function()
				UpdateEntriesHeight()
			end)
		end

		local function RenderAll()
			LOGS:IngestGlobalBuffer()

			scroller:ReleaseChildren()
			local entries = LOGS._entries or {}
			local minLvl = profile().minLevel or LOGS.LEVELS.INFO
			for i = #entries, 1, -1 do
				local e = entries[i]
				if e and (e.levelNum or 1) >= minLvl then
					scroller:AddChild(BuildLogRow(e))
				end
			end

			UpdateEntriesHeight()
		end

		local function PrependEntry(entry)
			if not scroller or not scroller.children then
				RenderAll()
				return
			end
			local w = BuildLogRow(entry)
			table.insert(scroller.children, 1, w)
			w.frame:SetParent(scroller.content)
			scroller:DoLayout()
			UpdateEntriesHeight()
		end

		LOGS._ui = {
			scroller = scroller,
			renderAll = RenderAll,
			prependEntry = PrependEntry,
		}

		btnRefresh:SetCallback("OnClick", function() RenderAll() end)
		btnClear:SetCallback("OnClick", function() GMS:Logs_Clear(); RenderAll() end)

		btnCopy:SetCallback("OnClick", function()
			LOGS:IngestGlobalBuffer()

			local entries = GMS:Logs_GetEntries(2000, profile().minLevel or 1)
			local lines = {}
			for i = 1, #entries do
				local e = entries[i]
				local origin = ""
				if (e.type and e.type ~= "") or (e.source and e.source ~= "") then
					origin = string.format(" [%s:%s]", e.type or "", e.source or "")
				end
				lines[#lines + 1] = string.format("[%s][%s]%s %s", e.level, e.time or "", origin, e.msg or "")
			end
			local text = table.concat(lines, "\n")
			if type(ChatFrame_OpenChat) == "function" then
				ChatFrame_OpenChat(text)
			else
				chatPrint(text)
			end
		end)

		RenderAll()
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
			help = "/gms logs - öffnet die Logs UI",
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
			help = "/gms logs - öffnet die Logs UI",
			handler = function() UI_Open("LOGS") end,
		})
		LOGS._slashRegistered = true
		LOCAL_LOG("INFO", "Slash subcommand registered via SlashCommands:RegisterSubCommand")
		return true
	end

	SC.SUB = SC.SUB or {}
	SC.SUB.logs = SC.SUB.logs or {}
	SC.SUB.logs.title = SC.SUB.logs.title or "Logs"
	SC.SUB.logs.desc = SC.SUB.logs.desc or "Öffnet die Logs UI"
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
			local minLvl = profile().minLevel or LOGS.LEVELS.INFO
			for i = #entries - added + 1, #entries do
				local e = entries[i]
				if e and (e.levelNum or 1) >= minLvl then
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
