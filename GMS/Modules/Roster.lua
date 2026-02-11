-- ============================================================================
--	GMS/Modules/Roster.lua
--	ROSTER-Module (Ace-only)
--	- KEIN _G, KEIN addonTable
--	- Zugriff auf GMS ausschließlich über AceAddon Registry
--	- UI: Registriert Page + RightDock Icon
--	- Roster-View:
--		- Modular: Spalten per Column-Registry (jede Spalte eigene Build-Fn)
--		- Header: klickbar, ändert Sortierung (ASC/DESC Toggle)
--		- Erweiterbar: externe Spalten über Augmenter (GUID -> Zusatzdaten)
--		- Async Build: X Einträge pro Frame (Token-Guard gegen alte Builds)
-- ============================================================================

local METADATA = {
	TYPE         = "MOD",
	INTERN_NAME  = "ROSTER",
	SHORT_NAME   = "Roster",
	DISPLAY_NAME = "Roster",
	VERSION      = "1.0.4",
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
local C_Timer                    = C_Timer
local GetGuildRosterInfo         = GetGuildRosterInfo
local GetNumGuildMembers         = GetNumGuildMembers
local GetFullRoster              = GetFullRoster -- Fallback or custom
local IsInGuild                  = IsInGuild
local C_GuildInfo                = C_GuildInfo
local GuildRoster                = GuildRoster
local GetNormalizedRealmName     = GetNormalizedRealmName
local CLASS_ICON_TCOORDS         = CLASS_ICON_TCOORDS
local RAID_CLASS_COLORS          = RAID_CLASS_COLORS
local GameFontNormalSmallOutline = GameFontNormalSmallOutline
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

-- ###########################################################################
-- #	NAME NORMALIZATION
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Stellt sicher, dass ein Charname IMMER den Realm enthält
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
	Roster._nameCache[rawName] = { name_full, name, realm }

	return name_full, name, realm
end

-- ###########################################################################
-- #	GUILD DATA + MULTI SORT
-- ###########################################################################

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
			m.name_full = name_full
			m.name = name_short
			m.realm = realm
			m.rank = rank
			m.rankIndex = rankIndex or 0
			m.level = level or 0
			m.class = class
			m.classFileName = classFileName
			m.zone = zone or ""
			m.online = online and true or false
			m.guid = GUID
			m.note = note or ""

			-- Generate a Data Fingerprint for incremental updates
			m.fingerprint = string.format("%s:%d:%s:%s:%s",
				GUID or "no-guid", level or 0, rankIndex or 0,
				m.online and "1" or "0", note or "")

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
					if type(va) == "boolean" then
						va, vb = (va and 1 or 0), (vb and 1 or 0)
					elseif type(va) == "string" then
						va, vb = va:lower(), vb:lower()
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
--	Gibt Icon Pfad für classFileName zurück (fallback QuestionMark)
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
--	Erstellt ein AceGUI Icon für eine Klasse
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
--	Gibt die Klassenfarbe für ein classFileName zurück
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
--	Registriert eine neue Spalte für den Roster (erweiterbar)
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
	LEVEL:SetWidth(25)
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

	local guid = member.guid
	local name_full = member.name_full

	local MEMBER_NAME = AceGUI:Create("InteractiveLabel")
	MEMBER_NAME:SetText("|c" .. hex .. tostring(member.name or "") .. "|r")
	MEMBER_NAME.label:SetFontObject(GameFontNormalSmallOutline)
	MEMBER_NAME:SetWidth(150)

	local bg = MEMBER_NAME.frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(MEMBER_NAME.frame)
	bg:SetColorTexture(1, 1, 1, 0.10)
	bg:Hide()

	MEMBER_NAME:SetCallback("OnEnter", function(widget)
		bg:Show()
		if widget and widget.label then
			widget.label:SetAlpha(0.95)
		end
	end)

	MEMBER_NAME:SetCallback("OnLeave", function(widget)
		bg:Hide()
		if widget and widget.label then
			widget.label:SetAlpha(1.0)
		end
	end)

	MEMBER_NAME:SetCallback("OnClick", function(_, _, mouseButton)
		if mouseButton ~= "LeftButton" then return end

		local ui = (GMS and (GMS.UI or GMS:GetModule("UI", true))) or nil
		if not ui or type(ui.Open) ~= "function" then
			return
		end

		if type(ui.SetNavigationContext) == "function" then
			ui:SetNavigationContext({
				source = "ROSTER",
				guid = guid,
				name_full = name_full,
			})
		end

		ui:Open("CHARINFO")
	end)

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
	REALM:SetWidth(120)
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
		width = 25,
		order = 20,
		sortable = true,
		sortKey = "level",
		buildCellFn = BuildCell_Level,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "name",
		title = "Name",
		width = 150,
		order = 30,
		sortable = true,
		sortKey = "name",
		buildCellFn = BuildCell_Name,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "realm",
		title = "Realm",
		width = 120,
		order = 40,
		sortable = true,
		sortKey = "realm",
		buildCellFn = BuildCell_Realm,
	})

	Roster:API_RegisterRosterColumnDefinition({
		id = "zone",
		title = "Zone",
		width = 220,
		order = 50,
		sortable = true,
		sortKey = "zone",
		buildCellFn = BuildCell_Zone,
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

	local header = AceGUI:Create("SimpleGroup")
	header:SetFullWidth(true)
	header:SetLayout("Flow")
	parent:AddChild(header)

	for _, colId in ipairs(Roster._columns.order) do
		local def = Roster._columns.map[colId]
		if def then
			local title = tostring(def.title or colId)
			local w = tonumber(def.width) or 80

			if def.sortable == true and type(def.sortKey) == "string" and def.sortKey ~= "" then
				local lbl = AceGUI:Create("InteractiveLabel")

				local arrow = ""
				if Roster._sortState.key == def.sortKey then
					arrow = (Roster._sortState.desc == true) and " |cffffd100▼|r" or " |cffffd100▲|r"
				end

				lbl:SetText("|cffc8c8c8" .. title .. "|r" .. arrow)
				lbl.label:SetFontObject(GameFontNormalSmallOutline)
				lbl:SetWidth(w)

				local bg = lbl.frame:CreateTexture(nil, "BACKGROUND")
				bg:SetAllPoints(lbl.frame)
				bg:SetColorTexture(1, 1, 1, 0.08)
				bg:Hide()

				lbl:SetCallback("OnEnter", function() bg:Show() end)
				lbl:SetCallback("OnLeave", function() bg:Hide() end)
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
				lbl:SetWidth(w)
				header:AddChild(lbl)
			end
		end
	end
end

-- ###########################################################################
-- #	ASYNC LIST BUILD
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Baut Guild-Roster-Labels asynchron (X Einträge pro Frame)
--	- Nutzt Column-Registry + Header + SortState
--	- Ruft externe Augmenter für Zusatzspalten auf (GUID -> member.someField)
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

	local members = GetAllGuildMembers(BuildRosterSortSpec())
	if not members or #members == 0 then
		local empty = AceGUI:Create("Label")
		empty:SetText("Keine Gildenmitglieder gefunden.")
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
				parent:AddChild(row)

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

		parent:DoLayout()

		if index <= total then
			C_Timer.After(delay, Step)
		end
	end

	Step()
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
	local asyncBatch = (Roster._options and Roster._options.asyncBatchSize) or 10
	local asyncWait  = (Roster._options and Roster._options.asyncDelay) or 0.05
	BuildGuildRosterLabelsAsync(self._lastListParent, perFrame or asyncBatch, asyncWait)
end

-- ###########################################################################
-- #	INCREMENTAL LIVE UPDATES
-- ###########################################################################

function Roster:OnGuildRosterUpdate(canScan)
	-- Skip if UI is not on Roster page
	if not GMS.UI or GMS.UI._page ~= "ROSTER" then return end
	if not self._lastListParent then return end

	-- THROTTLE: Max once every 5 seconds for UI updates
	local now = GetTime()
	if (now - Roster._lastUpdateEvent) < 5 then return end
	Roster._lastUpdateEvent = now

	-- Get current members (Skip new server request to avoid recursion loop)
	local members = GetAllGuildMembers(BuildRosterSortSpec(), true)

	-- If member count changed, full rebuild is safer
	local currentCount = #members
	local displayedCount = 0
	for _ in pairs(self._guidToRow) do displayedCount = displayedCount + 1 end

	if currentCount ~= displayedCount then
		self:API_RefreshRosterView()
		return
	end

	-- Incremental update for visible rows
	local ctx = {
		ui = GMS.UI,
	}

	local changed = false
	for _, m in ipairs(members) do
		local row = self._guidToRow[m.guid]

		-- Only rebuild row if data fingerprint changed
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

	if changed and self._lastListParent.DoLayout then
		self._lastListParent:DoLayout()
	end
end

-- ###########################################################################
-- #	UI PAGE BUILD
-- ###########################################################################

-- ---------------------------------------------------------------------------
--	Baut die Roster-Page UI (Scroll + Content)
--	@param root AceGUIWidget
--	@return nil
-- ---------------------------------------------------------------------------
local function BuildRosterPageUI(root, id, isCached)
	if GMS.UI and type(GMS.UI.Header_BuildDefault) == "function" then
		GMS.UI:Header_BuildDefault()
	end

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

	local asyncBatch = (Roster._options and Roster._options.asyncBatchSize) or 5
	local asyncWait  = (Roster._options and Roster._options.asyncDelay) or 0.05
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
--	Registriert Page + Dock Icon (wenn UI verfügbar ist)
--	@return boolean
-- ---------------------------------------------------------------------------
function Roster:TryRegisterRosterPageInUI()
	if self._pageRegistered then
		return true
	end

	if not GMS.UI or type(GMS.UI.RegisterPage) ~= "function" then
		return false
	end

	GMS.UI:RegisterPage(METADATA.INTERN_NAME, 50, METADATA.DISPLAY_NAME, function(root)
		BuildRosterPageUI(root)
	end)

	self._pageRegistered = true
	LOCAL_LOG("INFO", "UI page registered", { page = "Roster" })

	return true
end

-- ---------------------------------------------------------------------------
--	Registriert RightDock Icon für die Roster-Page
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
		tooltipText = "Öffnet die Roster-Page",
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
	showOffline = true,
	autoRefresh = true,
	lastRefresh = 0,
	asyncBatchSize = { name = "Einträge pro Schritt (Batch)", type = "range", min = 1, max = 50, step = 1, default = 5 },
	asyncDelay = { name = "Verzögerung (Schrittpause, Sek)", type = "range", min = 0, max = 1, step = 0.01, default = 0.05 },
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
		if ok and opts then
			self._options = opts
			LOCAL_LOG("INFO", "Roster options initialized (GUILD scope)")
		else
			-- If not in guild or gdb not ready, retry in 5s
			if IsInGuild and IsInGuild() then
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

	-- Register for live updates
	self:RegisterEvent("GUILD_ROSTER_UPDATE", "OnGuildRosterUpdate")

	-- Listen for config changes to sync _options and update view
	self:RegisterMessage("GMS_CONFIG_CHANGED", function(_, targetKey, key, value)
		if targetKey == "ROSTER" then
			self:InitializeOptions() -- Refresh local ref
			if self._lastListParent and self._lastListParent.frame:IsShown() then
				self:API_RefreshRosterView()
			end
		end
	end)

	if self._integrateWaitFrame then
		return
	end

	if self._pageRegistered and self._dockRegistered then
		GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
		return
	end

	self._integrateWaitFrame = CreateFrame("Frame")
	self._integrateWaitFrame:RegisterEvent("ADDON_LOADED")

	self._integrateWaitFrame:SetScript("OnEvent", function(frame, _, addonName)
		if addonName ~= "GMS" then return end

		Roster:TryIntegrateWithUIIfAvailable()

		if Roster._pageRegistered and Roster._dockRegistered then
			frame:UnregisterEvent("ADDON_LOADED")
			frame:SetScript("OnEvent", nil)
			Roster._integrateWaitFrame = nil
			GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
		end
	end)
end

function Roster:OnDisable()
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end
