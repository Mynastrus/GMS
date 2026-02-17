-- ============================================================================
--	GMS/Modules/Roster.lua
--	ROSTER-Module (Ace-only)
--	- KEIN _G, KEIN addonTable
--	- Zugriff auf GMS ausschliesslich ueber AceAddon Registry
--	- UI: Registriert Page + RightDock Icon
--	- Roster-View:
--		- Modular: Spalten per Column-Registry (jede Spalte eigene Build-Fn)
--		- Header: klickbar, aendert Sortierung (ASC/DESC Toggle)
--		- Erweiterbar: externe Spalten ueber Augmenter (GUID -> Zusatzdaten)
--		- Async Build: X Eintraege pro Frame (Token-Guard gegen alte Builds)
-- ============================================================================

local METADATA = {
	TYPE         = "MOD",
	INTERN_NAME  = "ROSTER",
	SHORT_NAME   = "Roster",
	DISPLAY_NAME = "Roster",
	VERSION      = "1.0.26",
}

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G                         = _G
local GetTime                    = GetTime
local time                       = time
local rawget                     = rawget
local C_Timer                    = C_Timer
local CreateFrame                = CreateFrame
local LoadAddOn                  = LoadAddOn
local GetGuildRosterInfo         = GetGuildRosterInfo
local GetGuildRosterLastOnline   = GetGuildRosterLastOnline
local GetNumGuildMembers         = GetNumGuildMembers
local GetFullRoster              = GetFullRoster -- Fallback or custom
local IsInGuild                  = IsInGuild
local GetGuildInfo               = GetGuildInfo
local C_GuildInfo                = C_GuildInfo
local GuildRoster                = GuildRoster
local GetRealmName               = GetRealmName
local GetNormalizedRealmName     = GetNormalizedRealmName
local UnitFactionGroup           = UnitFactionGroup
local UnitGUID                   = UnitGUID
local UnitName                   = UnitName
local UnitFullName               = UnitFullName
local UnitClass                  = UnitClass
local UnitLevel                  = UnitLevel
local GetAverageItemLevel        = GetAverageItemLevel
local GameTooltip                = GameTooltip
local UIParent                   = UIParent
local EasyMenu                   = EasyMenu
local UIDropDownMenu_Initialize  = UIDropDownMenu_Initialize
local UIDropDownMenu_AddButton   = UIDropDownMenu_AddButton
local ToggleDropDownMenu         = ToggleDropDownMenu
local ChatFrame_SendTell         = ChatFrame_SendTell
local ChatEdit_ChooseBoxForSend  = ChatEdit_ChooseBoxForSend
local ChatEdit_ActivateChat      = ChatEdit_ActivateChat
local InviteUnit                 = InviteUnit
local C_PartyInfo                = C_PartyInfo
local CLASS_ICON_TCOORDS         = CLASS_ICON_TCOORDS
local RAID_CLASS_COLORS          = RAID_CLASS_COLORS
local GameFontNormalSmall        = GameFontNormalSmall
local GameFontNormalSmallOutline = GameFontNormalSmallOutline
local GameFontNormalLarge        = GameFontNormalLarge
local GameFontNormal             = GameFontNormal
---@diagnostic enable: undefined-global

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

-- ---------------------------------------------------------------------------
--	Logging (buffered)
-- ---------------------------------------------------------------------------
GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		ts = (type(GetTime) == "function") and GetTime() or 0,
		level = tostring(level or "INFO"),
		type = tostring(METADATA.TYPE or "UNKNOWN"),
		source = tostring(METADATA.SHORT_NAME or "UNKNOWN"),
		msg = tostring(msg or ""),
		args = { ... },
	}

	local buffer = GMS._LOG_BUFFER
	local idx = #buffer + 1
	buffer[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		pcall(GMS._LOG_NOTIFY, entry, idx)
	end
end

local MODULE_NAME = "ROSTER"
local DISPLAY_NAME = "Roster"
local ACCOUNT_CHARS_SYNC_DOMAIN = "ACCOUNT_CHARS_V1"
local ACCOUNT_CHARS_PUBLISH_MIN_INTERVAL = 20

local Roster = GMS:GetModule(MODULE_NAME, true)
if not Roster then
	Roster = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
end

-- Registration
if GMS and type(GMS.RegisterModule) == "function" then
	GMS:RegisterModule(Roster, METADATA)
end

GMS[MODULE_NAME] = Roster

Roster._pageRegistered = Roster._pageRegistered or false
Roster._dockRegistered = Roster._dockRegistered or false

Roster._columns = Roster._columns or nil
Roster._augmenters = Roster._augmenters or nil
Roster._sortState = Roster._sortState or nil
Roster._defaultColumnsSeeded = Roster._defaultColumnsSeeded or false
Roster._buildToken = Roster._buildToken or 0
Roster._lastListParent = Roster._lastListParent or nil

-- Optimization: Table Pooling, Caches and GUID mapping
Roster._tablePool = Roster._tablePool or {}
Roster._guidToRow = Roster._guidToRow or {}
Roster._nameCache = Roster._nameCache or {}
Roster._lastRosterRequest = Roster._lastRosterRequest or 0
Roster._lastUpdateEvent = Roster._lastUpdateEvent or 0
Roster._lastGuidOrderSig = Roster._lastGuidOrderSig or ""
Roster._updateScheduled = Roster._updateScheduled or false
Roster._optionsRetryScheduled = Roster._optionsRetryScheduled or false
Roster._nameCacheCount = Roster._nameCacheCount or 0
Roster._memberMetaCache = Roster._memberMetaCache or {}
Roster._commInited = Roster._commInited or false
Roster._commTicker = Roster._commTicker or nil
Roster._lastMetaHeartbeat = Roster._lastMetaHeartbeat or 0
Roster._selfRosterOnline = Roster._selfRosterOnline or false

-- ###########################################################################
-- #	NAME NORMALIZATION
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Stellt sicher, dass ein Charname IMMER den Realm enthaelt
--	- "Name"        -> "Name-Realm"
--	- "Name-Realm"  -> "Name-Realm"
--
--	@param rawName string
--	@return string name_full, string name, string realm
-- ---------------------------------------------------------------------------
local function NormalizeCharacterNameWithRealm(rawName)
	if type(rawName) ~= "string" or rawName == "" then
		return "", "", ""
	end

	-- Cache Check
	if Roster._nameCache[rawName] then
		local c = Roster._nameCache[rawName]
		return c[1], c[2], c[3]
	end

	local name, realm = string.match(rawName, "^([^%-]+)%-(.+)$")

	if not name then
		name = rawName
		realm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
	end

	local name_full = name .. "-" .. realm

	-- Store in cache
	if not Roster._nameCache[rawName] then
		Roster._nameCacheCount = (Roster._nameCacheCount or 0) + 1
	end
	Roster._nameCache[rawName] = { name_full, name, realm }
	if (Roster._nameCacheCount or 0) > 4000 then
		wipe(Roster._nameCache)
		Roster._nameCacheCount = 0
	end

	return name_full, name, realm
end

-- ###########################################################################
-- #	GUILD DATA + MULTI SORT
-- ###########################################################################

local GetLastOnlineByRosterIndex

-- ---------------------------------------------------------------------------
--	Liest alle Gildenmitglieder und sortiert sie mehrstufig
--
--	@param sortSpec table|nil
--		- z. B. {
--			{ key = "rankIndex", desc = false },
--			{ key = "name", desc = false },
--		}
--	@return table
-- ---------------------------------------------------------------------------
local function GetAllGuildMembers(sortSpec, skipRequest)
	local members = {}

	if not IsInGuild() then
		return members
	end

	-- Request guild roster update (Throttled: Max once every 30s unless forced)
	local now = GetTime()
	if not skipRequest and (now - Roster._lastRosterRequest) > 30 then
		Roster._lastRosterRequest = now
		if C_GuildInfo and C_GuildInfo.GuildRoster then
			C_GuildInfo.GuildRoster()
		elseif GuildRoster then
			GuildRoster()
		end
	end

	-- Get total members count
	local total = 0
	if C_GuildInfo and C_GuildInfo.GetNumGuildMembers then
		total = C_GuildInfo.GetNumGuildMembers()
	elseif GetNumGuildMembers then
		total = GetNumGuildMembers()
	end

	if total == 0 then
		return members
	end

	local playerFaction = (type(UnitFactionGroup) == "function" and UnitFactionGroup("player")) or nil

	-- Collect members using pool
	local pool = Roster._tablePool
	local poolIdx = 1

	for i = 1, total do
		local name, rank, rankIndex, level, class, zone, note, officernote,
		online, status, classFileName, achievementPoints,
		achievementRank, isMobile, canSoR, repStanding,
		GUID

		if C_GuildInfo and C_GuildInfo.GetGuildRosterInfo then
			GUID = C_GuildInfo.GetGuildRosterInfo(i)
			if not GUID and GetGuildRosterInfo then
				name, rank, rankIndex, level, class, zone, note, officernote,
					online, status, classFileName, achievementPoints,
					achievementRank, isMobile, canSoR, repStanding,
					GUID = GetGuildRosterInfo(i)
			end
		elseif GetGuildRosterInfo then
			name, rank, rankIndex, level, class, zone, note, officernote,
				online, status, classFileName, achievementPoints,
				achievementRank, isMobile, canSoR, repStanding,
				GUID = GetGuildRosterInfo(i)
		end

		if name then
			local name_full, name_short, realm = NormalizeCharacterNameWithRealm(name)

			-- Get or create table from pool
			local m = pool[poolIdx]
			if m then
				wipe(m)
			else
				m = {}
				pool[poolIdx] = m
			end
			poolIdx = poolIdx + 1

			m.index = i
			m.name_roster = name
			m.name_full = name_full
			m.name = name_short
			m.realm = realm
			m.rank = rank
			m.rankIndex = rankIndex or 0
			m.level = level or 0
			m.class = class
			m.classFileName = classFileName
			m.faction = playerFaction
			m.zone = zone or ""
			m.online = online and true or false
			m.status = status
			m.guid = GUID
			m.note = note or ""
			m.officernote = officernote or ""

			local lastOnlineTs, lastOnlineText, lastOnlineHours = GetLastOnlineByRosterIndex(i, m.online)
			m.lastOnlineAt = lastOnlineTs
			m.lastOnlineText = lastOnlineText
			m.lastOnlineHours = lastOnlineHours or 0
			local meta = (GUID and Roster:GetMemberMeta(GUID)) or nil
			m.ilvl = (meta and tonumber(meta.ilvl)) or nil
			m.mplusScore = (meta and tonumber(meta.mplus)) or nil
			m.raidStatus = (meta and tostring(meta.raid or "")) or "-"
			if m.raidStatus == "" then m.raidStatus = "-" end
			m.gmsVersion = (meta and tostring(meta.version or "")) or "-"
			if m.gmsVersion == "" then m.gmsVersion = "-" end
			if m.guid and UnitGUID and m.guid == UnitGUID("player") and (m.gmsVersion == "-") then
				m.gmsVersion = tostring((GMS and GMS.VERSION) or "-")
			end

			-- Generate a Data Fingerprint for incremental updates
			m.fingerprint = string.format("%s:%d:%s:%s:%s:%s:%s:%s:%s:%s:%s",
				GUID or "no-guid", level or 0, rankIndex or 0,
				m.online and "1" or "0", tostring(status or ""), note or "",
				tostring(m.lastOnlineHours or 0), tostring(m.ilvl or "-"),
				tostring(m.mplusScore or "-"), tostring(m.raidStatus or "-"), tostring(m.gmsVersion or "-"))

			members[#members + 1] = m
		end
	end

	if type(sortSpec) == "table" and #sortSpec > 0 then
		table.sort(members, function(a, b)
			for _, spec in ipairs(sortSpec) do
				local key = spec.key
				local desc = spec.desc == true
				local va, vb = a[key], b[key]

				if va ~= vb then
					-- Keep unknown values stable at the end for both sort directions.
					if va == nil then return false end
					if vb == nil then return true end

					if type(va) == "boolean" then
						va, vb = (va and 1 or 0), (vb and 1 or 0)
					elseif type(va) == "string" then
						va, vb = va:lower(), vb:lower()
					elseif type(va) ~= type(vb) then
						va, vb = tostring(va), tostring(vb)
					end

					if desc then return va > vb else return va < vb end
				end
			end
			return a.index < b.index
		end)
	end

	return members
end

-- ###########################################################################
-- #	CLASS ICON + COLOR
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Gibt Icon Pfad fuer classFileName zurueck (fallback QuestionMark)
--	@param classFileName string
--	@return string
-- ---------------------------------------------------------------------------
local function GetClassIconPathFromClassFileName(classFileName)
	local map = {
		WARRIOR = "Warrior",
		PALADIN = "Paladin",
		HUNTER = "Hunter",
		ROGUE = "Rogue",
		PRIEST = "Priest",
		SHAMAN = "Shaman",
		MAGE = "Mage",
		WARLOCK = "Warlock",
		DRUID = "Druid",
		DEATHKNIGHT = "DeathKnight",
		MONK = "Monk",
		DEMONHUNTER = "DemonHunter",
		EVOKER = "Evoker",
	}

	local suffix = map[type(classFileName) == "string" and classFileName or ""]
	if not suffix then
		return "Interface\\Icons\\INV_Misc_QuestionMark"
	end

	return "Interface\\Icons\\ClassIcon_" .. suffix
end

-- ---------------------------------------------------------------------------
--	Erstellt ein AceGUI Icon fuer eine Klasse
--
--	@param classFileName string
--	@return AceGUIWidget|nil
-- ---------------------------------------------------------------------------
local function CreateClassIconWidget(classFileName)
	if type(classFileName) ~= "string" then return nil end

	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFileName] or nil
	if not coords then return nil end

	local icon = AceGUI:Create("Icon")
	icon:SetImage(GetClassIconPathFromClassFileName(classFileName))
	icon:SetImageSize(12, 12)
	icon:SetWidth(22)
	icon.frame:EnableMouse(false)
	icon.frame:SetScript("OnEnter", nil)
	icon.frame:SetScript("OnLeave", nil)

	return icon
end

-- ---------------------------------------------------------------------------
--	Gibt die Klassenfarbe fuer ein classFileName zurueck
--
--	@param classFileName string
--	@return number r, number g, number b, string hex
-- ---------------------------------------------------------------------------
local function GetClassColor(classFileName)
	if type(classFileName) ~= "string" then
		return 1, 1, 1, "CCCCCC"
	end

	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFileName] or nil
	if not c then
		return 1, 1, 1, "CCCCCC"
	end

	return c.r, c.g, c.b, c.colorStr
end

-- ###########################################################################
-- #	COLUMN REGISTRY + AUGMENTERS (EXTERNAL DATA)
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Registriert eine neue Spalte fuer den Roster (erweiterbar)
--
--	@param def table
--		- id string (unique)
--		- title string
--		- width number|nil
--		- order number|nil
--		- sortable boolean|nil
--		- sortKey string|nil (member field, muss existieren oder per Augmenter gesetzt werden)
--		- buildCellFn function(row:AceGUIWidget, member:table, ctx:table)
--	@return nil
-- ---------------------------------------------------------------------------
function Roster:API_RegisterRosterColumnDefinition(def)
	self._columns = self._columns or { order = {}, map = {} }
	if type(def) ~= "table" then return end

	local id = tostring(def.id or "")
	if id == "" then return end

	self._columns.map[id] = def

	local exists = false
	for _, v in ipairs(self._columns.order) do
		if v == id then
			exists = true
			break
		end
	end

	if not exists then
		table.insert(self._columns.order, id)
	end

	table.sort(self._columns.order, function(a, b)
		local da = self._columns.map[a]
		local db = self._columns.map[b]
		local oa = (da and tonumber(da.order)) or 9999
		local ob = (db and tonumber(db.order)) or 9999
		if oa == ob then
			return tostring(a) < tostring(b)
		end
		return oa < ob
	end)
end

-- ---------------------------------------------------------------------------
--	Registriert eine externe Member-Anreicherung (liefert Zusatzfelder per GUID)
--	- Jede Funktion darf member erweitern (member.someField = ...)
--	- Wird beim Build pro Member einmal aufgerufen
--
--	@param fn function(member:table, ctx:table)
--	@return nil
-- ---------------------------------------------------------------------------
function Roster:API_RegisterRosterMemberAugmenter(fn)
	self._augmenters = self._augmenters or {}
	if type(fn) ~= "function" then return end
	table.insert(self._augmenters, fn)
end

-- ---------------------------------------------------------------------------
--	Ruft alle Augmenter auf und reichert member an
--	@param member table
--	@param ctx table
--	@return nil
-- ---------------------------------------------------------------------------
local function ApplyRosterMemberAugmenters(member, ctx)
	if not Roster._augmenters then return end
	for _, fn in ipairs(Roster._augmenters) do
		pcall(fn, member, ctx)
	end
end

-- ###########################################################################
-- #	SORT STATE
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Initialisiert Sort-State
--	@return nil
-- ---------------------------------------------------------------------------
local function EnsureRosterSortState()
	Roster._sortState = Roster._sortState or { key = "online", desc = true }
end

-- ---------------------------------------------------------------------------
--	Setzt Sort-Key (toggle desc bei erneutem Klick)
--	@param key string
--	@return nil
-- ---------------------------------------------------------------------------
local function SetRosterSortKey(key)
	EnsureRosterSortState()

	key = tostring(key or "")
	if key == "" then return end

	if Roster._sortState.key == key then
		Roster._sortState.desc = not (Roster._sortState.desc == true)
	else
		Roster._sortState.key = key
		if key == "online" or key == "level" then
			Roster._sortState.desc = true
		else
			Roster._sortState.desc = false
		end
	end
end

-- ---------------------------------------------------------------------------
--	Erzeugt Multi-SortSpec basierend auf Sort-State + stabilen Fallbacks
--	@return table
-- ---------------------------------------------------------------------------
local function BuildRosterSortSpec()
	EnsureRosterSortState()

	local spec = {}
	spec[#spec + 1] = { key = Roster._sortState.key, desc = Roster._sortState.desc == true }

	if Roster._sortState.key ~= "online" then
		spec[#spec + 1] = { key = "online", desc = true }
	end
	if Roster._sortState.key ~= "rankIndex" then
		spec[#spec + 1] = { key = "rankIndex", desc = false }
	end
	if Roster._sortState.key ~= "name" then
		spec[#spec + 1] = { key = "name", desc = false }
	end

	return spec
end

local function GetPresenceState(member)
	if not member or not member.online then
		return "OFFLINE"
	end

	local st = member.status
	if type(st) == "number" then
		if st == 1 then return "AFK" end
		if st == 2 then return "DND" end
	elseif type(st) == "string" then
		local s = st:lower()
		if s:find("afk", 1, true) then return "AFK" end
		if s:find("dnd", 1, true) then return "DND" end
	end

	return "ONLINE"
end

local function BuildGuidOrderSignature(members)
	if type(members) ~= "table" or #members == 0 then
		return ""
	end
	local parts = {}
	for i = 1, #members do
		local m = members[i]
		parts[i] = (m and m.guid) or ("idx:" .. tostring(i))
	end
	return table.concat(parts, "|")
end

local function BuildLastOnlineText(years, months, days, hours)
	local y = tonumber(years) or 0
	local mo = tonumber(months) or 0
	local d = tonumber(days) or 0
	local h = tonumber(hours) or 0

	if y <= 0 and mo <= 0 and d <= 0 and h <= 0 then
		return "-"
	end
	if y > 0 then return string.format("%dy %dmo", y, mo) end
	if mo > 0 then return string.format("%dmo %dd", mo, d) end
	if d > 0 then return string.format("%dd %dh", d, h) end
	return string.format("%dh", h)
end

GetLastOnlineByRosterIndex = function(index, isOnline)
	if isOnline then
		return 0, "Online", 0
	end

	local y, mo, d, h
	if C_GuildInfo and type(C_GuildInfo.GetGuildRosterLastOnline) == "function" then
		y, mo, d, h = C_GuildInfo.GetGuildRosterLastOnline(index)
	elseif type(GetGuildRosterLastOnline) == "function" then
		y, mo, d, h = GetGuildRosterLastOnline(index)
	end

	local years = tonumber(y) or 0
	local months = tonumber(mo) or 0
	local days = tonumber(d) or 0
	local hours = tonumber(h) or 0
	local totalHours = (years * 365 * 24) + (months * 30 * 24) + (days * 24) + hours

	if totalHours <= 0 then
		return nil, "-", 0
	end

	local text = BuildLastOnlineText(years, months, days, hours)
	local ts = (type(time) == "function") and (time() - (totalHours * 3600)) or nil
	return ts, text, totalHours
end

function Roster:GetMemberMetaStore()
	local opts = self._options
	if type(opts) == "table" then
		opts.memberMeta = opts.memberMeta or {}
		return opts.memberMeta
	end
	self._memberMetaCache = self._memberMetaCache or {}
	return self._memberMetaCache
end

function Roster:GetMemberMeta(guid)
	if type(guid) ~= "string" or guid == "" then return nil end
	local store = self:GetMemberMetaStore()
	local e = store and store[guid]
	if type(e) ~= "table" then return nil end
	return e
end

function Roster:GetMemberGmsVersion(guid)
	local e = self:GetMemberMeta(guid)
	if type(e) ~= "table" then return nil end
	local v = tostring(e.version or "")
	if v == "" then return nil end
	return v
end

function Roster:SetMemberMeta(guid, meta, seenAt)
	if type(guid) ~= "string" or guid == "" then return false end
	if type(meta) ~= "table" then return false end

	local store = self:GetMemberMetaStore()
	local t = tonumber(seenAt) or (GetTime and GetTime()) or 0
	store[guid] = store[guid] or {}
	local row = store[guid]

	local v = tostring(meta.version or "")
	if v ~= "" then row.version = v end

	local ilvl = tonumber(meta.ilvl)
	if ilvl and ilvl > 0 then row.ilvl = ilvl end

	local mplus = tonumber(meta.mplus)
	if mplus and mplus >= 0 then row.mplus = mplus end

	local raid = tostring(meta.raid or "")
	if raid ~= "" then row.raid = raid end

	row.seenAt = t
	return true
end

local function BuildLocalPlayerNameData()
	local name, realm = nil, nil
	if type(UnitFullName) == "function" then
		local n, r = UnitFullName("player")
		if type(n) == "string" and n ~= "" then name = n end
		if type(r) == "string" and r ~= "" then realm = r end
	end
	if (not name or name == "") and type(UnitName) == "function" then
		local n = UnitName("player")
		if type(n) == "string" and n ~= "" then name = n end
	end
	if (not realm or realm == "") and type(GetNormalizedRealmName) == "function" then
		local r = GetNormalizedRealmName()
		if type(r) == "string" and r ~= "" then realm = r end
	end
	if (not realm or realm == "") and type(GetRealmName) == "function" then
		local r = GetRealmName()
		if type(r) == "string" and r ~= "" then realm = r end
	end

	name = tostring(name or "")
	realm = tostring(realm or "")
	if name == "" then
		return "", "", ""
	end
	if realm ~= "" then
		return name .. "-" .. realm, name, realm
	end
	return name, name, realm
end

local function GetCurrentGuildStorageKeySafe()
	if not IsInGuild or not IsInGuild() then
		return "", ""
	end

	local guildName = ""
	if type(GetGuildInfo) == "function" then
		local g = GetGuildInfo("player")
		if type(g) == "string" then
			guildName = g
		end
	end

	local guildKey = ""
	if type(GMS.GetGuildStorageKey) == "function" then
		local ok, key = pcall(GMS.GetGuildStorageKey, GMS)
		if ok and type(key) == "string" then
			guildKey = key
		end
	end

	if guildKey == "" and guildName ~= "" then
		local realm = (type(GetRealmName) == "function" and tostring(GetRealmName() or "")) or ""
		local faction = (type(UnitFactionGroup) == "function" and tostring(UnitFactionGroup("player") or "")) or ""
		if realm ~= "" and faction ~= "" then
			guildKey = string.format("%s|%s|%s", realm, faction, guildName)
		end
	end

	return guildKey, guildName
end

function Roster:GetAccountLinkStore()
	if GMS and type(GMS.InitializeStandardDatabases) == "function" then
		GMS:InitializeStandardDatabases(false)
	end
	if not GMS or type(GMS.db) ~= "table" or type(GMS.db.global) ~= "table" then
		return nil
	end

	local global = GMS.db.global
	global.accountLinks = type(global.accountLinks) == "table" and global.accountLinks or {}
	local links = global.accountLinks
	links.chars = type(links.chars) == "table" and links.chars or {}
	return links
end

local function BuildAccountCharsListForGuild(links, guildKey)
	local out = {}
	local key = tostring(guildKey or "")
	if key == "" then
		return out
	end
	if type(links) ~= "table" or type(links.chars) ~= "table" then
		return out
	end

	for guid, entry in pairs(links.chars) do
		if type(entry) == "table" and tostring(entry.guildKey or "") == key then
			out[#out + 1] = {
				guid = tostring(guid or ""),
				name_full = tostring(entry.name_full or entry.name or guid or "-"),
				name = tostring(entry.name or ""),
				realm = tostring(entry.realm or ""),
				level = tonumber(entry.level or 0) or 0,
				class = tostring(entry.class or "-"),
				classFile = tostring(entry.classFile or ""),
				guild = tostring(entry.guild or ""),
				guildKey = key,
				lastSeenAt = tonumber(entry.lastSeenAt or 0) or 0,
			}
		end
	end

	table.sort(out, function(a, b)
		return tostring(a.name_full or "") < tostring(b.name_full or "")
	end)

	return out
end

local function BuildAccountCharsDigest(guildKey, chars)
	local parts = { tostring(guildKey or "") }
	for i = 1, #chars do
		local row = chars[i]
		parts[#parts + 1] = string.format(
			"%s:%s:%s:%d:%s",
			tostring(row.guid or ""),
			tostring(row.name_full or ""),
			tostring(row.classFile or ""),
			tonumber(row.level or 0) or 0,
			tostring(row.guildKey or "")
		)
	end
	return table.concat(parts, "|")
end

local function BuildGuildVerifiedLinkedRows(roster, selectedGuid, chars, fallbackGuildKey, sourceLabel)
	local guid = tostring(selectedGuid or "")
	if guid == "" then
		return {}, false, "No character GUID available."
	end
	if type(chars) ~= "table" or #chars <= 0 then
		return {}, false, "No same-account guild characters recorded yet."
	end

	local selectedGuildKey = tostring(fallbackGuildKey or "")
	for i = 1, #chars do
		local row = chars[i]
		if type(row) == "table" and tostring(row.guid or "") == guid then
			local rowGuildKey = tostring(row.guildKey or "")
			if rowGuildKey ~= "" then
				selectedGuildKey = rowGuildKey
			end
			break
		end
	end
	if selectedGuildKey == "" then
		return {}, false, "Selected character has no guild link."
	end

	local currentGuildKey = select(1, GetCurrentGuildStorageKeySafe())
	if tostring(currentGuildKey or "") == "" or tostring(currentGuildKey or "") ~= selectedGuildKey then
		return {}, false, "Selected character is outside the current guild context."
	end

	local currentMember = roster:GetMemberByGUID(guid)
	if type(currentMember) ~= "table" then
		return {}, false, "Selected character is not currently in guild roster."
	end

	local rows = {}
	for i = 1, #chars do
		local entry = chars[i]
		if type(entry) == "table" then
			local otherGuid = tostring(entry.guid or "")
			local otherGuildKey = tostring(entry.guildKey or selectedGuildKey)
			if otherGuid ~= "" and otherGuid ~= guid and otherGuildKey == selectedGuildKey then
				local member = roster:GetMemberByGUID(otherGuid)
				if type(member) == "table" then
					rows[#rows + 1] = {
						guid = otherGuid,
						name_full = tostring(member.name_full or member.name or entry.name_full or entry.name or "-"),
						level = tonumber(member.level or entry.level or 0) or 0,
						class = tostring(member.class or entry.class or "-"),
						classFile = tostring(member.classFileName or entry.classFile or ""),
						online = member.online == true,
					}
				end
			end
		end
	end

	table.sort(rows, function(a, b)
		return tostring(a.name_full or "") < tostring(b.name_full or "")
	end)

	if #rows <= 0 then
		return rows, false, "No same-account guild characters currently in guild roster."
	end

	return rows, true, tostring(sourceLabel or "Account guild links (guild-verified)")
end

function Roster:PublishLocalAccountLinks(reason, force)
	local comm = GMS and GMS.Comm
	if type(comm) ~= "table" or type(comm.PublishRecord) ~= "function" then
		return false, "comm-unavailable"
	end

	local guid = (type(UnitGUID) == "function") and tostring(UnitGUID("player") or "") or ""
	if guid == "" then
		return false, "no-player-guid"
	end

	local links = self:GetAccountLinkStore()
	if type(links) ~= "table" or type(links.chars) ~= "table" then
		return false, "store-unavailable"
	end

	local base = links.chars[guid]
	if type(base) ~= "table" then
		return false, "player-row-missing"
	end

	local guildKey = tostring(base.guildKey or "")
	if guildKey == "" then
		return false, "no-guild"
	end

	local chars = BuildAccountCharsListForGuild(links, guildKey)
	if #chars <= 0 then
		return false, "no-same-guild-chars"
	end

	local digest = BuildAccountCharsDigest(guildKey, chars)
	local nowTs = (type(GetTime) == "function" and GetTime()) or 0
	local lastTs = tonumber(self._accountCharsLastPublishAt or 0) or 0
	local forcePublish = (force == true)

	if not forcePublish and (nowTs - lastTs) < ACCOUNT_CHARS_PUBLISH_MIN_INTERVAL then
		return false, "cooldown"
	end
	if not forcePublish and digest == tostring(self._accountCharsLastDigest or "") then
		return false, "unchanged"
	end

	local payload = {
		schema = 1,
		guildKey = guildKey,
		guild = tostring(base.guild or ""),
		sourceGuid = guid,
		reason = tostring(reason or "unknown"),
		chars = chars,
		characters = {},
	}
	for i = 1, #chars do
		payload.characters[#payload.characters + 1] = tostring(chars[i].name_full or chars[i].guid or "-")
	end

	local ok = comm:PublishRecord(ACCOUNT_CHARS_SYNC_DOMAIN, guid, payload, {
		updatedAt = nowTs,
	})
	if ok then
		self._accountCharsLastDigest = digest
		self._accountCharsLastPublishAt = nowTs
		LOCAL_LOG("INFO", "Account links published", tostring(#chars), tostring(reason or "unknown"))
		return true, "published"
	end
	return false, "publish-failed"
end

function Roster:TrackLocalAccountCharacter(reason)
	local guid = (type(UnitGUID) == "function") and tostring(UnitGUID("player") or "") or ""
	if guid == "" then return false end

	local links = self:GetAccountLinkStore()
	if type(links) ~= "table" or type(links.chars) ~= "table" then
		return false
	end

	local nameFull, name, realm = BuildLocalPlayerNameData()
	if nameFull == "" then
		nameFull = guid
	end

	local className, classFile = nil, nil
	if type(UnitClass) == "function" then
		className, classFile = UnitClass("player")
	end
	local level = (type(UnitLevel) == "function") and tonumber(UnitLevel("player") or 0) or 0

	local guildKey, guildName = GetCurrentGuildStorageKeySafe()
	guildKey = tostring(guildKey or "")
	guildName = tostring(guildName or "")

	links.chars[guid] = links.chars[guid] or {}
	local row = links.chars[guid]
	local changed = false

	local function SetTextField(key, value, countAsChange)
		local v = tostring(value or "")
		if tostring(row[key] or "") ~= v then
			row[key] = v
			if countAsChange ~= false then
				changed = true
			end
		end
	end

	local function SetNumberField(key, value)
		local v = tonumber(value) or 0
		if tonumber(row[key] or -1) ~= v then
			row[key] = v
			changed = true
		end
	end

	SetTextField("guid", guid)
	SetTextField("name", name)
	SetTextField("realm", realm)
	SetTextField("name_full", nameFull)
	SetTextField("class", className)
	SetTextField("classFile", classFile)
	SetNumberField("level", level)
	SetTextField("guild", guildName)
	SetTextField("guildKey", guildKey)
	-- Reason updates are operational metadata and should not count as structural row changes.
	SetTextField("lastSeenReason", tostring(reason or "unknown"), false)

	local nowTs = (type(time) == "function" and time()) or 0
	local oldSeenAt = tonumber(row.lastSeenAt or 0) or 0
	if changed or (tonumber(nowTs) or 0) - oldSeenAt >= 60 then
		row.lastSeenAt = tonumber(nowTs) or 0
	end

	if changed then
		LOCAL_LOG("INFO", "Local account character tracked", guid, nameFull, guildKey ~= "" and guildKey or "no-guild")
	end

	if tostring(reason or "") ~= "query" then
		self:PublishLocalAccountLinks(reason, changed)
	end

	return true
end

function Roster:GetSyncedAccountGuildCharactersForGuid(guid)
	local g = tostring(guid or "")
	if g == "" then
		return {}, false, "No character GUID available."
	end

	local comm = GMS and GMS.Comm
	if type(comm) ~= "table" or type(comm.GetRecordsByDomain) ~= "function" then
		return {}, false, "Comm record store unavailable."
	end

	local records = comm:GetRecordsByDomain(ACCOUNT_CHARS_SYNC_DOMAIN)
	if type(records) ~= "table" or #records <= 0 then
		return {}, false, "No synced account-link record found for selected character."
	end

	local best = nil
	local bestUpdated = -1
	local bestSeq = -1
	for i = 1, #records do
		local rec = records[i]
		if type(rec) == "table" and type(rec.payload) == "table" then
			local match = false
			if tostring(rec.charGUID or "") == g or tostring(rec.originGUID or "") == g then
				match = true
			else
				local chars = rec.payload.chars
				if type(chars) == "table" then
					for j = 1, #chars do
						local row = chars[j]
						if type(row) == "table" and tostring(row.guid or "") == g then
							match = true
							break
						end
					end
				end
			end

			if match then
				local updated = tonumber(rec.updatedAt) or 0
				local seq = tonumber(rec.seq) or 0
				if updated > bestUpdated or (updated == bestUpdated and seq > bestSeq) then
					best = rec
					bestUpdated = updated
					bestSeq = seq
				end
			end
		end
	end

	if type(best) ~= "table" or type(best.payload) ~= "table" then
		return {}, false, "No synced account-link record found for selected character."
	end

	return BuildGuildVerifiedLinkedRows(
		self,
		g,
		type(best.payload.chars) == "table" and best.payload.chars or {},
		tostring(best.payload.guildKey or ""),
		"Synced account guild links (guild-verified)"
	)
end

function Roster:GetLinkedAccountGuildCharactersForGuid(guid)
	local g = tostring(guid or "")
	if g == "" then
		return {}, false, "No character GUID available."
	end

	self:TrackLocalAccountCharacter("query")

	local links = self:GetAccountLinkStore()
	if type(links) == "table" and type(links.chars) == "table" then
		local base = links.chars[g]
		if type(base) == "table" then
			local guildKey = tostring(base.guildKey or "")
			local localChars = BuildAccountCharsListForGuild(links, guildKey)
			local rows, hasData, source = BuildGuildVerifiedLinkedRows(
				self,
				g,
				localChars,
				guildKey,
				"Local account guild links (guild-verified)"
			)
			if hasData then
				return rows, true, source
			end
			local syncedRows, syncedHasData, syncedSource = self:GetSyncedAccountGuildCharactersForGuid(g)
			if syncedHasData then
				return syncedRows, true, syncedSource
			end
			return rows, false, source
		end
	end

	local syncedRows, syncedHasData, syncedSource = self:GetSyncedAccountGuildCharactersForGuid(g)
	if syncedHasData then
		return syncedRows, true, syncedSource
	end
	return syncedRows, false, syncedSource
end

function Roster:SetMemberGmsVersion(guid, version, seenAt)
	if type(guid) ~= "string" or guid == "" then return false end
	local v = tostring(version or "")
	if v == "" then return false end

	return self:SetMemberMeta(guid, { version = v }, seenAt)
end

local BuildRaidStatusFromRaidsStore

local function BuildRaidStatusFromRaidsModule()
	local raids = GMS and (GMS:GetModule("RAIDS", true) or GMS:GetModule("Raids", true))
	if not raids or type(raids.GetAllRaids) ~= "function" then
		return "-"
	end

	local all = raids:GetAllRaids()
	if type(all) ~= "table" then return "-" end
	return BuildRaidStatusFromRaidsStore(all)
end

local function GetBestRaidProgressFromEntry(raidEntry)
	if type(raidEntry) ~= "table" then return nil end

	local best = nil
	local function consider(node)
		if type(node) ~= "table" then return end
		local short = tostring(node.short or "")
		if short == "" or short == "-" then return end
		local diff = tonumber(node.diffID) or 0
		local killed = tonumber(node.killed) or 0
		if not best or diff > best.diff or (diff == best.diff and killed > best.killed) then
			best = { diff = diff, killed = killed, short = short }
		end
	end

	consider(raidEntry.best)
	if type(raidEntry.current) == "table" then
		for _, cur in pairs(raidEntry.current) do
			consider(cur)
		end
	end

	return best
end

BuildRaidStatusFromRaidsStore = function(all)
	if type(all) ~= "table" then return "-" end

	local bestDiff = -1
	local bestKilled = -1
	local bestShort = "-"
	for _, raidEntry in pairs(all) do
		local b = GetBestRaidProgressFromEntry(raidEntry)
		if b and (b.diff > bestDiff or (b.diff == bestDiff and b.killed > bestKilled)) then
			bestDiff = b.diff
			bestKilled = b.killed
			bestShort = b.short
		end
	end
	return bestShort
end

local function BuildItemLevelFromEquipmentSnapshot(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.slots) ~= "table" then return nil end
	local total = 0
	local count = 0
	for _, item in pairs(snapshot.slots) do
		if type(item) == "table" then
			local ilvl = tonumber(item.itemLevel)
			if ilvl and ilvl > 0 then
				total = total + ilvl
				count = count + 1
			end
		end
	end
	if count <= 0 then return nil end
	return total / count
end

local function CollectLocalMetaPayload()
	local version = tostring((GMS and GMS.VERSION) or "")
	local ilvl, mplus = nil, nil
	local raid = "-"

	local equip = GMS and GMS:GetModule("Equipment", true)
	if equip and type(equip._options) == "table" and type(equip._options.equipment) == "table" then
		ilvl = BuildItemLevelFromEquipmentSnapshot(equip._options.equipment.snapshot)
	end
	if not ilvl and type(GetAverageItemLevel) == "function" then
		local _, equipped = GetAverageItemLevel()
		ilvl = tonumber(equipped)
	end

	local mythic = GMS and GMS:GetModule("MythicPlus", true)
	if mythic and type(mythic._options) == "table" then
		mplus = tonumber(mythic._options.score)
	end
	if not mplus and GMS and type(GMS.GetModuleOptions) == "function" then
		local ok, opts = pcall(GMS.GetModuleOptions, GMS, "MythicPlus")
		if ok and type(opts) == "table" then
			mplus = tonumber(opts.score)
		end
	end

	local raids = GMS and (GMS:GetModule("RAIDS", true) or GMS:GetModule("Raids", true))
	if raids and type(raids._options) == "table" and type(raids._options.raids) == "table" then
		raid = BuildRaidStatusFromRaidsStore(raids._options.raids)
	else
		raid = BuildRaidStatusFromRaidsModule()
	end

	return {
		version = (version ~= "" and version) or nil,
		ilvl = ilvl,
		mplus = mplus,
		raid = raid,
		best_in_raid = raid,
	}
end

function Roster:BroadcastMetaHeartbeat(force)
	local nowTs = (GetTime and GetTime()) or 0
	if not force and (nowTs - (self._lastMetaHeartbeat or 0)) < 10 then
		return false
	end

	local comm = GMS and GMS.Comm
	if not comm or type(comm.SendData) ~= "function" then return end

	local guid = (type(UnitGUID) == "function") and UnitGUID("player") or nil
	if not guid then return end

	local payload = CollectLocalMetaPayload()
	if type(payload) ~= "table" then return end

	self:SetMemberMeta(guid, payload, GetTime and GetTime() or 0)

	if type(comm.PublishCharacterRecord) == "function" then
		comm:PublishCharacterRecord("roster_meta", {
			version = payload.version,
			ilvl = payload.ilvl,
			mplus = payload.mplus,
			raid = payload.raid,
			best_in_raid = payload.best_in_raid,
		}, {
			updatedAt = (GetTime and GetTime()) or 0,
		})
	end

	comm:SendData("ROSTER_META", {
		guid = guid,
		version = payload.version,
		ilvl = payload.ilvl,
		mplus = payload.mplus,
		raid = payload.raid,
		best_in_raid = payload.best_in_raid,
		ts = (GetTime and GetTime()) or 0,
	}, "BULK", "GUILD")

	self._lastMetaHeartbeat = nowTs
	return true
end

function Roster:InitCommMetaSync()
	if self._commInited then return true end
	local comm = GMS and GMS.Comm
	if not comm or type(comm.RegisterPrefix) ~= "function" then
		return false
	end

	comm:RegisterPrefix("ROSTER_META", function(senderGUID, data, raw)
		if type(data) ~= "table" then return end
		local guid = senderGUID or data.guid
		local payload = {
			version = data.version or data.v,
			ilvl = data.ilvl,
			mplus = data.mplus,
			raid = data.raid or data.best_in_raid,
		}
		local seenAt = data.ts or (GetTime and GetTime()) or 0
		if Roster:SetMemberMeta(guid, payload, seenAt) then
			if GMS.UI and GMS.UI._page == METADATA.INTERN_NAME and Roster._lastListParent then
				Roster:API_RefreshRosterView()
			end
		end
	end)

	if type(comm.RegisterRecordListener) == "function" then
		local function RefreshRosterIfVisible()
			if GMS.UI and GMS.UI._page == METADATA.INTERN_NAME and Roster._lastListParent then
				Roster:API_RefreshRosterView()
			end
		end

		comm:RegisterRecordListener("roster_meta", function(record)
			if type(record) ~= "table" or type(record.originGUID) ~= "string" then return end
			local payload = record.payload
			if type(payload) ~= "table" then return end
			if Roster:SetMemberMeta(record.originGUID, {
				version = payload.version,
				ilvl = payload.ilvl,
				mplus = payload.mplus,
				raid = payload.raid or payload.best_in_raid,
			}, record.updatedAt or ((GetTime and GetTime()) or 0)) then
				RefreshRosterIfVisible()
			end
		end)

		comm:RegisterRecordListener("EQUIPMENT_V1", function(record)
			if type(record) ~= "table" or type(record.originGUID) ~= "string" then return end
			local payload = record.payload
			if type(payload) ~= "table" or type(payload.snapshot) ~= "table" then return end
			local ilvl = BuildItemLevelFromEquipmentSnapshot(payload.snapshot)
			if ilvl and Roster:SetMemberMeta(record.originGUID, {
				ilvl = ilvl,
			}, record.updatedAt or ((GetTime and GetTime()) or 0)) then
				RefreshRosterIfVisible()
			end
		end)

		comm:RegisterRecordListener("MYTHICPLUS_V1", function(record)
			if type(record) ~= "table" or type(record.originGUID) ~= "string" then return end
			local payload = record.payload
			if type(payload) ~= "table" then return end
			local mplus = tonumber(payload.score)
			if mplus and Roster:SetMemberMeta(record.originGUID, {
				mplus = mplus,
			}, record.updatedAt or ((GetTime and GetTime()) or 0)) then
				RefreshRosterIfVisible()
			end
		end)

		comm:RegisterRecordListener("RAIDS_V1", function(record)
			if type(record) ~= "table" or type(record.originGUID) ~= "string" then return end
			local payload = record.payload
			if type(payload) ~= "table" or type(payload.raids) ~= "table" then return end
			local raid = BuildRaidStatusFromRaidsStore(payload.raids)
			if raid ~= "" and raid ~= "-" and Roster:SetMemberMeta(record.originGUID, {
				raid = raid,
			}, record.updatedAt or ((GetTime and GetTime()) or 0)) then
				RefreshRosterIfVisible()
			end
		end)
	end

	if type(comm.GetRecordsByDomain) == "function" then
		local function HydrateDomain(domain, fn)
			local records = comm:GetRecordsByDomain(domain)
			if type(records) ~= "table" then return end
			for i = 1, #records do
				local rec = records[i]
				if type(rec) == "table" then
					pcall(fn, rec)
				end
			end
		end

		HydrateDomain("roster_meta", function(record)
			local payload = record.payload
			if type(payload) ~= "table" then return end
			Roster:SetMemberMeta(record.originGUID, {
				version = payload.version,
				ilvl = payload.ilvl,
				mplus = payload.mplus,
				raid = payload.raid or payload.best_in_raid,
			}, record.updatedAt or ((GetTime and GetTime()) or 0))
		end)

		HydrateDomain("EQUIPMENT_V1", function(record)
			local payload = record.payload
			if type(payload) ~= "table" or type(payload.snapshot) ~= "table" then return end
			local ilvl = BuildItemLevelFromEquipmentSnapshot(payload.snapshot)
			if ilvl then
				Roster:SetMemberMeta(record.originGUID, { ilvl = ilvl }, record.updatedAt or ((GetTime and GetTime()) or 0))
			end
		end)

		HydrateDomain("MYTHICPLUS_V1", function(record)
			local payload = record.payload
			if type(payload) ~= "table" then return end
			local mplus = tonumber(payload.score)
			if mplus then
				Roster:SetMemberMeta(record.originGUID, { mplus = mplus }, record.updatedAt or ((GetTime and GetTime()) or 0))
			end
		end)

		HydrateDomain("RAIDS_V1", function(record)
			local payload = record.payload
			if type(payload) ~= "table" or type(payload.raids) ~= "table" then return end
			local raid = BuildRaidStatusFromRaidsStore(payload.raids)
			if raid ~= "" and raid ~= "-" then
				Roster:SetMemberMeta(record.originGUID, { raid = raid }, record.updatedAt or ((GetTime and GetTime()) or 0))
			end
		end)
	end

	self._commInited = true

	if not self._commTicker and C_Timer and type(C_Timer.NewTicker) == "function" then
		self._commTicker = C_Timer.NewTicker(120, function()
			Roster:BroadcastMetaHeartbeat()
		end)
	end

	self:BroadcastMetaHeartbeat()
	return true
end

Roster._contextMenuFrame = Roster._contextMenuFrame or nil

local function OpenChatEditWithText(text)
	local t = tostring(text or "")
	if t == "" then return end

	local editBox = nil
	if type(ChatEdit_ChooseBoxForSend) == "function" then
		editBox = ChatEdit_ChooseBoxForSend()
	end
	if editBox and type(ChatEdit_ActivateChat) == "function" then
		ChatEdit_ActivateChat(editBox)
	end
	if editBox and type(editBox.SetText) == "function" then
		editBox:SetText(t)
		if type(editBox.HighlightText) == "function" then
			editBox:HighlightText()
		end
	end
end

local function TryInviteUnitByName(nameFull, nameShort)
	local full = tostring(nameFull or "")
	local short = tostring(nameShort or "")

	local function TryInvite(target)
		target = tostring(target or "")
		if target == "" then return false end

		if type(C_PartyInfo) == "table" and type(C_PartyInfo.InviteUnit) == "function" then
			local ok = pcall(C_PartyInfo.InviteUnit, target)
			if ok then return true end
		end
		if type(InviteUnit) == "function" then
			local ok = pcall(InviteUnit, target)
			if ok then return true end
		end
		return false
	end

	if TryInvite(full) then return true end
	if TryInvite(short) then return true end

	-- Fallback: short name parsed from full if needed.
	local parsedShort = full:match("^([^%-]+)")
	if parsedShort and parsedShort ~= short and TryInvite(parsedShort) then
		return true
	end

	return false
end

function Roster:ShowMemberContextMenu(anchorFrame, memberData)
	if type(memberData) ~= "table" then return end
	local nameFull = tostring(memberData.name_full or memberData.name or "")
	local nameShort = tostring(memberData.name or "")
	local nameRoster = tostring(memberData.name_roster or "")
	local targetName = (nameRoster ~= "" and nameRoster) or (nameFull ~= "" and nameFull) or nameShort
	local isOnline = memberData.online == true
	local isSelf = false
	if type(UnitGUID) == "function" and type(memberData.guid) == "string" and memberData.guid ~= "" then
		isSelf = (memberData.guid == UnitGUID("player"))
	end
	if targetName == "" then return end

	if type(EasyMenu) ~= "function" and type(LoadAddOn) == "function" then
		pcall(LoadAddOn, "Blizzard_UIDropDownMenu")
		EasyMenu = (type(_G) == "table" and rawget(_G, "EasyMenu")) or EasyMenu
		UIDropDownMenu_Initialize = (type(_G) == "table" and rawget(_G, "UIDropDownMenu_Initialize")) or UIDropDownMenu_Initialize
		UIDropDownMenu_AddButton = (type(_G) == "table" and rawget(_G, "UIDropDownMenu_AddButton")) or UIDropDownMenu_AddButton
		ToggleDropDownMenu = (type(_G) == "table" and rawget(_G, "ToggleDropDownMenu")) or ToggleDropDownMenu
	end

	if not self._contextMenuFrame and type(CreateFrame) == "function" then
		self._contextMenuFrame = CreateFrame("Frame", "GMSRosterMemberContextMenu", UIParent, "UIDropDownMenuTemplate")
	end
	if not self._contextMenuFrame then
		return
	end

	local menu = {
		{ text = targetName, isTitle = true, notCheckable = true },
		{
			text = (type(GMS.T) == "function" and GMS:T("ROSTER_CTX_WHISPER")) or "Whisper",
			notCheckable = true,
			func = function()
				OpenChatEditWithText("/w " .. targetName .. " ")
			end,
		},
		{
			text = (type(GMS.T) == "function" and GMS:T("ROSTER_CTX_COPY_NAME")) or "Copy name (with realm)",
			notCheckable = true,
			func = function()
				OpenChatEditWithText((nameFull ~= "" and nameFull) or targetName)
			end,
		},
		{
			text = (type(GMS.T) == "function" and GMS:T("ROSTER_CTX_INVITE")) or "Invite to group",
			notCheckable = true,
			disabled = isSelf,
			func = function()
				if isSelf then return end
				if isOnline and TryInviteUnitByName(targetName, nameShort) then
					return
				end
				OpenChatEditWithText("/invite " .. targetName)
			end,
		},
	}

	if type(EasyMenu) == "function" then
		EasyMenu(menu, self._contextMenuFrame, "cursor", 0, 0, "MENU")
		return
	end

	-- Fallback path if EasyMenu is still unavailable.
	if type(UIDropDownMenu_Initialize) == "function"
		and type(UIDropDownMenu_AddButton) == "function"
		and type(ToggleDropDownMenu) == "function" then
		UIDropDownMenu_Initialize(self._contextMenuFrame, function(_, level)
			if level ~= 1 then return end
			for i = 1, #menu do
				UIDropDownMenu_AddButton(menu[i], level)
			end
		end, "MENU")
		ToggleDropDownMenu(1, nil, self._contextMenuFrame, "cursor", 0, 0)
	end
end

-- Forward declaration (used by async builder before actual definition below)
local FilterMembersByVisibility
local UpdateRosterStatus

-- ###########################################################################
-- #	CELL BUILDERS (EINE FUNKTION PRO SPALTE)
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Spalte: Klassen-Icon
--	@param row AceGUIWidget
--	@param member table
--	@param ctx table
--	@return nil
-- ---------------------------------------------------------------------------
local function BuildCell_ClassIcon(row, member, ctx)
	local icon = CreateClassIconWidget(member.classFileName)
	if icon then
		row:AddChild(icon)
	end
end

local function BuildCell_PresenceDot(row, member, ctx)
	local state = GetPresenceState(member)
	local iconPath = "Interface\\FriendsFrame\\StatusIcon-Offline"
	local tooltip = (type(GMS.T) == "function" and GMS:T("ROSTER_STATUS_OFFLINE")) or "Offline"
	if state == "ONLINE" then
		iconPath = "Interface\\FriendsFrame\\StatusIcon-Online"
		tooltip = (type(GMS.T) == "function" and GMS:T("ROSTER_STATUS_ONLINE")) or "Online"
	elseif state == "AFK" then
		iconPath = "Interface\\FriendsFrame\\StatusIcon-Away"
		tooltip = (type(GMS.T) == "function" and GMS:T("ROSTER_STATUS_AWAY")) or "Away"
	elseif state == "DND" then
		iconPath = "Interface\\FriendsFrame\\StatusIcon-DnD"
		tooltip = (type(GMS.T) == "function" and GMS:T("ROSTER_STATUS_BUSY")) or "Busy"
	end

	local icon = AceGUI:Create("Icon")
	icon:SetImage(iconPath)
	icon:SetImageSize(10, 10)
	icon:SetWidth(14)
	icon:SetHeight(10)
	if icon.image then
		icon.image:ClearAllPoints()
		icon.image:SetPoint("CENTER", icon.frame, "CENTER", 0, 0)
	end
	if icon.frame then
		icon.frame:EnableMouse(true)
		icon.frame:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(tooltip, 1, 1, 1)
			GameTooltip:Show()
		end)
		icon.frame:SetScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
	end
	row:AddChild(icon)
end

local function BuildCell_FactionIcon(row, member, ctx)
	local faction = tostring(member and member.faction or "")
	local letter = "N"
	local color = "AAD372" -- hunter-like green for neutral
	local tooltip = (type(GMS.T) == "function" and GMS:T("ROSTER_FACTION_NEUTRAL")) or "Neutral"
	if faction == "Alliance" then
		letter = "A"
		color = "3FC7FF" -- alliance blue
		tooltip = (type(GMS.T) == "function" and GMS:T("ROSTER_FACTION_ALLIANCE")) or "Alliance"
	elseif faction == "Horde" then
		letter = "H"
		color = "FF4D4D" -- horde red
		tooltip = (type(GMS.T) == "function" and GMS:T("ROSTER_FACTION_HORDE")) or "Horde"
	end

	local lbl = AceGUI:Create("Label")
	lbl:SetText("|cff" .. color .. letter .. "|r")
	lbl:SetWidth(16)
	if lbl.label then
		lbl.label:SetFontObject(GameFontNormalSmallOutline)
		lbl.label:SetJustifyH("CENTER")
		lbl.label:SetJustifyV("MIDDLE")
	end
	if lbl.frame then
		lbl.frame:EnableMouse(true)
		lbl.frame:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText((type(GMS.T) == "function" and GMS:T("ROSTER_FACTION_TITLE")) or "Faction", 1, 1, 1)
			GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8)
			GameTooltip:Show()
		end)
		lbl.frame:SetScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
	end
	row:AddChild(lbl)
end

-- ---------------------------------------------------------------------------
--	Spalte: Level
--	@param row AceGUIWidget
--	@param member table
--	@param ctx table
--	@return nil
-- ---------------------------------------------------------------------------
local function BuildCell_Level(row, member, ctx)
	local LEVEL = AceGUI:Create("Label")
	LEVEL:SetText(tostring(member.level or ""))
	LEVEL.label:SetFontObject(GameFontNormalSmallOutline)
	LEVEL.label:SetJustifyH("CENTER")
	LEVEL:SetWidth(24)
	row:AddChild(LEVEL)
end

-- ---------------------------------------------------------------------------
--	Spalte: Name (InteractiveLabel mit Hover + Click -> CHARINFO)
--	@param row AceGUIWidget
--	@param member table
--	@param ctx table
--	@return nil
-- ---------------------------------------------------------------------------
local function BuildCell_Name(row, member, ctx)
	local _, _, _, hex = GetClassColor(member.classFileName)

	local MEMBER_NAME = AceGUI:Create("Label")
	MEMBER_NAME:SetText("|c" .. hex .. tostring(member.name or "") .. "|r")
	MEMBER_NAME.label:SetFontObject(GameFontNormalSmallOutline)
	MEMBER_NAME:SetWidth(125)
	row:AddChild(MEMBER_NAME)
end

-- ---------------------------------------------------------------------------
--	Spalte: Realm
--	@param row AceGUIWidget
--	@param member table
--	@param ctx table
--	@return nil
-- ---------------------------------------------------------------------------
local function BuildCell_Realm(row, member, ctx)
	local REALM = AceGUI:Create("Label")
	REALM:SetText(tostring(member.realm or ""))
	REALM.label:SetFontObject(GameFontNormalSmallOutline)
	REALM:SetWidth(90)
	row:AddChild(REALM)
end

-- ---------------------------------------------------------------------------
--	Spalte: Zone
--	@param row AceGUIWidget
--	@param member table
--	@param ctx table
--	@return nil
-- ---------------------------------------------------------------------------
local function BuildCell_Zone(row, member, ctx)
	local ZONE = AceGUI:Create("Label")
	ZONE:SetText(tostring(member.zone or ""))
	ZONE.label:SetFontObject(GameFontNormalSmallOutline)
	ZONE:SetWidth(220)
	row:AddChild(ZONE)
end

local function BuildCell_LastOnline(row, member, ctx)
	local txt = tostring((member and member.lastOnlineText) or "-")
	local lbl = AceGUI:Create("Label")
	lbl:SetText(txt)
	lbl.label:SetFontObject(GameFontNormalSmallOutline)
	lbl.label:SetJustifyH("RIGHT")
	lbl:SetWidth(80)
	row:AddChild(lbl)
end

local function BuildCell_iLvl(row, member, ctx)
	local n = tonumber(member and member.ilvl)
	local txt = (n and string.format("%.1f", n)) or "-"
	local lbl = AceGUI:Create("Label")
	lbl:SetText(txt)
	lbl.label:SetFontObject(GameFontNormalSmallOutline)
	lbl.label:SetJustifyH("RIGHT")
	lbl:SetWidth(45)
	row:AddChild(lbl)
end

local function BuildCell_MPlus(row, member, ctx)
	local n = tonumber(member and member.mplusScore)
	local txt = (n and tostring(math.floor(n + 0.5))) or "-"
	local lbl = AceGUI:Create("Label")
	lbl:SetText(txt)
	lbl.label:SetFontObject(GameFontNormalSmallOutline)
	lbl.label:SetJustifyH("RIGHT")
	lbl:SetWidth(45)
	row:AddChild(lbl)
end

local function BuildCell_RaidStatus(row, member, ctx)
	local txt = tostring((member and member.raidStatus) or "-")
	local lbl = AceGUI:Create("Label")
	lbl:SetText(txt)
	lbl.label:SetFontObject(GameFontNormalSmallOutline)
	lbl.label:SetJustifyH("RIGHT")
	lbl:SetWidth(70)
	row:AddChild(lbl)
end

local function BuildCell_GmsVersion(row, member, ctx)
	local v = tostring((member and member.gmsVersion) or "-")
	if v == "" then v = "-" end
	local lbl = AceGUI:Create("Label")
	if v ~= "-" then
		lbl:SetText("|cff7CFC00" .. v .. "|r")
	else
		lbl:SetText("|cff8a8a8a-|r")
	end
	lbl.label:SetFontObject(GameFontNormalSmallOutline)
	lbl.label:SetJustifyH("RIGHT")
	lbl:SetWidth(60)
	row:AddChild(lbl)
end

-- ###########################################################################
-- #	DEFAULT COLUMNS SEED
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Registriert Default-Spalten (einmalig)
--	@return nil
-- ---------------------------------------------------------------------------
local function EnsureDefaultRosterColumnsRegistered()
	if Roster._defaultColumnsSeeded then return end
	Roster._defaultColumnsSeeded = true

	Roster:API_RegisterRosterColumnDefinition({
		id = "presence",
		title = "",
		width = 14,
		order = 5,
		sortable = false,
		buildCellFn = BuildCell_PresenceDot,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "class",
		title = "",
		width = 22,
		order = 10,
		sortable = false,
		buildCellFn = BuildCell_ClassIcon,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "level",
		title = "Lvl",
		titleKey = "ROSTER_COL_LEVEL",
		width = 24,
		order = 15,
		sortable = true,
		sortKey = "level",
		buildCellFn = BuildCell_Level,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "name",
		title = "Name",
		titleKey = "ROSTER_COL_NAME",
		width = 125,
		order = 20,
		sortable = true,
		sortKey = "name",
		buildCellFn = BuildCell_Name,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "realm",
		title = "Realm",
		titleKey = "ROSTER_COL_REALM",
		width = 90,
		order = 30,
		sortable = true,
		sortKey = "realm",
		buildCellFn = BuildCell_Realm,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "lastOnline",
		title = "Last online",
		titleKey = "ROSTER_COL_LAST_ONLINE",
		width = 80,
		order = 40,
		sortable = true,
		sortKey = "lastOnlineHours",
		buildCellFn = BuildCell_LastOnline,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "ilvl",
		title = "iLvl",
		titleKey = "ROSTER_COL_ILVL",
		width = 45,
		order = 50,
		sortable = true,
		sortKey = "ilvl",
		buildCellFn = BuildCell_iLvl,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "mplus",
		title = "M+",
		titleKey = "ROSTER_COL_MPLUS",
		width = 45,
		order = 60,
		sortable = true,
		sortKey = "mplusScore",
		buildCellFn = BuildCell_MPlus,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "raidStatus",
		title = "Raid",
		titleKey = "ROSTER_COL_RAID",
		width = 70,
		order = 70,
		sortable = true,
		sortKey = "raidStatus",
		buildCellFn = BuildCell_RaidStatus,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "gmsVersion",
		title = "GMS",
		titleKey = "ROSTER_COL_GMS",
		width = 60,
		order = 80,
		sortable = true,
		sortKey = "gmsVersion",
		buildCellFn = BuildCell_GmsVersion,
	})
end

-- ###########################################################################
-- #	HEADER UI
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Baut die Header-Zeile anhand Column-Registry
--	@param parent AceGUIWidget
--	@param rebuildFn function()
--	@return nil
-- ---------------------------------------------------------------------------
local function BuildRosterHeaderRow(parent, rebuildFn)
	if not parent or type(parent.AddChild) ~= "function" then return end
	if not Roster._columns or not Roster._columns.order then return end

	EnsureRosterSortState()
	local function IsRightAlignedColumn(colId)
		return colId == "lastOnline"
			or colId == "ilvl"
			or colId == "mplus"
			or colId == "raidStatus"
			or colId == "gmsVersion"
	end

	local header = AceGUI:Create("SimpleGroup")
	header:SetFullWidth(true)
	header:SetLayout("Flow")
	header:SetHeight(18)
	parent:AddChild(header)

	for _, colId in ipairs(Roster._columns.order) do
		local def = Roster._columns.map[colId]
		if def then
			local title = tostring(def.title or colId)
			if type(def.titleKey) == "string" and def.titleKey ~= "" and type(GMS.T) == "function" then
				local localized = tostring(GMS:T(def.titleKey))
				if localized ~= "" and localized ~= def.titleKey then
					title = localized
				end
			end
			local w = tonumber(def.width) or 80

			if def.sortable == true and type(def.sortKey) == "string" and def.sortKey ~= "" then
				local lbl = AceGUI:Create("InteractiveLabel")

				local arrow = ""
				if Roster._sortState.key == def.sortKey then
					arrow = (Roster._sortState.desc == true) and " |cffffd100[v]|r" or " |cffffd100[^]|r"
				end

				lbl:SetText("|cffc8c8c8" .. title .. "|r" .. arrow)
				lbl.label:SetFontObject(GameFontNormalSmallOutline)
				lbl.label:SetJustifyH(IsRightAlignedColumn(colId) and "RIGHT" or "LEFT")
				lbl:SetWidth(w)

				local bg = lbl.frame:CreateTexture(nil, "BACKGROUND")
				bg:SetAllPoints(lbl.frame)
				bg:SetColorTexture(1, 1, 1, 0.08)
				bg:Hide()

				lbl:SetCallback("OnLeave", function() bg:Hide() end)
				lbl:SetCallback("OnEnter", function()
					bg:Show()
					if GameTooltip then GameTooltip:Hide() end
				end)
				lbl:SetCallback("OnClick", function(_, _, mouseButton)
					if mouseButton ~= "LeftButton" then return end
					SetRosterSortKey(def.sortKey)
					if type(rebuildFn) == "function" then
						rebuildFn()
					end
				end)

				header:AddChild(lbl)
			else
				local lbl = AceGUI:Create("Label")
				lbl:SetText("|cffc8c8c8" .. title .. "|r")
				lbl.label:SetFontObject(GameFontNormalSmallOutline)
				lbl.label:SetJustifyH(IsRightAlignedColumn(colId) and "RIGHT" or "LEFT")
				lbl:SetWidth(w)
				if lbl.frame and type(lbl.frame.SetScript) == "function" then
					lbl.frame:EnableMouse(true)
					lbl.frame:SetScript("OnEnter", function()
						if GameTooltip then GameTooltip:Hide() end
					end)
				end
				header:AddChild(lbl)
			end
		end
	end
end

-- ###########################################################################
-- #	ASYNC LIST BUILD
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Baut Guild-Roster-Labels asynchron (X Eintraege pro Frame)
--	- Nutzt Column-Registry + Header + SortState
--	- Ruft externe Augmenter fuer Zusatzspalten auf (GUID -> member.someField)
--
--	@param parent AceGUIWidget
--	@param perFrame number
--	@return nil
-- ---------------------------------------------------------------------------
local function BuildGuildRosterLabelsAsync(parent, perFrame, delay)
	if not parent or type(parent.AddChild) ~= "function" then return end

	EnsureDefaultRosterColumnsRegistered()
	EnsureRosterSortState()

	perFrame = tonumber(perFrame) or 10
	delay = tonumber(delay) or 0.05
	if perFrame < 1 then perFrame = 1 end
	if delay < 0 then delay = 0 end

	Roster._buildToken = (Roster._buildToken or 0) + 1
	local myToken = Roster._buildToken
	local myNavToken = (GMS.UI and GMS.UI._navToken) or 0

	if type(parent.ReleaseChildren) == "function" then
		parent:ReleaseChildren()
	end

	-- Clear GUID mapping on full rebuild
	wipe(Roster._guidToRow)

	local function Rebuild()
		BuildGuildRosterLabelsAsync(parent, perFrame, delay)
		parent:DoLayout()
	end

	BuildRosterHeaderRow(parent, Rebuild)

	local allMembers = GetAllGuildMembers(BuildRosterSortSpec())
	local totalMembers = #allMembers
	local members = FilterMembersByVisibility(allMembers)
	UpdateRosterStatus(#members, totalMembers)
	Roster._lastGuidOrderSig = BuildGuidOrderSignature(members)
	if not members or #members == 0 then
		local empty = AceGUI:Create("Label")
		empty:SetText((type(GMS.T) == "function" and GMS:T("ROSTER_EMPTY")) or "No guild members found.")
		empty:SetFullWidth(true)
		parent:AddChild(empty)
		parent:DoLayout()
		return
	end

	local index = 1
	local total = #members

	local ctx = {
		ui = (GMS and (GMS.UI or GMS:GetModule("UI", true))) or nil,
	}

	local function ForceFinalLayoutPass()
		if parent and type(parent.DoLayout) == "function" then
			parent:DoLayout()
		end
		local p1 = parent and parent.parent or nil
		if p1 and type(p1.DoLayout) == "function" then
			p1:DoLayout()
		end
		local p2 = p1 and p1.parent or nil
		if p2 and type(p2.DoLayout) == "function" then
			p2:DoLayout()
		end
	end

	local function Step()
		if myToken ~= Roster._buildToken then
			return
		end
		if GMS.UI and GMS.UI._navToken ~= myNavToken then
			return
		end

		local created = 0
		while index <= total and created < perFrame do
			local m = members[index]
			if m then
				ApplyRosterMemberAugmenters(m, ctx)

				local row = AceGUI:Create("SimpleGroup")
				row:SetFullWidth(true)
				row:SetLayout("Flow")
				row:SetHeight(24)
				if type(row.SetAutoAdjustHeight) == "function" then
					row:SetAutoAdjustHeight(false)
				end
				parent:AddChild(row)

				if row.frame then
					local rowGuid = m.guid
					local rowNameFull = m.name_full
					local rowName = m.name or "-"
					local rowNameRoster = m.name_roster or rowNameFull or rowName
					local rowLevel = m.level or "-"
					local rowClass = m.class or "-"
					local rowRealm = m.realm or "-"
					local rowClassFile = m.classFileName
					local rowLastOnline = m.lastOnlineText or "-"
					local rowILvl = m.ilvl and string.format("%.1f", m.ilvl) or "-"
					local rowMPlus = m.mplusScore and tostring(math.floor((m.mplusScore or 0) + 0.5)) or "-"
					local rowRaid = m.raidStatus or "-"
					local rowGms = m.gmsVersion or "-"
					local rowPublicNote = tostring(m.note or "")
					local rowOfficerNote = tostring(m.officernote or "")
					local rowStatus = GetPresenceState(m)
					row.frame:EnableMouse(true)

					local hover = row.frame:CreateTexture(nil, "BACKGROUND")
					hover:SetAllPoints(row.frame)
					hover:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
					hover:SetBlendMode("ADD")
					hover:SetAlpha(0.35)
					hover:Hide()

					row.frame:SetScript("OnEnter", function(self)
						if not (GMS.UI and GMS.UI._page == METADATA.INTERN_NAME) then
							if GameTooltip then GameTooltip:Hide() end
							return
						end
						hover:Show()
						if GameTooltip then
							local _, _, _, classHex = GetClassColor(rowClassFile)
							local statusText = "Offline"
							if rowStatus == "ONLINE" then
								statusText = "Online"
							elseif rowStatus == "AFK" then
								statusText = "Away"
							elseif rowStatus == "DND" then
								statusText = "Busy"
							end

							local displayRealm = tostring(rowRealm or "-")
							local localNormRealm = (type(GetNormalizedRealmName) == "function" and tostring(GetNormalizedRealmName() or "")) or ""
							if displayRealm == localNormRealm and type(GetRealmName) == "function" then
								displayRealm = tostring(GetRealmName() or displayRealm)
							end
							displayRealm = displayRealm:gsub("%-", " ")

							local classColor = tostring(classHex or "FFFFFFFF")
							if #classColor == 8 then
								classColor = classColor:sub(3) -- drop alpha when using |cffRRGGBB
							end
							local function TT_Row(labelText, valueText)
								local label = tostring(labelText or "")
								local value = tostring(valueText or "-")
								if GameTooltip.AddDoubleLine then
									GameTooltip:AddDoubleLine(label, value, 0.62, 0.62, 0.62, 1.0, 1.0, 1.0)
								else
									GameTooltip:AddLine(string.format("|cff9d9d9d%s|r |cffffffff%s|r", label, value))
								end
							end

							GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
							GameTooltip:SetText(string.format("|cff%s%s|r", classColor, tostring(rowName)))
							GameTooltip:AddLine(" ")
							TT_Row("Status", statusText)
							TT_Row("Level/Class", string.format("%s %s", tostring(rowLevel), tostring(rowClass)))
							TT_Row("Realm", displayRealm)
							TT_Row("Öffentliche Notiz", (rowPublicNote ~= "" and rowPublicNote) or "-")
							if rowOfficerNote ~= "" then
								TT_Row("Offiziersnotiz", rowOfficerNote)
							end
							if rowGuid and rowGuid ~= "" then
								GameTooltip:AddLine(" ")
								local guidLabel = (type(GMS.T) == "function" and GMS:T("ROSTER_GUID_LABEL", "GUID")) or "GUID"
								GameTooltip:AddLine(string.format("|cff888888%s: %s|r", guidLabel, tostring(rowGuid)), 1, 1, 1)
							end
							GameTooltip:Show()
						end
					end)
					row.frame:SetScript("OnLeave", function()
						hover:Hide()
						if GameTooltip then GameTooltip:Hide() end
					end)
					row.frame:SetScript("OnMouseUp", function(_, mouseButton)
						if not (GMS.UI and GMS.UI._page == METADATA.INTERN_NAME) then
							return
						end
						if mouseButton == "RightButton" then
							if Roster and type(Roster.ShowMemberContextMenu) == "function" then
								Roster:ShowMemberContextMenu(row.frame, {
									name = rowName,
									name_full = rowNameFull,
									name_roster = rowNameRoster,
									guid = rowGuid,
									online = m.online == true,
								})
							end
							return
						end
						if mouseButton ~= "LeftButton" then return end
						local ui = (GMS and (GMS.UI or GMS:GetModule("UI", true))) or nil
						if not ui or type(ui.Open) ~= "function" then
							return
						end
						if type(ui.SetNavigationContext) == "function" then
							ui:SetNavigationContext({
								source = "ROSTER",
								guid = rowGuid,
								name_full = rowNameFull,
							})
						end
						ui:Open("CHARINFO")
					end)
				end

				-- Map GUID to row container and store fingerprint
				if m.guid then
					Roster._guidToRow[m.guid] = row
					row._dataFingerprint = m.fingerprint
				end

				for _, colId in ipairs(Roster._columns.order) do
					local def = Roster._columns.map[colId]
					if def and type(def.buildCellFn) == "function" then
						pcall(def.buildCellFn, row, m, ctx)
					end
				end
			end

			index = index + 1
			created = created + 1
		end

		-- Layout once per chunk, not per row.
		parent:DoLayout()

		if index <= total then
			C_Timer.After(delay, Step)
		else
			if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
				C_Timer.After(0, ForceFinalLayoutPass)
				C_Timer.After(0.05, ForceFinalLayoutPass)
			else
				ForceFinalLayoutPass()
			end
		end
	end

	Step()
end

local function GetAsyncBatchSize(defaultValue)
	local opts = Roster._options
	if type(opts) ~= "table" then return defaultValue end
	local v = tonumber(opts.asyncBatchSize)
	if not v then return defaultValue end
	if v < 1 then v = 1 end
	if v > 100 then v = 100 end
	return v
end

local function GetAsyncDelay(defaultValue)
	local opts = Roster._options
	if type(opts) ~= "table" then return defaultValue end
	local v = tonumber(opts.asyncDelay)
	if not v then return defaultValue end
	if v < 0 then v = 0 end
	if v > 1 then v = 1 end
	return v
end

local function IsMemberVisibleByOnlineState(member)
	local opts = (type(Roster._options) == "table") and Roster._options or {}
	local showOnline = (opts.showOnline ~= false)
	local showOffline = (opts.showOffline ~= false)

	if member and member.online then
		return showOnline
	end
	return showOffline
end

local function NormalizeSearchQuery(raw)
	local q = tostring(raw or "")
	q = q:gsub("^%s+", ""):gsub("%s+$", "")
	return q:lower()
end

local function MemberMatchesSearch(member, queryLower)
	if queryLower == "" then return true end
	if type(member) ~= "table" then return false end

	for k, v in pairs(member) do
		local tv = type(v)
		if tv == "string" or tv == "number" or tv == "boolean" then
			local s = tostring(v):lower()
			if s:find(queryLower, 1, true) then
				return true
			end
		elseif tv == "table" then
			for kk, vv in pairs(v) do
				local tvv = type(vv)
				if tvv == "string" or tvv == "number" or tvv == "boolean" then
					local s = tostring(vv):lower()
					if s:find(queryLower, 1, true) then
						return true
					end
				end
			end
		end
	end
	return false
end

UpdateRosterStatus = function(displayedCount, totalCount)
	if not (GMS.UI and type(GMS.UI.SetStatusText) == "function") then return end

	local shown = tonumber(displayedCount) or 0
	local total = tonumber(totalCount) or 0
	if total < 0 then total = 0 end
	if shown < 0 then shown = 0 end

	local opts = Roster._options or {}
	local q = NormalizeSearchQuery(opts.searchQuery)
	local msg = ""

	if q ~= "" then
		msg = (type(GMS.T) == "function" and GMS:T("ROSTER_STATUS_SEARCH", shown, total, q))
			or string.format("|cffb8b8b8Roster:|r showing %d of %d (search: %s)", shown, total, q)
	elseif shown ~= total then
		msg = (type(GMS.T) == "function" and GMS:T("ROSTER_STATUS_FILTERED", shown, total))
			or string.format("|cffb8b8b8Roster:|r showing %d of %d", shown, total)
	else
		msg = (type(GMS.T) == "function" and GMS:T("ROSTER_STATUS_TOTAL", total))
			or string.format("|cffb8b8b8Roster:|r %d members", total)
	end

	GMS.UI:SetStatusText(msg)
end

FilterMembersByVisibility = function(members)
	if type(members) ~= "table" or #members == 0 then
		return members or {}
	end

	local opts = (type(Roster._options) == "table") and Roster._options or {}
	local showOnline = (opts.showOnline ~= false)
	local showOffline = (opts.showOffline ~= false)
	local searchQuery = NormalizeSearchQuery(opts.searchQuery)

	if showOnline and showOffline and searchQuery == "" then
		return members
	end
	if (not showOnline) and (not showOffline) then
		return {}
	end

	local out = {}
	for i = 1, #members do
		local m = members[i]
		if IsMemberVisibleByOnlineState(m) and MemberMatchesSearch(m, searchQuery) then
			out[#out + 1] = m
		end
	end
	return out
end

-- ###########################################################################
-- #	PUBLIC REFRESH API
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Forciert ein Rebuild der aktuellen Roster-List (falls UI offen)
--	@param perFrame number|nil
--	@return nil
-- ---------------------------------------------------------------------------
function Roster:API_RefreshRosterView(perFrame)
	if not self._lastListParent then return end
	local asyncBatch = GetAsyncBatchSize(10)
	local asyncWait  = GetAsyncDelay(0.05)
	BuildGuildRosterLabelsAsync(self._lastListParent, perFrame or asyncBatch, asyncWait)
end

-- ###########################################################################
-- #	INCREMENTAL LIVE UPDATES
-- ###########################################################################

function Roster:OnGuildRosterUpdate(canScan)
	self:TrackLocalAccountCharacter("guild-roster-update")

	local selfGuid = (type(UnitGUID) == "function") and UnitGUID("player") or nil
	if type(selfGuid) == "string" and selfGuid ~= "" and type(GetNumGuildMembers) == "function" and type(GetGuildRosterInfo) == "function" then
		local total = tonumber(GetNumGuildMembers() or 0) or 0
		local foundOnline = false
		for i = 1, total do
			local _, _, _, _, _, _, _, _, online, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
			if guid == selfGuid then
				foundOnline = (online == true)
				break
			end
		end
		if foundOnline and not self._selfRosterOnline then
			self._selfRosterOnline = true
			self:BroadcastMetaHeartbeat(true)
		elseif not foundOnline then
			self._selfRosterOnline = false
		end
	end

	-- Skip if UI is not on Roster page
	if not GMS.UI or GMS.UI._page ~= "ROSTER" then return end
	if not self._lastListParent then return end

	-- Debounce bursty events and limit processing frequency.
	local now = GetTime()
	if self._updateScheduled then return end
	if (now - Roster._lastUpdateEvent) < 1 then return end
	self._updateScheduled = true

	if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
		self._updateScheduled = false
		self:API_RefreshRosterView()
		return
	end

	C_Timer.After(0.30, function()
		Roster._updateScheduled = false
		Roster._lastUpdateEvent = GetTime()
		if not GMS.UI or GMS.UI._page ~= "ROSTER" then return end
		if not Roster._lastListParent then return end

		-- Get current members (skip new server request to avoid recursion loop)
		local allMembers = GetAllGuildMembers(BuildRosterSortSpec(), true)
		local totalMembers = #allMembers
		local members = FilterMembersByVisibility(allMembers)
		UpdateRosterStatus(#members, totalMembers)

		-- If count or order changed, full rebuild is safer and cheaper than patching order.
		local currentCount = #members
		local displayedCount = 0
		for _ in pairs(Roster._guidToRow) do displayedCount = displayedCount + 1 end
		local sig = BuildGuidOrderSignature(members)
		if currentCount ~= displayedCount or sig ~= (Roster._lastGuidOrderSig or "") then
			Roster._lastGuidOrderSig = sig
			Roster:API_RefreshRosterView()
			return
		end

		-- Incremental update for visible rows
		local ctx = { ui = GMS.UI }
		local changed = false
		for _, m in ipairs(members) do
			local row = Roster._guidToRow[m.guid]
			if row and row.ReleaseChildren and row._dataFingerprint ~= m.fingerprint then
				row:ReleaseChildren()
				ApplyRosterMemberAugmenters(m, ctx)
				for _, colId in ipairs(Roster._columns.order) do
					local def = Roster._columns.map[colId]
					if def and type(def.buildCellFn) == "function" then
						pcall(def.buildCellFn, row, m, ctx)
					end
				end
				row._dataFingerprint = m.fingerprint
				row:DoLayout()
				changed = true
			end
		end

		local parent = Roster._lastListParent
		local doLayout = (type(parent) == "table") and rawget(parent, "DoLayout") or nil
		if changed and parent and type(doLayout) == "function" then
			doLayout(parent)
		end
	end)
end

-- ###########################################################################
-- #	UI PAGE BUILD
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Baut die Roster-Page UI (Scroll + Content)
--	@param root AceGUIWidget
--	@return nil
-- ---------------------------------------------------------------------------
local function BuildRosterHeaderUI()
	if not (GMS.UI and type(GMS.UI.GetHeaderContent) == "function") then return end
	local header = GMS.UI:GetHeaderContent()
	if not header then return end
	if header.SetLayout then header:SetLayout("List") end
	if header.ReleaseChildren then header:ReleaseChildren() end
	EnsureDefaultRosterColumnsRegistered()
	EnsureRosterSortState()

	local opts = (type(Roster._options) == "table") and Roster._options or {}

	local guildName = ""
	if type(GetGuildInfo) == "function" then
		guildName = tostring((GetGuildInfo("player")) or "")
	end
	if guildName == "" then guildName = "Roster" end

	local realm = (type(GetNormalizedRealmName) == "function" and tostring(GetNormalizedRealmName() or ""))
		or (type(GetRealmName) == "function" and tostring(GetRealmName() or ""))
		or "-"
	local faction = (type(UnitFactionGroup) == "function" and tostring((UnitFactionGroup("player")) or "")) or "-"
	if faction == "" then faction = "-" end

	opts.showOnline = true

	local row = AceGUI:Create("SimpleGroup")
	row:SetFullWidth(true)
	row:SetLayout("Flow")
	row:SetHeight(36)
	header:AddChild(row)

	local leftCol = AceGUI:Create("SimpleGroup")
	leftCol:SetLayout("List")
	row:AddChild(leftCol)

	local title = AceGUI:Create("Label")
	title:SetText("|cff03A9F4" .. guildName .. "|r")
	title:SetHeight(20)
	if title.label then
		title.label:SetFontObject(GameFontNormalLarge)
		title.label:SetJustifyV("MIDDLE")
	end
	leftCol:AddChild(title)

	local meta = AceGUI:Create("Label")
	meta:SetFullWidth(true)
	meta:SetHeight(14)
	meta:SetText(tostring(realm) .. " - " .. tostring(faction))
	if meta.label then
		meta.label:SetFontObject(GameFontNormalSmall or GameFontNormalSmallOutline)
		meta.label:SetJustifyV("TOP")
	end
	leftCol:AddChild(meta)

	local searchCol = AceGUI:Create("SimpleGroup")
	searchCol:SetLayout("Flow")
	row:AddChild(searchCol)

	local searchLabel = AceGUI:Create("Label")
	searchLabel:SetText((type(GMS.T) == "function" and GMS:T("ROSTER_SEARCH")) or "Search:")
	searchLabel:SetWidth(45)
	searchCol:AddChild(searchLabel)

	local searchBox = AceGUI:Create("EditBox")
	searchBox:SetLabel("")
	searchBox:SetWidth(280)
	searchBox:DisableButton(true)
	searchBox:SetText(tostring(opts.searchQuery or ""))
	searchCol:AddChild(searchBox)

	local filterCol = AceGUI:Create("SimpleGroup")
	filterCol:SetLayout("Flow")
	row:AddChild(filterCol)

	local cbOffline = AceGUI:Create("CheckBox")
	cbOffline:SetLabel((type(GMS.T) == "function" and GMS:T("ROSTER_SHOW_OFFLINE")) or "Show offline members")
	cbOffline:SetWidth(210)
	cbOffline:SetValue(opts.showOffline ~= false)
	cbOffline:SetCallback("OnValueChanged", function(_, _, v)
		opts.showOffline = v and true or false
		if Roster and type(Roster.API_RefreshRosterView) == "function" then
			Roster:API_RefreshRosterView()
		end
	end)
	filterCol:AddChild(cbOffline)

	local searchToken = 0
	local function ApplySearch(text)
		opts.searchQuery = tostring(text or "")
		if Roster and type(Roster.API_RefreshRosterView) == "function" then
			Roster:API_RefreshRosterView()
		end
	end
	local function ScheduleSearchApply(text)
		searchToken = searchToken + 1
		local token = searchToken
		if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
			C_Timer.After(0.15, function()
				if token ~= searchToken then return end
				ApplySearch(text)
			end)
		else
			ApplySearch(text)
		end
	end

	searchBox:SetCallback("OnTextChanged", function(_, _, val)
		ScheduleSearchApply(val)
	end)
	searchBox:SetCallback("OnEnterPressed", function(_, _, val)
		ApplySearch(val)
	end)

	local function UpdateHeaderWidths()
		local totalW = (row.frame and row.frame.GetWidth and row.frame:GetWidth()) or 760
		local rightW = 220
		local leftW = 250
		local middleW = totalW - leftW - rightW - 20
		if middleW < 220 then
			middleW = 220
			leftW = totalW - middleW - rightW - 20
			if leftW < 180 then leftW = 180 end
		end
		leftCol:SetWidth(leftW)
		searchCol:SetWidth(middleW)
		filterCol:SetWidth(rightW)

		local searchW = middleW - 45 - 8
		if searchW < 120 then searchW = 120 end
		searchBox:SetWidth(searchW)

		-- AceGUI flow places the search widgets slightly low in this row; nudge up for visual alignment.
		if searchCol.frame and searchCol.frame.GetPoint and searchCol.frame.SetPoint then
			local p, rel, rp, x, y = searchCol.frame:GetPoint(1)
			if p then
				searchCol.frame:ClearAllPoints()
				searchCol.frame:SetPoint(p, rel, rp, x, (y or 0) + 3)
			end
		end
	end

	UpdateHeaderWidths()
	if row.frame and type(row.frame.HookScript) == "function" then
		row.frame:HookScript("OnSizeChanged", function()
			UpdateHeaderWidths()
		end)
	end
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		local function RefreshHeaderLayout()
			UpdateHeaderWidths()
			if header and type(header.DoLayout) == "function" then
				header:DoLayout()
			end
			if row and type(row.DoLayout) == "function" then
				row:DoLayout()
			end
		end
		C_Timer.After(0, RefreshHeaderLayout)
		C_Timer.After(0.05, RefreshHeaderLayout)
		C_Timer.After(0.15, RefreshHeaderLayout)
	end

end

local function BuildRosterPageUI(root, id, isCached)
	BuildRosterHeaderUI()

	if isCached then return end

	local wrapper = AceGUI:Create("SimpleGroup")
	wrapper:SetFullWidth(true)
	wrapper:SetFullHeight(true)
	wrapper:SetLayout("Fill")
	root:AddChild(wrapper)

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	wrapper:AddChild(scroll)

	local content = AceGUI:Create("SimpleGroup")
	content:SetFullWidth(true)
	content:SetFullHeight(true)
	content:SetLayout("List")
	scroll:AddChild(content)

	Roster._lastListParent = content

	local asyncBatch = GetAsyncBatchSize(5)
	local asyncWait  = GetAsyncDelay(0.05)
	BuildGuildRosterLabelsAsync(content, asyncBatch, asyncWait)

	C_Timer.After(0.2, function()
		scroll:DoLayout()
		wrapper:DoLayout()
	end)
end

-- ###########################################################################
-- #	UI INTEGRATION (PAGE + DOCK)
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Registriert Page + Dock Icon (wenn UI verfuegbar ist)
--	@return boolean
-- ---------------------------------------------------------------------------
function Roster:TryRegisterRosterPageInUI()
	if self._pageRegistered then
		return true
	end

	if not GMS.UI or type(GMS.UI.RegisterPage) ~= "function" then
		return false
	end

	GMS.UI:RegisterPage(METADATA.INTERN_NAME, 50, METADATA.DISPLAY_NAME, function(root, id, isCached)
		BuildRosterPageUI(root, id, isCached)
	end)

	self._pageRegistered = true
	LOCAL_LOG("INFO", "UI page registered", { page = "Roster" })

	return true
end

-- ---------------------------------------------------------------------------
--	Registriert RightDock Icon fuer die Roster-Page
--	@return boolean
-- ---------------------------------------------------------------------------
function Roster:TryRegisterRosterDockIconInUI()
	if self._dockRegistered then
		return true
	end

	if not GMS.UI or type(GMS.UI.AddRightDockIconTop) ~= "function" then
		return false
	end

	GMS.UI:AddRightDockIconTop({
		id = METADATA.INTERN_NAME,
		order = 50,
		selectable = true,
		icon = "Interface\\Icons\\Achievement_guildperk_everybodysfriend",
		tooltipTitle = METADATA.DISPLAY_NAME,
		tooltipText = (type(GMS.T) == "function" and GMS:T("ROSTER_DOCK_TOOLTIP")) or "Open roster page",
		onClick = function()
			GMS.UI:Open(METADATA.INTERN_NAME)
		end,
	})

	self._dockRegistered = true
	LOCAL_LOG("INFO", "RightDock icon registered", { id = "Roster" })

	return true
end

-- ---------------------------------------------------------------------------
--	Versucht Integration (Page + Dock), falls UI bereit ist
--	@return nil
-- ---------------------------------------------------------------------------
function Roster:TryIntegrateWithUIIfAvailable()
	local okPage = self:TryRegisterRosterPageInUI()
	local okDock = self:TryRegisterRosterDockIconInUI()

	if okPage and okDock then
		return
	end
end

-- ###########################################################################
-- #	ACE LIFECYCLE
-- ###########################################################################

-- Roster options (migrated to RegisterModuleOptions API)
Roster._options = Roster._options or nil

local OPTIONS_DEFAULTS = {
	showOnline = true,
	showOffline = true,
	searchQuery = "",
	autoRefresh = true,
	lastRefresh = 0,
	asyncBatchSize = 8,
	asyncDelay = 0.02,
}

function Roster:InitializeOptions()
	-- Register guild-scoped options using new API
	if GMS and type(GMS.RegisterModuleOptions) == "function" then
		pcall(function()
			GMS:RegisterModuleOptions("ROSTER", OPTIONS_DEFAULTS, "GUILD")
		end)
	end

	-- Retrieve options table
	if GMS and type(GMS.GetModuleOptions) == "function" then
		local ok, opts = pcall(GMS.GetModuleOptions, GMS, "ROSTER")
		if ok and type(opts) == "table" then
			local moduleOptions = opts
			if moduleOptions.showOnline == nil then moduleOptions.showOnline = true end
			if moduleOptions.showOffline == nil then moduleOptions.showOffline = true end
			if moduleOptions.searchQuery == nil then moduleOptions.searchQuery = "" end

			local batchValue = moduleOptions.asyncBatchSize
			if type(batchValue) == "table" then
				local raw = batchValue["default"]
				moduleOptions.asyncBatchSize = tonumber(raw) or 8
			end

			local delayValue = moduleOptions.asyncDelay
			if type(delayValue) == "table" then
				local raw = delayValue["default"]
				moduleOptions.asyncDelay = tonumber(raw) or 0.02
			end

			self._options = moduleOptions
			self._optionsRetryScheduled = false
			LOCAL_LOG("INFO", "Roster options initialized (GUILD scope)")
		else
			-- If not in guild or gdb not ready, retry in 5s
			if IsInGuild and IsInGuild() and not self._optionsRetryScheduled then
				self._optionsRetryScheduled = true
				C_Timer.After(5, function() Roster:InitializeOptions() end)
			end
			LOCAL_LOG("WARN", "Failed to retrieve Roster options (deferred)")
		end
	end
end

-- ---------------------------------------------------------------------------
--	Ace Lifecycle: OnEnable
--	@return nil
-- ---------------------------------------------------------------------------
function Roster:OnEnable()
	self:InitializeOptions()
	self:TryIntegrateWithUIIfAvailable()
	self:InitCommMetaSync()
	self:TrackLocalAccountCharacter("enable")

	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(2.0, function()
			Roster:TrackLocalAccountCharacter("enable-delay")
		end)
	end

	-- Register for live updates
	self:RegisterEvent("GUILD_ROSTER_UPDATE", "OnGuildRosterUpdate")
	self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
	self:RegisterEvent("PLAYER_GUILD_UPDATE", "OnPlayerGuildUpdate")

	-- Listen for config changes to sync _options and update view
	self:RegisterMessage("GMS_CONFIG_CHANGED", function(_, targetKey, key, value)
		if targetKey == "ROSTER" then
			self:InitializeOptions() -- Refresh local ref
			---@diagnostic disable-next-line: undefined-field
			local frame = self._lastListParent and self._lastListParent.frame or nil
			if frame and frame.IsShown and frame:IsShown() then
				self:API_RefreshRosterView()
			end
		end
	end)

	if self._integrateWaitFrame then
		return
	end

	if self._pageRegistered and self._dockRegistered then
		GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
		self:BroadcastMetaHeartbeat(true)
		return
	end

	self._integrateWaitFrame = CreateFrame("Frame")
	self._integrateWaitFrame:RegisterEvent("ADDON_LOADED")

	self._integrateWaitFrame:SetScript("OnEvent", function(frame, _, addonName)
		if addonName ~= "GMS" then return end

		Roster:TryIntegrateWithUIIfAvailable()
		Roster:InitCommMetaSync()

		if Roster._pageRegistered and Roster._dockRegistered then
			frame:UnregisterEvent("ADDON_LOADED")
			frame:SetScript("OnEvent", nil)
			Roster._integrateWaitFrame = nil
			GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
			Roster:BroadcastMetaHeartbeat(true)
		end
	end)
end

function Roster:OnDisable()
	self._updateScheduled = false
	self._lastListParent = nil
	self._lastGuidOrderSig = ""
	wipe(self._guidToRow)
	local ticker = self._commTicker
	if ticker and type(ticker["Cancel"]) == "function" then
		pcall(ticker["Cancel"], ticker)
	end
	self._commTicker = nil
	self._commInited = false
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end

function Roster:OnPlayerLogin()
	self:TrackLocalAccountCharacter("player-login")
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(2.0, function()
			Roster:TrackLocalAccountCharacter("player-login-delay")
			Roster:BroadcastMetaHeartbeat(true)
		end)
	else
		self:BroadcastMetaHeartbeat(true)
	end
end

function Roster:OnPlayerEnteringWorld()
	self:TrackLocalAccountCharacter("entering-world")
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(1.0, function()
			Roster:TrackLocalAccountCharacter("entering-world-delay")
			Roster:BroadcastMetaHeartbeat(false)
		end)
	else
		self:BroadcastMetaHeartbeat(false)
	end
end

function Roster:OnPlayerGuildUpdate()
	self:TrackLocalAccountCharacter("guild-update")
	self:BroadcastMetaHeartbeat(true)
end

-- ---------------------------------------------------------------------------
--	Liefert Member-Daten per GUID (fuer andere Module/Berechtigungen)
--	Nutzt GetGuildRosterInfo direkt (Throttled by Blizzard), falls kein Cache
--	@param guid string
--	@return table|nil { guid, name, rankIndex, classFileName, online, ... }
-- ---------------------------------------------------------------------------
function Roster:GetMemberByGUID(guid)
	if not guid or type(guid) ~= "string" or not guid:find("^Player%-") then
		return nil
	end

	if not IsInGuild() then return nil end

	local num = GetNumGuildMembers()
	for i = 1, num do
		local name, rank, rankIndex, level, class, zone, note, officernote,
		online, status, classFileName, achievementPoints,
		achievementRank, isMobile, canSoR, repStanding, GUID = GetGuildRosterInfo(i)

		if GUID == guid then
			return {
				guid = GUID,
				name = name,
				rankIndex = rankIndex,
				rankName = rank,
				level = level,
				classFileName = classFileName,
				online = online,
			}
		end
	end
	return nil
end


