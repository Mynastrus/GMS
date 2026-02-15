-- ============================================================================
--	GMS/Modules/GuildLog.lua
--	GuildLog MODULE
--	- Logs guild roster changes into its own module log
--	- Optional chat echo when events happen
--	- Dedicated UI page (separate from generic logs)
-- ============================================================================

local METADATA = {
	TYPE         = "MOD",
	INTERN_NAME  = "GUILDLOG",
	SHORT_NAME   = "GuildLog",
	DISPLAY_NAME = "Guild Log",
	VERSION      = "1.1.15",
}

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

---@diagnostic disable: undefined-global
local GetTime = GetTime
local date = date
local IsInGuild = IsInGuild
local GetNumGuildMembers = GetNumGuildMembers
local GetGuildRosterInfo = GetGuildRosterInfo
local GetRealmName = GetRealmName
local C_GuildInfo = C_GuildInfo
local GuildRoster = GuildRoster
local C_Timer = C_Timer
local wipe = wipe
---@diagnostic enable: undefined-global

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

---@diagnostic disable: undefined-global
local _G = _G
---@diagnostic enable: undefined-global

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time   = (GetTime and GetTime()) or 0,
		level  = tostring(level or "INFO"),
		type   = METADATA.TYPE,
		source = METADATA.SHORT_NAME,
		msg    = tostring(msg or ""),
		data   = { ... },
	}
	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry
	if type(GMS._LOG_NOTIFY) == "function" then
		pcall(GMS._LOG_NOTIFY, entry, idx)
	end
end

local MODULE_NAME = METADATA.INTERN_NAME
local GuildLog = GMS:GetModule(MODULE_NAME, true)
if not GuildLog then
	GuildLog = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
end

if type(GMS.RegisterModule) == "function" then
	GMS:RegisterModule(GuildLog, METADATA)
end
GMS[MODULE_NAME] = GuildLog

GuildLog._options = GuildLog._options or nil
GuildLog._optionsBound = GuildLog._optionsBound or false
GuildLog._snapshot = GuildLog._snapshot or nil
GuildLog._pageRegistered = GuildLog._pageRegistered or false
GuildLog._dockRegistered = GuildLog._dockRegistered or false
GuildLog._scanScheduled = GuildLog._scanScheduled or false
GuildLog._ui = GuildLog._ui or nil
GuildLog._uiRefreshToken = GuildLog._uiRefreshToken or 0
GuildLog._baselineLogged = GuildLog._baselineLogged or false
GuildLog._pollTicker = GuildLog._pollTicker or nil
GuildLog._scanToken = GuildLog._scanToken or 0
GuildLog._recentEventSigs = GuildLog._recentEventSigs or {}
GuildLog._pendingPersist = GuildLog._pendingPersist or {
	chatEcho = false,
	maxEntries = false,
	entries = false,
	memberHistory = false,
}

local OPTIONS_DEFAULTS = {
	chatEcho = false,
	maxEntries = 1000,
}

local UI_RENDER_LIMIT = 300
local UI_RENDER_CHUNK_SIZE = 40

local function GetScopedOptions()
	if type(GMS.InitializeStandardDatabases) == "function" then
		pcall(GMS.InitializeStandardDatabases, GMS, false)
	end
	if not GMS or type(GMS.db) ~= "table" or type(GMS.db.global) ~= "table" then
		return nil
	end

	local global = GMS.db.global
	global.guilds = type(global.guilds) == "table" and global.guilds or {}

	local guildKey = nil
	if type(GMS.GetGuildStorageKey) == "function" then
		guildKey = GMS:GetGuildStorageKey()
	end

	if type(guildKey) ~= "string" or guildKey == "" then
		local first = nil
		local count = 0
		for k in pairs(global.guilds) do
			if type(k) == "string" and k ~= "" then
				count = count + 1
				if not first then first = k end
				if count > 1 then break end
			end
		end
		if count == 1 and first then
			guildKey = first
		end
	end
	if type(guildKey) ~= "string" or guildKey == "" then
		return nil
	end

	global.guilds[guildKey] = type(global.guilds[guildKey]) == "table" and global.guilds[guildKey] or {}
	local gRoot = global.guilds[guildKey]

	-- Key-compat: migrate old mixed-case module buckets into canonical key.
	if type(gRoot[MODULE_NAME]) ~= "table" then
		local legacyKeys = { "GuildLog", "guildlog" }
		for i = 1, #legacyKeys do
			local lk = legacyKeys[i]
			if type(gRoot[lk]) == "table" then
				gRoot[MODULE_NAME] = gRoot[lk]
				gRoot[lk] = nil
				break
			end
		end
	end
	gRoot[MODULE_NAME] = type(gRoot[MODULE_NAME]) == "table" and gRoot[MODULE_NAME] or {}

	-- Legacy migration: try to import old guildlog buckets once if current is empty.
	local target = gRoot[MODULE_NAME]
	local targetEntries = (type(target.entries) == "table") and target.entries or nil
	local isEmpty = (not targetEntries) or (#targetEntries == 0)
	if isEmpty then
		local candidates = { "GUILDACTIVITY", "GuildActivity", "guildactivity", "GUILD_ACTIVITY", "GA" }
		for i = 1, #candidates do
			local key = candidates[i]
			local src = gRoot[key]
			if type(src) == "table" and type(src.entries) == "table" and #src.entries > 0 then
				target.entries = src.entries
				if type(src.memberHistory) == "table" and next(src.memberHistory) ~= nil then
					target.memberHistory = src.memberHistory
				end
				if src.chatEcho ~= nil then
					target.chatEcho = src.chatEcho and true or false
				end
				if src.maxEntries ~= nil then
					target.maxEntries = tonumber(src.maxEntries) or target.maxEntries
				end
				LOCAL_LOG("INFO", "Migrated GuildLog legacy entries from guild bucket key", key, #src.entries)
				break
			end
		end
	end

	-- Legacy migration: optional import from deprecated GMS_Guild_DB if available.
	if (type(target.entries) ~= "table" or #target.entries == 0) and type(_G) == "table" and type(_G.GMS_Guild_DB) == "table" then
		local old = _G.GMS_Guild_DB[guildKey]
		if type(old) ~= "table" then
			-- fallback: single bucket in legacy DB
			local first, count = nil, 0
			for k, v in pairs(_G.GMS_Guild_DB) do
				if type(v) == "table" then
					count = count + 1
					if not first then first = v end
					if count > 1 then break end
				end
			end
			if count == 1 then old = first end
		end
		if type(old) == "table" then
			local oldCandidates = { old[MODULE_NAME], old.GUILDACTIVITY, old.GuildActivity, old.guildactivity, old.GUILD_ACTIVITY, old.GA, old }
			for i = 1, #oldCandidates do
				local src = oldCandidates[i]
				if type(src) == "table" and type(src.entries) == "table" and #src.entries > 0 then
					target.entries = src.entries
					if type(src.memberHistory) == "table" and next(src.memberHistory) ~= nil then
						target.memberHistory = src.memberHistory
					end
					if src.chatEcho ~= nil then
						target.chatEcho = src.chatEcho and true or false
					end
					if src.maxEntries ~= nil then
						target.maxEntries = tonumber(src.maxEntries) or target.maxEntries
					end
					LOCAL_LOG("INFO", "Migrated GuildLog legacy entries from GMS_Guild_DB", #src.entries)
					break
				end
			end
		end
	end

	return gRoot[MODULE_NAME]
end

local function T(key, fallback, ...)
	if type(GMS.T) == "function" then
		local txt = GMS:T(key, ...)
		if txt and txt ~= key then return txt end
	end
	if select("#", ...) > 0 then
		local ok, out = pcall(string.format, tostring(fallback or key), ...)
		return ok and out or tostring(fallback or key)
	end
	return tostring(fallback or key)
end

local function ClampMaxEntries(v)
	local n = tonumber(v) or 1000
	if n < 50 then n = 50 end
	if n > 5000 then n = 5000 end
	return n
end

local function NewPendingPersistFlags()
	return {
		chatEcho = false,
		maxEntries = false,
		entries = false,
		memberHistory = false,
	}
end

local function ResetPendingPersist()
	GuildLog._pendingPersist = NewPendingPersistFlags()
end

local function EnsurePendingPersist()
	local p = GuildLog._pendingPersist
	if type(p) ~= "table" then
		p = NewPendingPersistFlags()
		GuildLog._pendingPersist = p
	end
	if p.chatEcho ~= true then p.chatEcho = false end
	if p.maxEntries ~= true then p.maxEntries = false end
	if p.entries ~= true then p.entries = false end
	if p.memberHistory ~= true then p.memberHistory = false end
	return p
end

local function EntryMergeSignature(e)
	if type(e) ~= "table" then return "" end
	local d = type(e.data) == "table" and e.data or nil
	return table.concat({
		tostring(e.ts or ""),
		tostring(e.kind or ""),
		tostring(e.msg or ""),
		d and tostring(d.guid or d.memberKey or d.oldName or "") or "",
		d and tostring(d.newName or d.oldRealm or d.newRealm or "") or "",
	}, "|")
end

local function MergeEntries(runtimeEntries, scopedEntries, maxEntries)
	if type(runtimeEntries) ~= "table" then
		return type(scopedEntries) == "table" and scopedEntries or {}
	end
	if type(scopedEntries) ~= "table" then
		return runtimeEntries
	end
	if runtimeEntries == scopedEntries then
		return scopedEntries
	end

	local merged = {}
	local seen = {}
	local function append(list)
		for i = 1, #list do
			local e = list[i]
			if type(e) == "table" then
				local sig = EntryMergeSignature(e)
				if not seen[sig] then
					seen[sig] = true
					merged[#merged + 1] = e
				end
			end
		end
	end

	append(scopedEntries)
	append(runtimeEntries)

	table.sort(merged, function(a, b)
		return (tonumber(a.ts) or 0) < (tonumber(b.ts) or 0)
	end)

	local limit = ClampMaxEntries(maxEntries)
	while #merged > limit do
		table.remove(merged, 1)
	end
	return merged
end

local function CloneMapEntry(src)
	local out = {}
	for k, v in pairs(src) do
		out[k] = v
	end
	return out
end

local function MergeMemberHistory(runtimeHistory, scopedHistory)
	if type(runtimeHistory) ~= "table" then
		return type(scopedHistory) == "table" and scopedHistory or {}
	end
	if type(scopedHistory) ~= "table" then
		return runtimeHistory
	end
	if runtimeHistory == scopedHistory then
		return scopedHistory
	end

	local merged = {}
	for guid, entry in pairs(scopedHistory) do
		if type(entry) == "table" then
			merged[guid] = CloneMapEntry(entry)
		end
	end

	for guid, entry in pairs(runtimeHistory) do
		if type(entry) == "table" then
			local dest = merged[guid]
			if type(dest) ~= "table" then
				merged[guid] = CloneMapEntry(entry)
			else
				dest.guid = tostring(entry.guid or dest.guid or guid)
				if tostring(entry.name or "") ~= "" then
					dest.name = tostring(entry.name)
				end
				dest.everMember = (dest.everMember == true) or (entry.everMember == true)
				if entry.currentMember ~= nil then
					dest.currentMember = entry.currentMember == true
				end
				local destFirstTracked = tonumber(dest.firstTrackedAt) or 0
				local srcFirstTracked = tonumber(entry.firstTrackedAt) or 0
				if destFirstTracked <= 0 or (srcFirstTracked > 0 and srcFirstTracked < destFirstTracked) then
					dest.firstTrackedAt = srcFirstTracked
					if tostring(entry.firstTrackedTime or "") ~= "" then
						dest.firstTrackedTime = tostring(entry.firstTrackedTime)
					end
				end
				local destFirstJoin = tonumber(dest.firstJoinAt) or 0
				local srcFirstJoin = tonumber(entry.firstJoinAt) or 0
				if destFirstJoin <= 0 or (srcFirstJoin > 0 and srcFirstJoin < destFirstJoin) then
					dest.firstJoinAt = srcFirstJoin
					if tostring(entry.firstJoinTime or "") ~= "" then
						dest.firstJoinTime = tostring(entry.firstJoinTime)
					end
				end
				dest.lastJoinAt = math.max(tonumber(dest.lastJoinAt) or 0, tonumber(entry.lastJoinAt) or 0)
				dest.lastLeaveAt = math.max(tonumber(dest.lastLeaveAt) or 0, tonumber(entry.lastLeaveAt) or 0)
				dest.joinCount = math.max(tonumber(dest.joinCount) or 0, tonumber(entry.joinCount) or 0)
				dest.leftCount = math.max(tonumber(dest.leftCount) or 0, tonumber(entry.leftCount) or 0)
				dest.rejoinCount = math.max(tonumber(dest.rejoinCount) or 0, tonumber(entry.rejoinCount) or 0)
				if tostring(entry.lastJoinTime or "") ~= "" then
					dest.lastJoinTime = tostring(entry.lastJoinTime)
				end
				if tostring(entry.lastLeaveTime or "") ~= "" then
					dest.lastLeaveTime = tostring(entry.lastLeaveTime)
				end
			end
		end
	end
	return merged
end

local function MergeRuntimeIntoScoped(scoped, runtime)
	if type(scoped) ~= "table" or type(runtime) ~= "table" then
		return
	end
	local pending = EnsurePendingPersist()

	if pending.entries and type(runtime.entries) == "table" then
		scoped.entries = MergeEntries(runtime.entries, scoped.entries, runtime.maxEntries or scoped.maxEntries)
	elseif (type(scoped.entries) ~= "table" or #scoped.entries == 0) and type(runtime.entries) == "table" and #runtime.entries > 0 then
		scoped.entries = runtime.entries
	end

	if pending.memberHistory and type(runtime.memberHistory) == "table" then
		scoped.memberHistory = MergeMemberHistory(runtime.memberHistory, scoped.memberHistory)
	elseif (type(scoped.memberHistory) ~= "table" or next(scoped.memberHistory) == nil) and type(runtime.memberHistory) == "table" then
		scoped.memberHistory = runtime.memberHistory
	end

	if pending.chatEcho and runtime.chatEcho ~= nil then
		scoped.chatEcho = runtime.chatEcho and true or false
	elseif scoped.chatEcho == nil and runtime.chatEcho ~= nil then
		scoped.chatEcho = runtime.chatEcho and true or false
	end

	if pending.maxEntries and runtime.maxEntries ~= nil then
		scoped.maxEntries = ClampMaxEntries(runtime.maxEntries)
	elseif scoped.maxEntries == nil and runtime.maxEntries ~= nil then
		scoped.maxEntries = ClampMaxEntries(runtime.maxEntries)
	end
end

local function EnsureOptions()
	local current = GuildLog._options
	local scoped = GetScopedOptions()
	local opts = nil

	if type(scoped) == "table" then
		opts = scoped
		GuildLog._optionsBound = true

		-- If we started in RAM fallback before guild key was available,
		-- merge runtime data into the real persistent table once bound.
		if type(current) == "table" and current ~= opts then
			MergeRuntimeIntoScoped(opts, current)
			ResetPendingPersist()
		end
	else
		opts = current or {}
		GuildLog._optionsBound = false
	end

	if opts.chatEcho == nil then opts.chatEcho = false end
	opts.maxEntries = ClampMaxEntries(opts.maxEntries)
	if type(opts.entries) ~= "table" then opts.entries = {} end
	if type(opts.memberHistory) ~= "table" then opts.memberHistory = {} end
	GuildLog._options = opts
	return opts
end

local function EnsureOptionsCompat()
	-- Keep function name for existing call sites.
	return EnsureOptions()
end

local function MarkPendingPersist(field)
	local p = EnsurePendingPersist()
	if type(field) == "string" and field ~= "" then
		p[field] = true
	end
end

local function SyncOptionsToScoped()
	local opts = EnsureOptionsCompat()
	if type(opts) ~= "table" then return opts end
	local scoped = GetScopedOptions()
	if type(scoped) ~= "table" then return opts end

	-- If runtime started in RAM fallback and guild-scoped storage becomes available
	-- later, merge pending runtime mutations explicitly into persistent scoped data.
	if opts ~= scoped then
		MergeRuntimeIntoScoped(scoped, opts)
	end

	if scoped.chatEcho == nil then scoped.chatEcho = false end
	scoped.maxEntries = ClampMaxEntries(scoped.maxEntries)
	if type(scoped.entries) ~= "table" then scoped.entries = {} end
	if type(scoped.memberHistory) ~= "table" then scoped.memberHistory = {} end

	GuildLog._options = scoped
	GuildLog._optionsBound = true
	ResetPendingPersist()
	return scoped
end

local function GetEffectiveChatEcho()
	local scoped = GetScopedOptions()
	if type(scoped) == "table" and scoped.chatEcho ~= nil then
		return scoped.chatEcho and true or false
	end
	local opts = EnsureOptionsCompat()
	if type(opts) == "table" and opts.chatEcho ~= nil then
		return opts.chatEcho and true or false
	end
	return false
end

local function GetCurrentGuildKeySafe()
	if type(GMS.GetGuildStorageKey) == "function" then
		return tostring(GMS:GetGuildStorageKey() or "")
	end
	return ""
end

local function SetChatEchoPersist(value, sourceTag)
	local newValue = value and true or false
	local scoped = GetScopedOptions()
	if type(scoped) == "table" then
		scoped.chatEcho = newValue
		GuildLog._options = scoped
		GuildLog._optionsBound = true
	end
	local opts = EnsureOptionsCompat()
	if type(opts) == "table" then
		opts.chatEcho = newValue
	end
	if not GuildLog._optionsBound then
		MarkPendingPersist("chatEcho")
	end
	SyncOptionsToScoped()
	LOCAL_LOG("INFO", "GuildLog chatEcho set", tostring(sourceTag or "unknown"), tostring(newValue), GetCurrentGuildKeySafe())
	return newValue
end

local function Entries()
	local opts = EnsureOptionsCompat()
	if type(opts) ~= "table" then return nil end
	if type(opts.entries) ~= "table" then opts.entries = {} end
	return opts.entries
end

local function MemberHistory()
	local opts = EnsureOptionsCompat()
	if type(opts) ~= "table" then return nil end
	if type(opts.memberHistory) ~= "table" then opts.memberHistory = {} end
	return opts.memberHistory
end

local function FormatNow()
	if type(date) == "function" then
		return date("%Y-%m-%d %H:%M:%S")
	end
	return tostring((GetTime and GetTime()) or 0)
end

local function PushEntry(kind, msg, data)
	local opts = EnsureOptionsCompat()
	local entries = Entries()
	if type(entries) ~= "table" then return end

	entries[#entries + 1] = {
		ts = (GetTime and GetTime()) or 0,
		time = FormatNow(),
		kind = tostring(kind or "INFO"),
		msg = tostring(msg or ""),
		data = data,
	}

	local maxEntries = ClampMaxEntries(opts and opts.maxEntries or 1000)
	while #entries > maxEntries do
		table.remove(entries, 1)
	end

	if not GuildLog._optionsBound then
		MarkPendingPersist("entries")
	end

	-- Hard persist mirror to avoid any runtime ref ambiguity.
	opts = SyncOptionsToScoped() or opts

	if opts and opts.chatEcho and type(GMS.Print) == "function" then
		GMS:Print("|cff03A9F4[GuildLog]|r " .. tostring(msg or ""))
	end

	if GuildLog._ui and type(GuildLog._ui.render) == "function" then
		GuildLog._uiRefreshToken = GuildLog._uiRefreshToken + 1
		local token = GuildLog._uiRefreshToken
		if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
			C_Timer.After(0, function()
				if token ~= GuildLog._uiRefreshToken then return end
				if GuildLog._ui and type(GuildLog._ui.render) == "function" then
					GuildLog._ui.render()
				end
			end)
		else
			GuildLog._ui.render()
		end
	end
end

local function BuildEventSignature(kind, msg, data)
	local d = type(data) == "table" and data or nil
	local guid = d and tostring(d.guid or "") or ""
	local oldName = d and tostring(d.oldName or "") or ""
	local newName = d and tostring(d.newName or "") or ""
	local oldRealm = d and tostring(d.oldRealm or "") or ""
	local newRealm = d and tostring(d.newRealm or "") or ""
	local oldFaction = d and tostring(d.oldFaction or "") or ""
	local newFaction = d and tostring(d.newFaction or "") or ""
	local oldRace = d and tostring(d.oldRace or "") or ""
	local newRace = d and tostring(d.newRace or "") or ""
	return table.concat({
		tostring(kind or ""),
		tostring(msg or ""),
		guid,
		oldName, newName,
		oldRealm, newRealm,
		oldFaction, newFaction,
		oldRace, newRace,
	}, "|")
end

local function EmitEvent(kind, msg, data)
	local now = (GetTime and GetTime()) or 0
	local cache = GuildLog._recentEventSigs or {}
	GuildLog._recentEventSigs = cache

	for sig, ts in pairs(cache) do
		if (now - (tonumber(ts) or 0)) > 1.25 then
			cache[sig] = nil
		end
	end

	local sig = BuildEventSignature(kind, msg, data)
	local last = tonumber(cache[sig]) or 0
	if (now - last) < 1.25 then
		return
	end

	cache[sig] = now
	PushEntry(kind, msg, data)
end

local function NormalizeName(name)
	local n = tostring(name or "")
	n = n:gsub("^%s+", ""):gsub("%s+$", "")
	return n
end

local function NormalizeRealmChain(realm)
	local r = NormalizeName(realm)
	if r == "" then return r end
	if not r:find("%-") then return r end

	local parts = {}
	for p in r:gmatch("[^%-]+") do
		parts[#parts + 1] = p
	end
	local count = #parts
	if count < 2 then return r end

	for patternLen = 1, math.floor(count / 2) do
		if (count % patternLen) == 0 then
			local repeated = true
			for i = patternLen + 1, count do
				local baseIdx = ((i - 1) % patternLen) + 1
				if parts[i] ~= parts[baseIdx] then
					repeated = false
					break
				end
			end
			if repeated then
				local normalized = {}
				for i = 1, patternLen do
					normalized[#normalized + 1] = parts[i]
				end
				return table.concat(normalized, "-")
			end
		end
	end

	return r
end

local function SplitNameRealm(rawName)
	local full = tostring(rawName or "")
	local name, realm = full:match("^([^%-]+)%-(.+)$")
	if not name then
		name = full
		realm = tostring((type(GetRealmName) == "function" and GetRealmName()) or "")
	end
	return NormalizeName(name), NormalizeRealmChain(realm), NormalizeName(full)
end

local function GetRosterFactionByIndex(index)
	if type(index) ~= "number" then return "" end
	if type(C_GuildInfo) ~= "table" then return "" end

	local infoFn = C_GuildInfo.GetGuildRosterMemberInfo or C_GuildInfo.GetGuildRosterMemberData
	if type(infoFn) ~= "function" then return "" end

	local ok, info = pcall(infoFn, index)
	if not ok or type(info) ~= "table" then return "" end

	local faction = info.faction or info.factionName or info.factionGroup
	if type(faction) ~= "string" then return "" end
	return NormalizeName(faction)
end

local function GetRosterRaceByIndex(index)
	if type(index) ~= "number" then return "" end
	if type(C_GuildInfo) ~= "table" then return "" end

	local infoFn = C_GuildInfo.GetGuildRosterMemberInfo or C_GuildInfo.GetGuildRosterMemberData
	if type(infoFn) ~= "function" then return "" end

	local ok, info = pcall(infoFn, index)
	if not ok or type(info) ~= "table" then return "" end

	local race = info.raceName or info.race
	if type(race) ~= "string" then return "" end
	return NormalizeName(race)
end

local function EnsureHistoryEntry(guid, name)
	local hist = MemberHistory()
	if type(hist) ~= "table" then return nil end
	local id = tostring(guid or "")
	if id == "" then return nil end
	hist[id] = hist[id] or {
		guid = id,
		name = tostring(name or ""),
		everMember = false,
		currentMember = false,
		firstTrackedAt = 0,
		firstTrackedTime = "",
		firstJoinAt = 0,
		firstJoinTime = "",
		lastJoinAt = 0,
		lastJoinTime = "",
		lastLeaveAt = 0,
		lastLeaveTime = "",
		joinCount = 0,
		leftCount = 0,
		rejoinCount = 0,
	}
	local e = hist[id]
	if tostring(name or "") ~= "" then
		e.name = tostring(name)
	end
	if (tonumber(e.firstTrackedAt) or 0) <= 0 then
		e.firstTrackedAt = (GetTime and GetTime()) or 0
		e.firstTrackedTime = FormatNow()
	end
	if not GuildLog._optionsBound then
		MarkPendingPersist("memberHistory")
	end
	return e
end

local function MarkJoin(guid, name, isObservedJoin)
	local e = EnsureHistoryEntry(guid, name)
	if not e then return nil, false end
	local wasEver = e.everMember == true
	local wasCurrent = e.currentMember == true
	local nowTs = (GetTime and GetTime()) or 0
	local nowTxt = FormatNow()

	if isObservedJoin == true then
		e.joinCount = (tonumber(e.joinCount) or 0) + 1
		if (tonumber(e.firstJoinAt) or 0) <= 0 then
			e.firstJoinAt = nowTs
			e.firstJoinTime = nowTxt
		end
		e.lastJoinAt = nowTs
		e.lastJoinTime = nowTxt
		if wasEver and not wasCurrent then
			e.rejoinCount = (tonumber(e.rejoinCount) or 0) + 1
		end
	elseif not wasEver then
		-- baseline-seed fallback when we cannot observe historical join
		e.joinCount = math.max(1, tonumber(e.joinCount) or 0)
	end

	e.everMember = true
	e.currentMember = true

	local isRejoin = wasEver and not wasCurrent and isObservedJoin == true
	return e, isRejoin
end

local function MarkLeave(guid, name)
	local e = EnsureHistoryEntry(guid, name)
	if not e then return nil end
	local nowTs = (GetTime and GetTime()) or 0
	local nowTxt = FormatNow()
	e.leftCount = (tonumber(e.leftCount) or 0) + 1
	e.lastLeaveAt = nowTs
	e.lastLeaveTime = nowTxt
	e.currentMember = false
	return e
end

local function SeedHistoryFromSnapshot(snapshot)
	if type(snapshot) ~= "table" then return end
	for guid, m in pairs(snapshot) do
		MarkJoin(guid, m and m.name, false)
	end
end

local function MigrateHistoryKey(oldKey, newKey, memberName)
	if oldKey == newKey then return end
	local hist = MemberHistory()
	if type(hist) ~= "table" then return end
	local oldId = tostring(oldKey or "")
	local newId = tostring(newKey or "")
	if oldId == "" or newId == "" then return end

	local oldEntry = hist[oldId]
	local newEntry = hist[newId]
	if type(oldEntry) ~= "table" then return end

	if type(newEntry) ~= "table" then
		hist[newId] = oldEntry
		newEntry = oldEntry
	else
		newEntry.name = tostring(memberName or newEntry.name or oldEntry.name or "")
		newEntry.everMember = newEntry.everMember or oldEntry.everMember
		newEntry.currentMember = newEntry.currentMember or oldEntry.currentMember
		newEntry.firstTrackedAt = math.min(tonumber(newEntry.firstTrackedAt) or math.huge, tonumber(oldEntry.firstTrackedAt) or math.huge)
		newEntry.firstJoinAt = math.min(tonumber(newEntry.firstJoinAt) or math.huge, tonumber(oldEntry.firstJoinAt) or math.huge)
		newEntry.lastJoinAt = math.max(tonumber(newEntry.lastJoinAt) or 0, tonumber(oldEntry.lastJoinAt) or 0)
		newEntry.lastLeaveAt = math.max(tonumber(newEntry.lastLeaveAt) or 0, tonumber(oldEntry.lastLeaveAt) or 0)
		newEntry.joinCount = math.max(tonumber(newEntry.joinCount) or 0, tonumber(oldEntry.joinCount) or 0)
		newEntry.leftCount = math.max(tonumber(newEntry.leftCount) or 0, tonumber(oldEntry.leftCount) or 0)
		newEntry.rejoinCount = math.max(tonumber(newEntry.rejoinCount) or 0, tonumber(oldEntry.rejoinCount) or 0)
	end

	newEntry.guid = newId
	newEntry.name = tostring(memberName or newEntry.name or "")
	hist[oldId] = nil
end

local function BuildCurrentRosterSnapshot()
	local out = {}
	if not IsInGuild or not IsInGuild() then return out end
	if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
		return out
	end

	local total = tonumber((select(1, GetNumGuildMembers()))) or 0
	for i = 1, total do
		local name, rank, rankIndex, level, class, zone, note, officerNote, online, status, classFileName, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		local nameShort, realm, normalizedName = SplitNameRealm(name)
		local faction = GetRosterFactionByIndex(i)
		local race = GetRosterRaceByIndex(i)
		local memberKey = nil
		if type(guid) == "string" and guid ~= "" then
			memberKey = guid
		elseif normalizedName ~= "" then
			memberKey = "NAME:" .. normalizedName
		end
		if memberKey then
			out[memberKey] = {
				memberKey = memberKey,
				guid = (type(guid) == "string" and guid) or "",
				name = normalizedName,
				nameShort = nameShort,
				realm = realm,
				faction = faction,
				race = race,
				rank = tostring(rank or ""),
				rankIndex = tonumber(rankIndex) or 0,
				level = tonumber(level) or 0,
				class = tostring(class or ""),
				zone = tostring(zone or ""),
				note = tostring(note or ""),
				officerNote = tostring(officerNote or ""),
				online = online and true or false,
				status = status,
				classFileName = tostring(classFileName or ""),
			}
		end
	end
	return out
end

local function DiffRosterAndLog(prev, curr)
	prev = prev or {}
	curr = curr or {}
	local events = {}
	local consumedOld = {}

	local prevByGuid = {}
	local prevByName = {}
	for key, m in pairs(prev) do
		if type(m) == "table" then
			local guid = tostring(m.guid or "")
			local name = tostring(m.name or "")
			if guid ~= "" then prevByGuid[guid] = key end
			if name ~= "" then prevByName[name] = key end
		end
	end

	local function QueueEvent(kind, msg, data)
		events[#events + 1] = {
			kind = kind,
			msg = msg,
			data = data,
		}
	end

	for newKey, newM in pairs(curr) do
		local guid = tostring(newM and newM.guid or "")
		local oldKey = newKey
		local oldM = prev[oldKey]

		if not oldM and guid ~= "" and prevByGuid[guid] then
			oldKey = prevByGuid[guid]
			oldM = prev[oldKey]
		end
		if not oldM and type(newM) == "table" and tostring(newM.name or "") ~= "" and prevByName[newM.name] then
			oldKey = prevByName[newM.name]
			oldM = prev[oldKey]
		end

		if oldM and oldKey ~= newKey then
			MigrateHistoryKey(oldKey, newKey, newM.name)
		end

		if oldM then
			consumedOld[oldKey] = true
		end

		if not oldM then
			local history, isRejoin = MarkJoin(newKey, newM.name, true)
			if isRejoin then
				QueueEvent("REJOIN", T("GA_REJOIN", "%s rejoined the guild.", tostring(newM.name or newKey)), {
					guid = newKey,
					history = history,
				})
			else
				QueueEvent("JOIN", T("GA_JOIN", "%s joined the guild.", tostring(newM.name or newKey)), {
					guid = newKey,
					history = history,
				})
			end
		else
			EnsureHistoryEntry(newKey, newM.name)
			if oldM.nameShort ~= newM.nameShort then
				QueueEvent("NAME_CHANGE", T(
					"GA_NAME_CHANGED",
					"%s changed character name to %s.",
					tostring(oldM.nameShort or oldM.name or newKey),
					tostring(newM.nameShort or newM.name or newKey)
				), {
					guid = newKey,
					oldName = oldM.nameShort or oldM.name,
					newName = newM.nameShort or newM.name,
				})
			end
			if oldM.realm ~= newM.realm then
				QueueEvent("REALM_CHANGE", T(
					"GA_REALM_CHANGED",
					"%s changed realm from %s to %s.",
					tostring(newM.nameShort or newM.name or newKey),
					tostring(oldM.realm or "-"),
					tostring(newM.realm or "-")
				), {
					guid = newKey,
					name = newM.nameShort or newM.name,
					oldRealm = oldM.realm,
					newRealm = newM.realm,
				})
			end
			if oldM.faction ~= "" and newM.faction ~= "" and oldM.faction ~= newM.faction then
				QueueEvent("FACTION_CHANGE", T(
					"GA_FACTION_CHANGED",
					"%s changed faction from %s to %s.",
					tostring(newM.nameShort or newM.name or newKey),
					tostring(oldM.faction or "-"),
					tostring(newM.faction or "-")
				), {
					guid = newKey,
					name = newM.nameShort or newM.name,
					oldFaction = oldM.faction,
					newFaction = newM.faction,
				})
			end
			if oldM.race ~= "" and newM.race ~= "" and oldM.race ~= newM.race then
				QueueEvent("RACE_CHANGE", T(
					"GA_RACE_CHANGED",
					"%s changed race from %s to %s.",
					tostring(newM.nameShort or newM.name or newKey),
					tostring(oldM.race or "-"),
					tostring(newM.race or "-")
				), {
					guid = newKey,
					name = newM.nameShort or newM.name,
					oldRace = oldM.race,
					newRace = newM.race,
				})
			end
			if (tonumber(oldM.level) or 0) ~= (tonumber(newM.level) or 0) then
				QueueEvent("LEVEL_CHANGE", T(
					"GA_LEVEL_CHANGED",
					"%s changed level from %d to %d.",
					tostring(newM.nameShort or newM.name or newKey),
					tonumber(oldM.level) or 0,
					tonumber(newM.level) or 0
				), {
					guid = newKey,
					name = newM.nameShort or newM.name,
					oldLevel = tonumber(oldM.level) or 0,
					newLevel = tonumber(newM.level) or 0,
				})
			end
			if oldM.rankIndex ~= newM.rankIndex then
				if newM.rankIndex < oldM.rankIndex then
					QueueEvent("PROMOTE", T("GA_PROMOTE", "%s promoted (%s -> %s).", tostring(newM.name or newKey), tostring(oldM.rank or oldM.rankIndex), tostring(newM.rank or newM.rankIndex)))
				else
					QueueEvent("DEMOTE", T("GA_DEMOTE", "%s demoted (%s -> %s).", tostring(newM.name or newKey), tostring(oldM.rank or oldM.rankIndex), tostring(newM.rank or newM.rankIndex)))
				end
			end
			if oldM.online ~= newM.online then
				if newM.online then
					QueueEvent("ONLINE", T("GA_ONLINE", "%s is now online.", tostring(newM.name or newKey)))
				else
					QueueEvent("OFFLINE", T("GA_OFFLINE", "%s went offline.", tostring(newM.name or newKey)))
				end
			end
			if oldM.note ~= newM.note then
				QueueEvent("NOTE", T(
					"GA_NOTE_CHANGED_DETAIL",
					"%s updated public note (%s -> %s).",
					tostring(newM.name or newKey),
					tostring(oldM.note or "-"),
					tostring(newM.note or "-")
				))
			end
			if oldM.officerNote ~= newM.officerNote then
				QueueEvent("OFFICER_NOTE", T(
					"GA_OFFICER_NOTE_CHANGED_DETAIL",
					"%s updated officer note (%s -> %s).",
					tostring(newM.name or newKey),
					tostring(oldM.officerNote or "-"),
					tostring(newM.officerNote or "-")
				))
			end
		end
	end

	for oldKey, oldM in pairs(prev) do
		if not consumedOld[oldKey] and not curr[oldKey] then
			local history = MarkLeave(oldKey, oldM.name)
			QueueEvent("LEAVE", T("GA_LEAVE", "%s left the guild.", tostring(oldM.name or oldKey)), {
				guid = oldKey,
				history = history,
			})
		end
	end

	for i = 1, #events do
		local e = events[i]
		EmitEvent(e.kind, e.msg, e.data)
	end
end

function GuildLog:ScanGuildChanges()
	local curr = BuildCurrentRosterSnapshot()
	if type(IsInGuild) == "function" and IsInGuild() and self._snapshot and next(self._snapshot) ~= nil and next(curr) == nil then
		-- Avoid treating transient empty roster snapshots as mass-leaves.
		self:RequestRosterRefresh()
		return
	end
	if not self._snapshot then
		self._snapshot = curr
		SeedHistoryFromSnapshot(curr)
		if not self._baselineLogged then
			self._baselineLogged = true
			local entries = Entries() or {}
			if #entries == 0 then
				PushEntry("BASELINE", T("GA_BASELINE", "Initial guild snapshot captured (%d members).", tonumber(GetNumGuildMembers and GetNumGuildMembers() or 0)))
			end
		end
		LOCAL_LOG("DEBUG", "GuildLog baseline snapshot initialized", tostring(#(Entries() or {})))
		return
	end
	DiffRosterAndLog(self._snapshot, curr)
	self._snapshot = curr
end

function GuildLog:GetMemberHistory(guid)
	local hist = MemberHistory()
	if type(hist) ~= "table" then return nil end
	return hist[tostring(guid or "")]
end

function GuildLog:HasBeenInGuildBefore(guid)
	local h = self:GetMemberHistory(guid)
	if type(h) ~= "table" then return false end
	return (tonumber(h.joinCount) or 0) > 1 or (tonumber(h.rejoinCount) or 0) > 0
end

function GuildLog:RequestRosterRefresh()
	if C_GuildInfo and type(C_GuildInfo.GuildRoster) == "function" then
		C_GuildInfo.GuildRoster()
	elseif type(GuildRoster) == "function" then
		GuildRoster()
	end
end

function GuildLog:ScheduleScan(forceRefresh, immediate)
	if self._scanScheduled and not immediate then return end
	self._scanScheduled = true
	self._scanToken = (tonumber(self._scanToken) or 0) + 1
	local token = self._scanToken

	if forceRefresh then
		self:RequestRosterRefresh()
	end

	if immediate then
		self._scanScheduled = false
		self:ScanGuildChanges()
		if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
			C_Timer.After(0.35, function()
				if token ~= GuildLog._scanToken then return end
				GuildLog:ScanGuildChanges()
			end)
		end
		return
	end

	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(forceRefresh and 0.70 or 0.25, function()
			if token ~= GuildLog._scanToken then return end
			GuildLog._scanScheduled = false
			GuildLog:ScanGuildChanges()
			-- Second pass catches late roster cache updates (e.g. note edits).
			C_Timer.After(0.60, function()
				if token ~= GuildLog._scanToken then return end
				GuildLog:ScanGuildChanges()
			end)
		end)
	else
		self._scanScheduled = false
		self:ScanGuildChanges()
	end
end

local function RegisterPage()
	local ui = GMS and GMS.UI
	if not ui or type(ui.RegisterPage) ~= "function" then return false end
	if GuildLog._pageRegistered then return true end

	ui:RegisterPage(MODULE_NAME, 70, T("GA_PAGE_TITLE", "Guild Activity"), function(root, _, _)
		if type(root.ReleaseChildren) == "function" then
			pcall(root.ReleaseChildren, root)
		end

		if ui and type(ui.Header_BuildIconText) == "function" then
			ui:Header_BuildIconText({
				icon = "Interface\\Icons\\Achievement_Guildperk_EverybodysFriend",
				text = "|cff03A9F4" .. T("GA_HEADER_TITLE", "Guild Activity Log") .. "|r",
				subtext = T("GA_HEADER_SUB", "Tracks guild roster changes in a dedicated module log."),
			})
		end

		root:SetLayout("Fill")

		local wrapper = AceGUI:Create("SimpleGroup")
		wrapper:SetLayout("List")
		wrapper:SetFullWidth(true)
		wrapper:SetFullHeight(true)
		root:AddChild(wrapper)

		local controls = AceGUI:Create("SimpleGroup")
		controls:SetLayout("Flow")
		controls:SetFullWidth(true)
		wrapper:AddChild(controls)
		local updateStatusLine

		local cbChat = AceGUI:Create("CheckBox")
		cbChat:SetLabel(T("GA_CHAT_ECHO", "Post new entries in chat"))
		cbChat:SetWidth(260)
		local applyingChatState = false
		do
			applyingChatState = true
			cbChat:SetValue(GetEffectiveChatEcho())
			applyingChatState = false
		end
		cbChat:SetCallback("OnValueChanged", function(_, _, v)
			if applyingChatState then return end
			local newValue = SetChatEchoPersist(v and true or false, "UI")
			LOCAL_LOG("INFO", "GuildLog chatEcho effective", tostring(GetEffectiveChatEcho()), tostring(newValue))
			updateStatusLine(#(Entries() or {}))
		end)
		controls:AddChild(cbChat)

		local btnRefresh = AceGUI:Create("Button")
		btnRefresh:SetText(T("GA_REFRESH", "Refresh"))
		btnRefresh:SetWidth(120)
		btnRefresh:SetCallback("OnClick", function()
			GuildLog:RequestRosterRefresh()
			GuildLog:ScheduleScan()
		end)
		controls:AddChild(btnRefresh)

		local btnClear = AceGUI:Create("Button")
		btnClear:SetText(T("GA_CLEAR", "Clear"))
		btnClear:SetWidth(120)
		btnClear:SetCallback("OnClick", function()
			local entries = Entries()
			if type(entries) == "table" then
				wipe(entries)
				if not GuildLog._optionsBound then
					MarkPendingPersist("entries")
				end
			end
			SyncOptionsToScoped()
			if GuildLog._ui and type(GuildLog._ui.render) == "function" then
				GuildLog._ui.render()
			end
		end)
		controls:AddChild(btnClear)

		local statusLine = AceGUI:Create("Label")
		statusLine:SetFullWidth(true)
		statusLine:SetText("")
		wrapper:AddChild(statusLine)

		local scroller = AceGUI:Create("ScrollFrame")
		scroller:SetLayout("List")
		scroller:SetFullWidth(true)
		scroller:SetFullHeight(true)
		wrapper:AddChild(scroller)

		updateStatusLine = function(entriesCount)
			local opts = EnsureOptionsCompat()
			local guildKey = type(GMS.GetGuildStorageKey) == "function" and tostring(GMS:GetGuildStorageKey() or "-") or "-"
			local hist = type(opts) == "table" and opts.memberHistory or nil
			local histCount = 0
			if type(hist) == "table" then
				for _ in pairs(hist) do histCount = histCount + 1 end
			end
			local chatEcho = GetEffectiveChatEcho() and "|cff00ff00ON|r" or "|cffff4040OFF|r"
			statusLine:SetText(string.format(
				"|cffb0b0b0DB:|r %s  |cffb0b0b0Entries:|r %d  |cffb0b0b0History:|r %d  |cffb0b0b0Chat:|r %s",
				guildKey, tonumber(entriesCount) or 0, histCount, chatEcho
			))
		end

		local function render()
			EnsureOptionsCompat()
			local entries = Entries() or {}
			local opts = SyncOptionsToScoped() or EnsureOptionsCompat() or {}
			applyingChatState = true
			cbChat:SetValue(GetEffectiveChatEcho())
			applyingChatState = false
			GuildLog._uiRefreshToken = GuildLog._uiRefreshToken + 1
			local token = GuildLog._uiRefreshToken
			scroller:ReleaseChildren()
			updateStatusLine(#entries)

			local display = {}
			local startIdx = math.max(1, (#entries - UI_RENDER_LIMIT) + 1)
			for i = startIdx, #entries do
				display[#display + 1] = entries[i]
			end

			-- Fallback: reconstruct readable history rows when legacy installs have
			-- member history but no persisted activity entries yet.
			if #display == 0 and type(opts.memberHistory) == "table" and next(opts.memberHistory) ~= nil then
				local synth = {}
				for guid, h in pairs(opts.memberHistory) do
					if type(h) == "table" then
						local name = tostring(h.name or guid or "?")
						local firstTs = tonumber(h.firstTrackedAt) or 0
						local joinCount = tonumber(h.joinCount) or 0
						local leftCount = tonumber(h.leftCount) or 0
						local rejoinCount = tonumber(h.rejoinCount) or 0
						synth[#synth + 1] = {
							ts = firstTs,
							time = tostring(h.firstTrackedTime or "-"),
							kind = "HISTORY",
							msg = string.format("%s | joins:%d leaves:%d rejoins:%d", name, joinCount, leftCount, rejoinCount),
						}
					end
				end
				table.sort(synth, function(a, b) return (tonumber(a.ts) or 0) > (tonumber(b.ts) or 0) end)
				local limit = math.min(#synth, 300)
				for i = 1, limit do
					display[#display + 1] = synth[i]
				end
			end

			if #display == 0 then
				local empty = AceGUI:Create("Label")
				empty:SetFullWidth(true)
				empty:SetText("|cff9d9d9d" .. T("GA_EMPTY", "No guild activity entries yet.") .. "|r")
				scroller:AddChild(empty)
				if ui and type(ui.SetStatusText) == "function" then
					ui:SetStatusText(T("GA_STATUS_FMT", "Guild Activity: %d entries", 0))
				end
				return
			end

			local idx = #display
			local function addChunk()
				if token ~= GuildLog._uiRefreshToken then return end
				local added = 0
				while idx >= 1 and added < UI_RENDER_CHUNK_SIZE do
					local e = display[idx]
					local row = AceGUI:Create("SimpleGroup")
					row:SetFullWidth(true)
					row:SetLayout("Flow")

					local ts = AceGUI:Create("Label")
					ts:SetWidth(155)
					ts:SetText("|cffb0b0b0" .. tostring(e.time or "-") .. "|r")
					row:AddChild(ts)

					local kind = AceGUI:Create("Label")
					kind:SetWidth(110)
					kind:SetText("|cff03A9F4" .. tostring(e.kind or "INFO") .. "|r")
					row:AddChild(kind)

					local msg = AceGUI:Create("Label")
					msg:SetWidth(760)
					msg:SetText("|cffffffff" .. tostring(e.msg or "") .. "|r")
					row:AddChild(msg)

					scroller:AddChild(row)
					idx = idx - 1
					added = added + 1
				end
				if idx >= 1 and type(C_Timer) == "table" and type(C_Timer.After) == "function" then
					C_Timer.After(0, addChunk)
				end
			end
			addChunk()

			if ui and type(ui.SetStatusText) == "function" then
				ui:SetStatusText(T("GA_STATUS_FMT", "Guild Activity: %d entries", #display))
			end
		end

		GuildLog._ui = { render = render }
		render()
	end)

	GuildLog._pageRegistered = true
	return true
end

local function RegisterDock()
	local ui = GMS and GMS.UI
	if not ui or type(ui.AddRightDockIconTop) ~= "function" then return false end
	if GuildLog._dockRegistered then return true end

	ui:AddRightDockIconTop({
		id = MODULE_NAME,
		order = 70,
		selectable = true,
		icon = "Interface\\Icons\\Achievement_Guildperk_EverybodysFriend",
		tooltipTitle = T("GA_PAGE_TITLE", "Guild Activity"),
		tooltipText = T("GA_DOCK_TOOLTIP", "Open guild activity log"),
		onClick = function()
			if GMS.UI and type(GMS.UI.Open) == "function" then
				GMS.UI:Open(MODULE_NAME)
			end
		end,
	})

	GuildLog._dockRegistered = true
	return true
end

local function RegisterSlash()
	if type(GMS.Slash_RegisterSubCommand) ~= "function" then return false end
	GMS:Slash_RegisterSubCommand("guildlog", function()
		if GMS.UI and type(GMS.UI.Open) == "function" then
			GMS.UI:Open(MODULE_NAME)
		end
	end, {
		help = T("GA_SLASH_HELP", "/gms guildlog - opens guild activity log"),
		alias = { "glog" },
		owner = MODULE_NAME,
	})
	return true
end

function GuildLog:TryIntegrateUI()
	local okPage = RegisterPage()
	local okDock = RegisterDock()
	return okPage and okDock
end

function GuildLog:InitializeOptions()
	EnsureOptions()
	SyncOptionsToScoped()
end

function GuildLog:LogOptionsState(tag)
	local entries = Entries() or {}
	LOCAL_LOG(
		"INFO",
		"GuildLog options state",
		tostring(tag or "state"),
		"v=" .. tostring(METADATA.VERSION),
		"guildKey=" .. GetCurrentGuildKeySafe(),
		"chatEcho=" .. tostring(GetEffectiveChatEcho()),
		"bound=" .. tostring(self._optionsBound),
		"entries=" .. tostring(#entries)
	)
end

function GuildLog:OnEnable()
	self:InitializeOptions()
	self:LogOptionsState("OnEnable")
	self:TryIntegrateUI()
	RegisterSlash()

	if type(GMS.OnReady) == "function" then
		GMS:OnReady("EXT:UI", function()
			GuildLog:TryIntegrateUI()
		end)
		GMS:OnReady("EXT:SLASH", function()
			RegisterSlash()
		end)
	end

	self:RegisterEvent("GUILD_ROSTER_UPDATE", function()
		GuildLog:InitializeOptions()
		GuildLog:ScheduleScan(true, true)
	end)
	self:RegisterEvent("PLAYER_GUILD_UPDATE", function()
		GuildLog:InitializeOptions()
		GuildLog:ScheduleScan(true)
	end)

	self:RequestRosterRefresh()
	self:ScheduleScan(true, true)

	-- Retry options binding once after login in case DB became ready late.
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(1.0, function()
			GuildLog:InitializeOptions()
			GuildLog:LogOptionsState("Rebind+1s")
			if GuildLog._ui and type(GuildLog._ui.render) == "function" then
				GuildLog._ui.render()
			end
		end)
		C_Timer.After(3.0, function()
			GuildLog:InitializeOptions()
			GuildLog:LogOptionsState("Rebind+3s")
			if GuildLog._ui and type(GuildLog._ui.render) == "function" then
				GuildLog._ui.render()
			end
		end)
		C_Timer.After(8.0, function()
			GuildLog:InitializeOptions()
			GuildLog:LogOptionsState("Rebind+8s")
			if GuildLog._ui and type(GuildLog._ui.render) == "function" then
				GuildLog._ui.render()
			end
		end)
	end

	if not self._pollTicker and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
		self._pollTicker = C_Timer.NewTicker(15, function()
			GuildLog:RequestRosterRefresh()
			GuildLog:ScheduleScan(false)
		end)
	end

	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
	LOCAL_LOG("INFO", "GuildLog enabled")
end

function GuildLog:OnDisable()
	SyncOptionsToScoped()
	self:LogOptionsState("OnDisable")
	self._scanScheduled = false
	self._scanToken = (tonumber(self._scanToken) or 0) + 1
	local ticker = self._pollTicker
	if ticker and type(ticker["Cancel"]) == "function" then
		pcall(ticker["Cancel"], ticker)
	end
	self._pollTicker = nil
	self._ui = nil
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end
