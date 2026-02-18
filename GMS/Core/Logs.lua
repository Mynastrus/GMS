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
local GameTooltip        = GameTooltip
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
	VERSION      = "1.4.6",
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
	viewCOMM   = true,
	viewWARN   = true,
	viewERROR  = true,
}

local COLORS = {
	TRACE = "|cff9d9d9d",
	DEBUG = "|cff4da6ff",
	INFO  = "|cff4dff88",
	COMM  = "|cff6ec8ff",
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
LOGS._volatileProfile = nil

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

local VIEW_LEVEL_KEYS = { "TRACE", "DEBUG", "INFO", "COMM", "WARN", "ERROR" }
local SEVERITY_LEVEL_KEYS = { "TRACE", "DEBUG", "INFO", "WARN", "ERROR" }
local VIEW_LEVEL_DEFAULTS = {
	TRACE = false,
	DEBUG = false,
	INFO = true,
	COMM = true,
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
				p["view" .. key] = false
			end
			for i = 1, #SEVERITY_LEVEL_KEYS do
				local key = SEVERITY_LEVEL_KEYS[i]
				p["view" .. key] = (i >= legacyMin)
			end
			p.viewCOMM = true
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

local function cloneDefaults(defaults)
	local out = {}
	for k, v in pairs(defaults or {}) do
		out[k] = v
	end
	return out
end

local function markProfileDirty(p)
	if type(LOGS._volatileProfile) == "table" and p == LOGS._volatileProfile then
		LOGS._volatileProfile.__dirty = true
	end
end

local ensureSourceFilter

local function profile()
	local p = nil
	if type(GMS.GetModuleOptions) == "function" then
		p = GMS:GetModuleOptions("LOGS")
	end

	if type(p) ~= "table" and type(GMS.RegisterModuleOptions) == "function" then
		GMS:RegisterModuleOptions("LOGS", REG_DEFAULTS, "PROFILE")
		if type(GMS.GetModuleOptions) == "function" then
			p = GMS:GetModuleOptions("LOGS")
		end
	end

	if type(p) ~= "table" then
		if type(LOGS._volatileProfile) ~= "table" then
			LOGS._volatileProfile = cloneDefaults(REG_DEFAULTS)
			LOGS._volatileProfile.__dirty = false
		end
		p = LOGS._volatileProfile
	else
		if type(LOGS._volatileProfile) == "table" and LOGS._volatileProfile.__dirty == true then
			for k, v in pairs(LOGS._volatileProfile) do
				if k ~= "__dirty" then
					p[k] = v
				end
			end
		end
		LOGS._volatileProfile = nil
	end

	ensureViewLevelFilter(p)
	if type(ensureSourceFilter) == "function" and ensureSourceFilter(p) then
		markProfileDirty(p)
	end
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

local function makeSourceToken(srcType, srcName)
	local t = tostring(srcType or ""):upper()
	local s = tostring(srcName or ""):upper()
	if t == "" and s == "" then
		return ""
	end
	return t .. "|" .. s
end

local function getEntrySourceToken(entry)
	if type(entry) ~= "table" then return "" end
	return makeSourceToken(entry.type, entry.source)
end

local function resolveSourceFilterLabel(srcType, srcName)
	local t = tostring(srcType or "")
	local s = tostring(srcName or "")
	if s == "" then s = "-" end
	local display = s
	local localeKey = "NAME_" .. s:upper()
	if type(GMS.T) == "function" then
		local ok, localized = pcall(GMS.T, GMS, localeKey)
		if ok and type(localized) == "string" and localized ~= "" and localized ~= localeKey then
			display = localized
		end
	end
	return (t ~= "") and string.format("%s [%s]", display, t) or display
end

local function collectAvailableSourceFilters()
	local entries = LOGS._entries or {}
	local map = {}
	local out = {}
	for i = 1, #entries do
		local e = entries[i]
		if type(e) == "table" then
			local token = getEntrySourceToken(e)
			if token ~= "" and not map[token] then
				local srcType = tostring(e.type or "")
				local srcName = tostring(e.source or "")
				local item = {
					token = token,
					sourceType = srcType,
					sourceName = srcName,
					label = resolveSourceFilterLabel(srcType, srcName),
				}
				map[token] = item
				out[#out + 1] = item
			end
		end
	end
	table.sort(out, function(a, b)
		return tostring(a and a.label or "") < tostring(b and b.label or "")
	end)
	return out
end

ensureSourceFilter = function(p)
	p.viewSources = type(p.viewSources) == "table" and p.viewSources or {}
	local changed = false
	local list = collectAvailableSourceFilters()
	for i = 1, #list do
		local token = list[i].token
		if p.viewSources[token] == nil then
			p.viewSources[token] = true
			changed = true
		end
	end
	return changed
end

local function isSourceTokenVisible(token)
	local p = profile()
	p.viewSources = type(p.viewSources) == "table" and p.viewSources or {}
	local v = p.viewSources[token]
	if v == nil then
		p.viewSources[token] = true
		markProfileDirty(p)
		return true
	end
	return v == true
end

local function isSourceVisible(entry)
	local token = getEntrySourceToken(entry)
	if token == "" then return true end
	return isSourceTokenVisible(token)
end

local function displayLevelKey(entry)
	if type(entry) ~= "table" then
		return "INFO"
	end
	local explicit = tostring(entry.displayLevel or ""):upper()
	if explicit ~= "" then
		return explicit
	end
	if tostring(entry.level or ""):upper() == "COMM" then
		return "COMM"
	end
	local lvl = entry.levelNum
	if type(lvl) ~= "number" then
		lvl = toLevel(entry.level)
	end
	return levelName(lvl)
end

local function isEntryVisible(entry)
	if type(entry) ~= "table" then return false end
	return isLevelVisible(displayLevelKey(entry)) and isSourceVisible(entry)
end

local function setAllVisibleLevels(flag)
	local p = profile()
	local v = flag and true or false
	for i = 1, #VIEW_LEVEL_KEYS do
		local key = VIEW_LEVEL_KEYS[i]
		p["view" .. key] = v
	end
	markProfileDirty(p)
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

local function setAllVisibleSources(flag)
	local p = profile()
	if ensureSourceFilter(p) then
		markProfileDirty(p)
	end
	p.viewSources = type(p.viewSources) == "table" and p.viewSources or {}
	local list = collectAvailableSourceFilters()
	local v = flag and true or false
	for i = 1, #list do
		p.viewSources[list[i].token] = v
	end
	markProfileDirty(p)
end

local function countVisibleSources()
	local p = profile()
	if ensureSourceFilter(p) then
		markProfileDirty(p)
	end
	local list = collectAvailableSourceFilters()
	if #list == 0 then return 0, 0 end
	local count = 0
	for i = 1, #list do
		if isSourceTokenVisible(list[i].token) then
			count = count + 1
		end
	end
	return count, #list
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

local function dataPrettyFromData(data)
	if type(data) ~= "table" or #data == 0 then return "" end
	local lines = {}
	for i = 1, #data do
		local v = data[i]
		if type(v) == "table" then
			lines[#lines + 1] = string.format("[%d] %s", i, _jsonish(v, {}, 0, 6, 200))
		else
			lines[#lines + 1] = string.format("[%d] %s", i, tostring(v))
		end
	end
	return table.concat(lines, "\n")
end

local function analyzeDataForDetails(data)
	if type(data) ~= "table" or #data == 0 then
		return false, false, 0
	end
	local hasTable = false
	for i = 1, #data do
		if type(data[i]) == "table" then
			hasTable = true
			break
		end
	end
	return true, hasTable, #data
end

local function LT(key, fallback, ...)
	if type(GMS.T) == "function" then
		local ok, localized = pcall(GMS.T, GMS, key, ...)
		if ok and type(localized) == "string" and localized ~= "" and localized ~= key then
			return localized
		end
	end
	if select("#", ...) > 0 then
		return string.format(tostring(fallback or key), ...)
	end
	return tostring(fallback or key)
end

local function ParseRecordKey(key)
	local txt = tostring(key or "")
	local a, b, c = txt:match("^([^:]+):([^:]+):(.+)$")
	if not a or not b or not c then
		return nil, nil, nil
	end
	return a, b, c
end

local function NormalizeHexColor(hex)
	local c = tostring(hex or "")
	c = c:gsub("^|c", ""):gsub("|r", "")
	if c:match("^[0-9a-fA-F]+$") then
		if #c == 6 then
			c = "ff" .. c
		end
		if #c == 8 then
			return string.lower(c)
		end
	end
	return nil
end

local function ResolveCharacterDisplayByGuid(guid)
	local g = tostring(guid or "")
	if g == "" then return "?" end

	local roster = GMS and (GMS:GetModule("ROSTER", true) or GMS:GetModule("Roster", true)) or nil
	local nameFull = ""
	local classFile = ""
	if type(roster) == "table" and type(roster.GetMemberByGUID) == "function" then
		local ok, m = pcall(roster.GetMemberByGUID, roster, g)
		if ok and type(m) == "table" then
			nameFull = tostring(m.name_full or m.name or "")
			classFile = tostring(m.classFileName or m.classFile or "")
		end
	end
	if nameFull == "" and type(roster) == "table" and type(roster.GetMemberMeta) == "function" then
		local ok, meta = pcall(roster.GetMemberMeta, roster, g)
		if ok and type(meta) == "table" then
			nameFull = tostring(meta.name_full or "")
			if nameFull == "" then
				local n = tostring(meta.name or "")
				local r = tostring(meta.realm or "")
				if n ~= "" then
					nameFull = (r ~= "") and (n .. "-" .. r) or n
				end
			end
			if classFile == "" then
				classFile = tostring(meta.classFile or "")
			end
		end
	end
	if nameFull == "" then
		return g
	end

	local colorHex = nil
	if type(GMS.GET_CLASS_COLOR) == "function" and classFile ~= "" then
		local ok, clsColor = pcall(GMS.GET_CLASS_COLOR, GMS, classFile)
		if ok then
			colorHex = NormalizeHexColor(clsColor)
		end
	end
	if colorHex then
		return "|c" .. colorHex .. nameFull .. "|r"
	end
	return nameFull
end

local function ResolveRecordTargetDisplay(key)
	local originGuid, charGuid, domain = ParseRecordKey(key)
	local targetGuid = tostring(charGuid or originGuid or "")
	if targetGuid == "" then
		return tostring(key or "?")
	end
	local who = ResolveCharacterDisplayByGuid(targetGuid)
	local d = tostring(domain or "")
	if d ~= "" then
		return who .. " [" .. d .. "]"
	end
	return who
end

local function HumanizeCommMessage(raw, data)
	local msg = tostring(raw or "")
	if msg == "" then return msg end
	local d = type(data) == "table" and data or {}

	if msg == "Data sent" then
		local subPrefix = tostring(d[1] or "?")
		local distribution = tostring(d[2] or "GUILD")
		local targetName = tostring(d[3] or "")
		local targetSuffix = (targetName ~= "") and (" -> " .. targetName) or ""
		if subPrefix == "__SYNC_V1" then
			return LT("LOGS_HUMAN_COMM_DATA_SENT_SYNC_FMT", "Sent synchronization packet via %s%s", distribution, targetSuffix)
		end
		return LT("LOGS_HUMAN_COMM_DATA_SENT_FMT", "Sent %s packet via %s%s", subPrefix, distribution, targetSuffix)
	end
	if msg == "Registered prefix handler" then
		return LT("LOGS_HUMAN_COMM_PREFIX_REGISTERED_FMT", "Registered communication handler for prefix %s", tostring(d[1] or "?"))
	end
	if msg == "Stored sync push record" or msg == "Stored chunked sync record" then
		local _, _, domain = ParseRecordKey(tostring(d[1] or ""))
		local channel = tostring(d[2] or "?")
		return LT("LOGS_HUMAN_COMM_RECORD_STORED_FMT", "Stored %s data received via %s", tostring(domain ~= "" and domain or "?"), channel)
	end
	if msg == "Chunk reassembly deserialize failed" then
		return LT("LOGS_HUMAN_COMM_CHUNK_DESERIALIZE_FAILED_FMT", "Failed to reassemble chunked data from %s", tostring(d[2] or d[1] or "?"))
	end
	if msg == "Invalid chunked record" then
		return LT("LOGS_HUMAN_COMM_INVALID_CHUNK_FMT", "Received invalid chunked record (%s)", tostring(d[1] or "?"))
	end
	if msg == "Invalid sync push record" then
		return LT("LOGS_HUMAN_COMM_INVALID_PUSH_FMT", "Received invalid sync record (%s)", tostring(d[1] or "?"))
	end
	if msg == "Relay announce batch sent" then
		return LT("LOGS_HUMAN_COMM_RELAY_SENT_FMT", "Sent relay announce batch (%s records)", tostring(d[1] or "?"))
	end
	if msg == "Manual sync request sent" then
		local target = ResolveRecordTargetDisplay(tostring(d[1] or ""))
		return LT(
			"LOGS_HUMAN_COMM_MANUAL_REQ_SENT_FMT",
			"Requested sync for %s via %s (%s)",
			target,
			tostring(d[2] or "?"),
			tostring(d[3] or "-")
		)
	end
	if msg == "Chunked sync checksum mismatch accepted (compat)" then
		local target = ResolveRecordTargetDisplay(tostring(d[1] or ""))
		return LT(
			"LOGS_HUMAN_COMM_CHUNK_CHECKSUM_COMPAT_FMT",
			"Accepted chunked sync checksum mismatch for %s (compatibility mode)",
			target
		)
	end
	if msg == "Sync checksum mismatch accepted (compat)" then
		local target = ResolveRecordTargetDisplay(tostring(d[1] or ""))
		return LT(
			"LOGS_HUMAN_COMM_SYNC_CHECKSUM_COMPAT_FMT",
			"Accepted sync checksum mismatch for %s via %s (compatibility mode)",
			target,
			tostring(d[2] or "?")
		)
	end
	if msg == "Source GUID mismatch" then
		return LT("LOGS_HUMAN_COMM_SOURCE_MISMATCH_FMT", "Rejected packet due to source mismatch (%s from %s)", tostring(d[1] or "?"), tostring(d[2] or "?"))
	end
	if msg == "Missing sender GUID for secured prefix" then
		return LT("LOGS_HUMAN_COMM_MISSING_SENDER_GUID_FMT", "Rejected secured packet %s because sender GUID is missing", tostring(d[1] or "?"))
	end
	if msg == "Unauthorized data received" then
		return LT("LOGS_HUMAN_COMM_UNAUTHORIZED_FMT", "Rejected unauthorized packet %s from %s", tostring(d[1] or "?"), tostring(d[2] or "?"))
	end
	if msg == "Comm initialized" then
		return LT("LOGS_HUMAN_COMM_INITIALIZED", "Communication module initialized")
	end
	if msg == "Comm extension loaded" then
		return LT("LOGS_HUMAN_COMM_EXT_LOADED", "Communication extension loaded")
	end

	return msg
end

local function HumanizeGenericMessage(source, raw, data)
	local msg = tostring(raw or "")
	local src = tostring(source or "")
	if src == "Comm" or src == "COMM" then
		return HumanizeCommMessage(msg, data)
	end
	local d = type(data) == "table" and data or {}

	if msg == "OnInitialize" then return LT("LOGS_HUMAN_CORE_ONINITIALIZE", "Addon initialization started") end
	if msg == "OnEnable" then return LT("LOGS_HUMAN_CORE_ONENABLE", "Addon enabled") end
	if msg == "OnDisable" then return LT("LOGS_HUMAN_CORE_ONDISABLE", "Addon disabled") end
	if msg == "EXT:LOGS READY" then return LT("LOGS_HUMAN_LOGS_READY", "Logs extension is ready") end
	if msg == "Logs cleared" then return LT("LOGS_HUMAN_LOGS_CLEARED", "Logs were cleared") end
	if msg == "Database extension loaded" then return LT("LOGS_HUMAN_DB_EXT_LOADED", "Database extension loaded") end
	if msg == "Permissions initialized" then return LT("LOGS_HUMAN_PERM_INITIALIZED", "Permissions initialized") end
	if msg == "Permissions extension loaded" then return LT("LOGS_HUMAN_PERM_EXT_LOADED", "Permissions extension loaded") end
	if msg == "Settings extension loaded" then return LT("LOGS_HUMAN_SETTINGS_EXT_LOADED", "Settings extension loaded") end
	if msg == "SlashCommands extension loaded" then return LT("LOGS_HUMAN_SLASH_EXT_LOADED", "Slash commands extension loaded") end
	if msg == "UI page registered (UI:RegisterPage compat)" then return LT("LOGS_HUMAN_UI_PAGE_REGISTERED", "UI page registered") end
	if msg == "Registered subcommand: /gms ui" then return LT("LOGS_HUMAN_UI_SLASH_REGISTERED", "Registered slash command /gms ui") end
	if msg == "One-time hard reset applied" then return LT("LOGS_HUMAN_DB_HARD_RESET_APPLIED", "One-time database hard reset applied") end
	if msg == "All databases reset to defaults" then return LT("LOGS_HUMAN_DB_RESET_DONE", "All databases were reset to defaults") end

	if msg == "READY" then return LT("LOGS_HUMAN_STATE_READY_FMT", "Component ready: %s", tostring(d[1] or "?")) end
	if msg == "UNREADY" then return LT("LOGS_HUMAN_STATE_UNREADY_FMT", "Component not ready: %s", tostring(d[1] or "?")) end
	if msg == "INIT" then return LT("LOGS_HUMAN_STATE_INIT_FMT", "Component initialized: %s", tostring(d[1] or "?")) end
	if msg == "ENABLED" then return LT("LOGS_HUMAN_STATE_ENABLED_FMT", "Component enabled: %s", tostring(d[1] or "?")) end

	if msg == "Raid scan ingested" then
		return LT(
			"LOGS_HUMAN_RAID_SCAN_INGESTED_FMT",
			"Raid scan completed: processed=%s, unresolved=%s",
			tostring(d[1] or "?"),
			tostring(d[5] or d[3] or "?")
		)
	end
	if msg == "Raid best enriched from character statistics" then
		return LT("LOGS_HUMAN_RAID_BEST_ENRICHED", "Raid best progress was updated from character statistics")
	end
	if msg == "Catalog rebuild" then
		return LT("LOGS_HUMAN_RAID_CATALOG_REBUILD_FMT", "Raid catalog rebuild status: %s", tostring(d[1] or "?"))
	end
	if msg == "EJ catalog built" then
		return LT("LOGS_HUMAN_RAID_EJ_BUILT_FMT", "Encounter Journal catalog built (%s)", tostring(d[1] or "?"))
	end
	if msg == "EJ catalog build failed" then
		return LT("LOGS_HUMAN_RAID_EJ_BUILD_FAILED_FMT", "Encounter Journal catalog build failed (%s)", tostring(d[1] or "?"))
	end
	if msg == "SavedInstances skipped entries" then
		return LT("LOGS_HUMAN_RAID_SKIPPED_ENTRIES", "Some SavedInstances entries were skipped")
	end
	if msg == "Unresolved raid name->instanceID mappings" then
		return LT("LOGS_HUMAN_RAID_UNRESOLVED_MAPPINGS_FMT", "Unresolved raid name mappings: %s", tostring(d[1] or "?"))
	end
	if msg == "Collapsed named raid fallbacks" then
		return LT("LOGS_HUMAN_RAID_FALLBACK_COLLAPSED_FMT", "Merged old raid fallback entries: %s", tostring(d[1] or "?"))
	end
	if msg == "Catalog not ready; ingest continues with name-based fallback keys" then
		return LT("LOGS_HUMAN_RAID_CATALOG_NOT_READY", "Raid catalog not ready, temporary fallback mapping active")
	end
	if msg == "Equipment scanned + saved" then
		return LT("LOGS_HUMAN_EQUIPMENT_SCANNED_SAVED", "Equipment scan completed and saved")
	end
	if msg == "GuildLog enabled" then
		return LT("LOGS_HUMAN_GUILDLOG_ENABLED", "GuildLog enabled")
	end

	if msg == "Member added to group" then
		return LT("LOGS_HUMAN_PERM_MEMBER_ADDED_FMT", "Member %s was added to group %s", tostring(d[1] or "?"), tostring(d[2] or "?"))
	end
	if msg == "Member removed from group" then
		return LT("LOGS_HUMAN_PERM_MEMBER_REMOVED_FMT", "Member %s was removed from group %s", tostring(d[1] or "?"), tostring(d[2] or "?"))
	end
	if msg == "Rank assigned to group" then
		return LT("LOGS_HUMAN_PERM_RANK_ASSIGNED_FMT", "Guild rank %s was assigned to group %s", tostring(d[1] or "?"), tostring(d[2] or "?"))
	end

	local mod = msg:match("^(.-)%s+extension%s+loaded$")
	if mod then
		return LT("LOGS_HUMAN_EXT_LOADED_FMT", "%s extension loaded", mod)
	end

	local modFile = msg:match("^(.-)%s+file%s+loaded$")
	if modFile then
		return LT("LOGS_HUMAN_FILE_LOADED_FMT", "%s file loaded", modFile)
	end

	local logic = msg:match("^(.-)%s+logic%s+loaded$")
	if logic then
		return LT("LOGS_HUMAN_LOGIC_LOADED_FMT", "%s logic loaded", logic)
	end

	if msg == "Module initialized" then
		return LT("LOGS_HUMAN_MODULE_INITIALIZED", "Module initialized")
	end
	if msg == "Module enabled" then
		return LT("LOGS_HUMAN_MODULE_ENABLED", "Module enabled")
	end
	if msg == "Module disabled" then
		return LT("LOGS_HUMAN_MODULE_DISABLED", "Module disabled")
	end

	local optsInit = msg:match("^(.-)%s+options%s+initialized")
	if optsInit then
		return LT("LOGS_HUMAN_OPTIONS_INITIALIZED_FMT", "%s options initialized", optsInit)
	end
	local optsFail = msg:match("^Failed to retrieve%s+(.-)%s+options")
	if optsFail then
		return LT("LOGS_HUMAN_OPTIONS_LOAD_FAILED_FMT", "Failed to load %s options", optsFail)
	end
	local optsState = msg:match("^(.-)%s+options%s+state$")
	if optsState then
		return LT("LOGS_HUMAN_OPTIONS_STATE_FMT", "%s options state updated", optsState)
	end

	local moduleEnabling = msg:match("^Enabling%s+(.-)%s+module$")
	if moduleEnabling then
		return LT("LOGS_HUMAN_MODULE_ENABLING_FMT", "Enabling %s module", moduleEnabling)
	end
	local moduleInitializing = msg:match("^Initializing%s+(.-)%s+module$")
	if moduleInitializing then
		return LT("LOGS_HUMAN_MODULE_INITIALIZING_FMT", "Initializing %s module", moduleInitializing)
	end

	local snapSaved = msg:match("^(.-)%s+snapshot%s+saved$")
	if snapSaved then
		return LT("LOGS_HUMAN_SNAPSHOT_SAVED_FMT", "%s snapshot saved locally", snapSaved)
	end
	local snapPub = msg:match("^(.-)%s+snapshot%s+published$")
	if snapPub then
		return LT("LOGS_HUMAN_SNAPSHOT_PUBLISHED_FMT", "%s snapshot published to guild", snapPub)
	end
	local pubFail = msg:match("^(.-)%s+publish%s+failed$")
	if pubFail then
		return LT("LOGS_HUMAN_PUBLISH_FAILED_FMT", "%s publish failed", pubFail)
	end

	local pageReg = msg:match("^(.-)%s+page%s+registered")
	if pageReg then
		return LT("LOGS_HUMAN_PAGE_REGISTERED_FMT", "%s page registered", pageReg)
	end

	if msg == "RightDock icon registered" then
		return LT("LOGS_HUMAN_RIGHTDOCK_REGISTERED", "RightDock icon registered")
	end

	local slashReg = msg:match("^Slash subcommand registered via%s+(.+)$")
	if slashReg then
		return LT("LOGS_HUMAN_SLASH_REGISTERED_FMT", "Slash subcommand registered (%s)", slashReg)
	end

	return msg
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
	local rawMsg = tostring((e and (e.msg or e.message)) or "")
	local rawTime = e and (e.time or e.timestamp) or nil
	local rawSource = tostring((e and e.source) or "")
	local rawType = tostring((e and e.type) or "")
	local rawLevel = tostring((e and e.level) or "INFO"):upper()
	local isCommLevel = (rawLevel == "COMM")

	local lvl = isCommLevel and LOGS.LEVELS.INFO or toLevel(rawLevel)

	local srcType = rawType
	local srcName = rawSource

	local base = rawMsg
	base = HumanizeGenericMessage(srcName, base, e.data)
	local suffix = dataSuffixFromData(e.data)
	if suffix ~= "" then
		local detailsLabel = LT("LOGS_SUFFIX_DETAILS_LABEL", "details")
		suffix = suffix:gsub("^%s*|%s*data=", " | " .. tostring(detailsLabel) .. "=")
		suffix = suffix:gsub("^%s*|%s*details=", " | " .. tostring(detailsLabel) .. "=")
	end
	local msg = base .. suffix
	local displayLevel = isCommLevel and "COMM" or levelName(lvl)

	return {
		time     = nowReadable(profile().timestampFormat or "%Y-%m-%d %H:%M:%S"),
		levelNum = lvl,
		level    = levelName(lvl),
		displayLevel = displayLevel,

		type   = srcType,
		source = srcName,

		msg = msg,
		detailsPretty = dataPrettyFromData(e.data),
		hasDetailsData = analyzeDataForDetails(e.data),
		detailsCount = (type(e.data) == "table" and #e.data) or 0,
		detailsHasTable = (select(2, analyzeDataForDetails(e.data)) == true),

		-- optional: raw timing from GetTime()
		t = rawTime,
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
	for i = 1, #SEVERITY_LEVEL_KEYS do
		local key = SEVERITY_LEVEL_KEYS[i]
		p["view" .. key] = (i >= lvl)
	end
	markProfileDirty(p)
end

function GMS:Logs_GetLevel()
	local p = profile()
	if p.minLevel then
		return p.minLevel
	end
	for i = 1, #SEVERITY_LEVEL_KEYS do
		if p["view" .. SEVERITY_LEVEL_KEYS[i]] == true then
			return i
		end
	end
	return LOGS.LEVELS.INFO
end

function GMS:Logs_EnableChat(v)
	local p = profile()
	p.chat = not not v
	markProfileDirty(p)
end

function GMS:Logs_IsChatEnabled() return not not profile().chat end

function GMS:Logs_SetMaxEntries(n)
	local p = profile()
	p.maxEntries = clamp(tonumber(n) or 400, 50, 5000)
	markProfileDirty(p)
	trimToMax()
end

function GMS:Logs_GetMaxEntries() return profile().maxEntries end

function GMS:Logs_Clear()
	local p = profile()
	p.entries = {}
	LOGS._entries = p.entries
	if LOGS._db then LOGS._db.profile.entries = LOGS._entries end
	markProfileDirty(p)

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

	local function EscapePattern(text)
		return tostring(text or ""):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	end

	local function ExtractDetailsFromMsg(rawMsg)
		local s = tostring(rawMsg or "")
		local details = s:match("%s*|%s*data=(.+)$")
		if details and details ~= "" then return details end
		local details2 = s:match("%s*|%s*details=(.+)$")
		if details2 and details2 ~= "" then return details2 end
		local details3 = s:match("%s*|%s*daten=(.+)$")
		if details3 and details3 ~= "" then return details3 end
		return ""
	end

	local function StripDetailsSuffix(rawMsg)
		local s = tostring(rawMsg or "")
		s = s:gsub("%s*|%s*data=.+$", "")
		s = s:gsub("%s*|%s*details=.+$", "")
		s = s:gsub("%s*|%s*daten=.+$", "")
		local detailsLabel = LT("LOGS_SUFFIX_DETAILS_LABEL", "details")
		if detailsLabel ~= "" then
			s = s:gsub("%s*|%s*" .. EscapePattern(detailsLabel) .. "=.+$", "")
		end
		return s
	end

	local function ShowDetailsPopup(detailsEntry, displayName, detailsText)
		if not AceGUI then return end
		local txt = tostring(detailsText or "")
		local e = type(detailsEntry) == "table" and detailsEntry or {}
		local contextMsg = OneLine(StripDetailsSuffix(tostring(e.msg or "")))
		if contextMsg == "" then contextMsg = "-" end
		local context = table.concat({
			string.format(LT("LOGS_DETAILS_CONTEXT_SOURCE_FMT", "Log: %s"), tostring(displayName or "-")),
			string.format(LT("LOGS_DETAILS_CONTEXT_LEVEL_FMT", "Level: %s"), tostring(displayLevelKey(e) or "-")),
			string.format(LT("LOGS_DETAILS_CONTEXT_TIME_FMT", "Time: %s"), tostring(e.time or "-")),
			string.format(LT("LOGS_DETAILS_CONTEXT_MSG_FMT", "Message: %s"), contextMsg),
		}, "\n")
		if txt == "" then
			txt = LT("LOGS_DETAILS_EMPTY", "No details available.")
		end
		txt = context .. "\n\n" .. txt
		local frame = AceGUI:Create("Frame")
		frame:SetTitle(LT("LOGS_DETAILS_TITLE_FMT", "Log Details - %s", tostring(displayName or "-")))
		frame:SetLayout("Fill")
		frame:SetWidth(760)
		frame:SetHeight(420)
		frame:EnableResize(true)

		local box = AceGUI:Create("MultiLineEditBox")
		box:SetLabel("")
		box:SetText(txt)
		box:DisableButton(true)
		if box.SetNumLines then
			box:SetNumLines(22)
		end
		frame:AddChild(box)
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

	local rowLevel = displayLevelKey(entry)
	local color = COLORS[rowLevel] or COLORS[entry.level] or "|cffffffff"
	local timeText = OneLine(entry.time or "")
	local levelText = OneLine(rowLevel)
	local typeText = OneLine(entry.type or "-")
	local sourceText = OneLine(entry.source or "-")

	local function ResolveDisplayName(srcType, srcName)
		local t = tostring(srcType or "")
		local s = tostring(srcName or "")
		if s == "" then return "-" end
		local su = s:upper()

		local registry = (GMS and GMS.REGISTRY) or nil
		local function MatchIn(reg)
			if type(reg) ~= "table" then return nil end
			for _, meta in pairs(reg) do
				local key = tostring(meta.key or ""):upper()
				local name = tostring(meta.name or ""):upper()
				local short = tostring(meta.shortName or ""):upper()
				local display = (type(GMS.ResolveRegistryDisplayName) == "function")
					and tostring(GMS:ResolveRegistryDisplayName(meta, s))
					or tostring(meta.displayName or "")
				local displayU = display:upper()
				if su == key or su == name or su == short or su == displayU then
					return (display ~= "" and display) or s
				end
			end
			return nil
		end

		if type(registry) == "table" then
			if t == "EXT" then
				local hit = MatchIn(registry.EXT)
				if hit then return hit end
			elseif t == "MOD" then
				local hit = MatchIn(registry.MOD)
				if hit then return hit end
			elseif t == "CORE" then
				local hit = MatchIn(registry.CORE)
				if hit then return hit end
			end

			local hit = MatchIn(registry.EXT) or MatchIn(registry.MOD) or MatchIn(registry.CORE)
			if hit then return hit end
		end

		local localeKey = "NAME_" .. su
		if type(GMS.T) == "function" then
			local ok, localized = pcall(GMS.T, GMS, localeKey)
			if ok and type(localized) == "string" and localized ~= "" and localized ~= localeKey then
				return localized
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
	local detailsText = tostring(entry.detailsPretty or "")
	if detailsText == "" then
		detailsText = ExtractDetailsFromMsg(entry.msg)
	end
	msg = OneLine(StripDetailsSuffix(msg))
	local hasRawDetails = (tostring(detailsText or "") ~= "")
	local hasTableDetails = (entry.detailsHasTable == true)
	local detailsLongText = (#tostring(detailsText or "") >= 90)
	local hasDetails = hasRawDetails and (hasTableDetails or detailsLongText)

	local detailsButtonWidth = 0
	if hasDetails then
		detailsButtonWidth = 86
	end
	local hasMsg = (msg ~= "")
	if detailsButtonWidth > 0 and hasMsg then
		msgWidth = msgWidth - detailsButtonWidth
		if msgWidth < 120 then msgWidth = 120 end
	end

	if hasMsg then
		local body = AceGUI:Create("Label")
		body:SetWidth(msgWidth)
		body:SetText("|cffd8d8d8" .. msg .. "|r")
		if body.label then
			body.label:SetWordWrap(false)
			body.label:SetMaxLines(1)
		end
		grp:AddChild(body)
	end

	if hasDetails then
		local link = AceGUI:Create("InteractiveLabel")
		link:SetWidth(detailsButtonWidth)
		local linkText = LT("LOGS_DETAILS_BUTTON", "View")
		local normalColor = "6ec8ff"
		local hoverColor = "a8e4ff"
		local function SetLinkVisual(isHover)
			local c = isHover and hoverColor or normalColor
			link:SetText("|cff" .. c .. linkText .. "|r")
		end
		SetLinkVisual(false)
		link:SetCallback("OnClick", function()
			ShowDetailsPopup(entry, displayName, detailsText)
		end)
		if link.frame and type(link.frame.SetScript) == "function" and GameTooltip then
			link.frame:SetScript("OnEnter", function(self)
				SetLinkVisual(true)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(LT("LOGS_DETAILS_TOOLTIP", "Show detailed payload in pretty print"))
				GameTooltip:Show()
			end)
			link.frame:SetScript("OnLeave", function()
				SetLinkVisual(false)
				GameTooltip:Hide()
			end)
		end
		if link.label then
			link.label:SetWordWrap(false)
			link.label:SetMaxLines(1)
		end
		grp:AddChild(link)
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

		local filterBtn = AceGUI:Create("Button")
		filterBtn:SetWidth(260)
		local function UpdateFilterButtonText()
			local levelSelected = countVisibleLevels()
			local sourceSelected, sourceTotal = countVisibleSources()
			filterBtn:SetText(
				(type(GMS.T) == "function" and GMS:T("LOGS_FILTER_FMT", levelSelected, #VIEW_LEVEL_KEYS, sourceSelected, sourceTotal))
				or string.format("Filter (L %d/%d, Q %d/%d)", levelSelected, #VIEW_LEVEL_KEYS, sourceSelected, sourceTotal)
			)
		end

		local function ToggleLevelKey(levelKey)
			local p = profile()
			local k = "view" .. levelKey
			p[k] = not p[k]
			markProfileDirty(p)
			UpdateFilterButtonText()
			TriggerRender()
		end

		local function ToggleSourceToken(token)
			local p = profile()
			p.viewSources = type(p.viewSources) == "table" and p.viewSources or {}
			p.viewSources[token] = not isSourceTokenVisible(token)
			markProfileDirty(p)
			UpdateFilterButtonText()
			TriggerRender()
		end

		local function ShowFilterMenu()
			local p = profile()
			if ensureSourceFilter(p) then
				markProfileDirty(p)
			end
			local sources = collectAvailableSourceFilters()
			if type(CreateFrame) ~= "function" then return end
			LOGS._filterMenuFrame = LOGS._filterMenuFrame or CreateFrame("Frame", "GMS_LOGS_FILTER_MENU", UIParent, "UIDropDownMenuTemplate")
			if type(UIDropDownMenu_Initialize) == "function" and type(ToggleDropDownMenu) == "function" then
				UIDropDownMenu_Initialize(LOGS._filterMenuFrame, function(_, level, menuList)
					level = level or 1
					if type(UIDropDownMenu_AddButton) ~= "function" then return end

					local menuValue = menuList or _G.UIDROPDOWNMENU_MENU_VALUE
					local function AddEntry(text, notCheckable, checked, keepShownOnClick, func, disabled, hasArrow, value)
						local info = type(UIDropDownMenu_CreateInfo) == "function" and UIDropDownMenu_CreateInfo() or {}
						info.text = text
						info.notCheckable = notCheckable and true or false
						info.checked = checked
						info.keepShownOnClick = keepShownOnClick and true or false
						info.isNotRadio = true
						info.func = func
						info.disabled = disabled and true or false
						info.hasArrow = hasArrow and true or false
						info.value = value
						UIDropDownMenu_AddButton(info, level)
					end

					if level == 1 then
						AddEntry((type(GMS.T) == "function" and GMS:T("LOGS_LEVELS")) or "Levels:", true, false, false, nil, false, true, "LEVELS")
						AddEntry((type(GMS.T) == "function" and GMS:T("LOGS_SOURCES")) or "Sources:", true, false, false, nil, false, true, "SOURCES")
						return
					end

					if level == 2 and menuValue == "LEVELS" then
						AddEntry((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_ALL")) or "Select All", true, false, false, function()
							setAllVisibleLevels(true)
							UpdateFilterButtonText()
							TriggerRender()
						end, false)
						AddEntry((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_NONE")) or "Select None", true, false, false, function()
							setAllVisibleLevels(false)
							UpdateFilterButtonText()
							TriggerRender()
						end, false)
						AddEntry(" ", true, false, false, nil, true)

						for i = 1, #VIEW_LEVEL_KEYS do
							local levelKey = VIEW_LEVEL_KEYS[i]
							AddEntry(levelKey, false, isLevelVisible(levelKey), true, function()
								ToggleLevelKey(levelKey)
							end, false)
						end
						return
					end

					if level == 2 and menuValue == "SOURCES" then
						AddEntry((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_ALL")) or "Select All", true, false, false, function()
							setAllVisibleSources(true)
							UpdateFilterButtonText()
							TriggerRender()
						end, false)
						AddEntry((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_NONE")) or "Select None", true, false, false, function()
							setAllVisibleSources(false)
							UpdateFilterButtonText()
							TriggerRender()
						end, false)
						AddEntry(" ", true, false, false, nil, true)

						for i = 1, #sources do
							local item = sources[i]
							AddEntry(item.label, false, isSourceTokenVisible(item.token), true, function()
								ToggleSourceToken(item.token)
							end, false)
						end
					end
				end, "MENU")

				local anchor = (filterBtn and filterBtn.frame) or "cursor"
				ToggleDropDownMenu(1, nil, LOGS._filterMenuFrame, anchor, 0, 0)
			elseif type(EasyMenu) == "function" then
				local levelsMenu = {}
				levelsMenu[#levelsMenu + 1] = { text = ((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_ALL")) or "Select All"), notCheckable = true, func = function()
					setAllVisibleLevels(true); UpdateFilterButtonText(); TriggerRender()
				end }
				levelsMenu[#levelsMenu + 1] = { text = ((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_NONE")) or "Select None"), notCheckable = true, func = function()
					setAllVisibleLevels(false); UpdateFilterButtonText(); TriggerRender()
				end }
				levelsMenu[#levelsMenu + 1] = { text = " ", disabled = true, notCheckable = true }
				for i = 1, #VIEW_LEVEL_KEYS do
					local levelKey = VIEW_LEVEL_KEYS[i]
					levelsMenu[#levelsMenu + 1] = {
						text = levelKey,
						keepShownOnClick = true,
						isNotRadio = true,
						checked = isLevelVisible(levelKey),
						func = function()
							ToggleLevelKey(levelKey)
						end,
					}
				end

				local sourcesMenu = {}
				sourcesMenu[#sourcesMenu + 1] = { text = ((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_ALL")) or "Select All"), notCheckable = true, func = function()
					setAllVisibleSources(true); UpdateFilterButtonText(); TriggerRender()
				end }
				sourcesMenu[#sourcesMenu + 1] = { text = ((type(GMS.T) == "function" and GMS:T("LOGS_SELECT_NONE")) or "Select None"), notCheckable = true, func = function()
					setAllVisibleSources(false); UpdateFilterButtonText(); TriggerRender()
				end }
				sourcesMenu[#sourcesMenu + 1] = { text = " ", disabled = true, notCheckable = true }
				for i = 1, #sources do
					local item = sources[i]
					sourcesMenu[#sourcesMenu + 1] = {
						text = item.label,
						keepShownOnClick = true,
						isNotRadio = true,
						checked = isSourceTokenVisible(item.token),
						func = function()
							ToggleSourceToken(item.token)
						end,
					}
				end

				local menu = {
					{ text = ((type(GMS.T) == "function" and GMS:T("LOGS_LEVELS")) or "Levels:"), notCheckable = true, hasArrow = true, menuList = levelsMenu },
					{ text = ((type(GMS.T) == "function" and GMS:T("LOGS_SOURCES")) or "Sources:"), notCheckable = true, hasArrow = true, menuList = sourcesMenu },
				}
				EasyMenu(menu, LOGS._filterMenuFrame, "cursor", 0, 0, "MENU")
			end
		end

		filterBtn:SetCallback("OnClick", function()
			ShowFilterMenu()
		end)
		UpdateFilterButtonText()
		LOGS._updateSourceButtonText = UpdateFilterButtonText
		header:AddChild(filterBtn)

		local btnClear = AceGUI:Create("Button")
		btnClear:SetText((type(GMS.T) == "function" and GMS:T("LOGS_CLEAR")) or "Clear")
		btnClear:SetWidth(110)
		btnClear:SetCallback("OnClick", function()
			GMS:Logs_Clear()
			TriggerRender()
		end)
		header:AddChild(btnClear)

		local function ShowCopyPopup(text)
			if not AceGUI then
				if type(ChatFrame_OpenChat) == "function" then
					ChatFrame_OpenChat(text)
				else
					chatPrint(text)
				end
				return
			end
			local frame = AceGUI:Create("Frame")
			frame:SetTitle((type(GMS.T) == "function" and GMS:T("LOGS_COPY_TITLE")) or "Copy Logs")
			frame:SetLayout("Fill")
			frame:SetWidth(900)
			frame:SetHeight(560)
			frame:EnableResize(true)

			local box = AceGUI:Create("MultiLineEditBox")
			box:SetLabel("")
			box:SetText(tostring(text or ""))
			box:DisableButton(true)
			if box.SetNumLines then
				box:SetNumLines(30)
			end
			frame:AddChild(box)
		end

		local btnCopy = AceGUI:Create("Button")
		btnCopy:SetText((type(GMS.T) == "function" and GMS:T("LOGS_COPY")) or "Copy")
		btnCopy:SetWidth(130)
		btnCopy:SetCallback("OnClick", function()
			LOGS:IngestGlobalBuffer()

			local entries = LOGS._entries or {}
			local lines = {}
			for i = #entries, 1, -1 do
				local e = entries[i]
				if isEntryVisible(e) then
					local origin = ""
					if (e.type and e.type ~= "") or (e.source and e.source ~= "") then
						origin = string.format(" [%s:%s]", e.type or "", e.source or "")
					end
					local line = string.format("[%s][%s]%s %s", displayLevelKey(e), e.time or "", origin, tostring(e.msg or ""))
					local details = tostring(e.detailsPretty or "")
					if details ~= "" then
						line = line .. "\n" .. details
					end
					lines[#lines + 1] = line
				end
			end
			local text = table.concat(lines, "\n")
			ShowCopyPopup(text)
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
			local visibleCount = 0
			local totalCount = #entries
			for i = #entries, 1, -1 do
				local e = entries[i]
				if e and isEntryVisible(e) then
					visibleCount = visibleCount + 1
					scroller:AddChild(BuildLogRow(e, contentWidth))
				end
			end
			if scroller and type(scroller.DoLayout) == "function" then
				scroller:DoLayout()
			end
			if type(LOGS._updateSourceButtonText) == "function" then
				pcall(LOGS._updateSourceButtonText)
			end
			if GMS and GMS.UI and type(GMS.UI.SetStatusText) == "function" then
				GMS.UI:SetStatusText(LT("LOGS_STATUS_BAR_FMT", "Logs: showing %d / total %d", visibleCount, totalCount))
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
			helpKey = "LOGS_SLASH_HELP",
			helpFallback = "/gms logs - opens the logs UI",
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
			help = "/gms logs - opens the logs UI",
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

