-- ============================================================================
--	GMS/Modules/CharInfo.lua
--	CharInfo MODULE (Ace)
--	- Zugriff auf GMS Ã¼ber AceAddon Registry
--	- UI-Page + RightDock Icon
--	- Zeigt Player-Snapshot + ctx (optional) + Auswahl-Buttons
-- ============================================================================

local _G = _G

-- ###########################################################################
-- #	METADATA (required)
-- ###########################################################################

local METADATA = {
	TYPE         = "MOD",
	INTERN_NAME  = "CHARINFO",
	SHORT_NAME   = "CharInfo",
	DISPLAY_NAME = "Charakterinformationen",
	VERSION      = "1.0.10",
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
local GetLocale                  = GetLocale
local UnitFullName               = UnitFullName
local UnitClass                  = UnitClass
local UnitRace                   = UnitRace
local UnitLevel                  = UnitLevel
local GetGuildInfo               = GetGuildInfo
local UnitFactionGroup           = UnitFactionGroup
local GetSpecialization          = GetSpecialization
local GetSpecializationInfo      = GetSpecializationInfo
local GetAverageItemLevel        = GetAverageItemLevel
local UnitGUID                   = UnitGUID
local UnitExists                 = UnitExists
local UnitIsPlayer               = UnitIsPlayer
local C_Timer                    = C_Timer
local C_ClassTalents             = C_ClassTalents
local C_Traits                   = C_Traits
local C_PvP                      = C_PvP
local GetPVPLifetimeStats        = GetPVPLifetimeStats
local GameTooltip                = GameTooltip
local HandleModifiedItemClick    = HandleModifiedItemClick
local GameFontNormalSmallOutline = GameFontNormalSmallOutline
local RAID_CLASS_COLORS          = RAID_CLASS_COLORS
local LoadAddOn                  = LoadAddOn
local EasyMenu                   = EasyMenu
local CreateFrame                = CreateFrame
local UIParent                   = UIParent
local UIDropDownMenu_Initialize  = UIDropDownMenu_Initialize
local UIDropDownMenu_AddButton   = UIDropDownMenu_AddButton
local ToggleDropDownMenu         = ToggleDropDownMenu
local ChatEdit_ChooseBoxForSend  = ChatEdit_ChooseBoxForSend
local ChatEdit_ActivateChat      = ChatEdit_ActivateChat
local C_PartyInfo                = C_PartyInfo
local InviteUnit                 = InviteUnit
---@diagnostic enable: undefined-global

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

-- ###########################################################################
-- #	LOG BUFFER + LOCAL_LOG (required)
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		timestamp = time and time() or 0,
		level     = tostring(level or "INFO"),
		type      = METADATA.TYPE,
		source    = METADATA.SHORT_NAME,
		message   = tostring(msg or ""),
		args      = { ... },
	}

	local buffer = GMS._LOG_BUFFER
	local idx = #buffer + 1
	buffer[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		GMS._LOG_NOTIFY(entry, idx)
	end
end

-- ###########################################################################
-- #	MODULE
-- ###########################################################################

local MODULE_NAME = METADATA.INTERN_NAME
local DISPLAY_NAME = METADATA.DISPLAY_NAME

local CHARINFO = GMS:GetModule(MODULE_NAME, true)
if not CHARINFO then
	CHARINFO = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
end

-- Registration
if GMS and type(GMS.RegisterModule) == "function" then
	GMS:RegisterModule(CHARINFO, METADATA)
end

GMS[MODULE_NAME] = CHARINFO

CHARINFO._pageRegistered = CHARINFO._pageRegistered or false
CHARINFO._dockRegistered = CHARINFO._dockRegistered or false
CHARINFO._integrated     = CHARINFO._integrated or false
CHARINFO._ticker         = CHARINFO._ticker or nil
CHARINFO._uiDataTicker   = CHARINFO._uiDataTicker or nil
CHARINFO._uiDataLastSig  = CHARINFO._uiDataLastSig or nil
CHARINFO._resizeRefreshPending = CHARINFO._resizeRefreshPending or false

---@class GMSTickerHandle
---@field Cancel fun(self: GMSTickerHandle)

-- DB for character-specific options (migrated to new API)
CHARINFO._options = CHARINFO._options or nil

local OPTIONS_DEFAULTS = {
	autoLog = true, -- Auto-log character on login
	lastUpdate = 0,
	cardOrder = { "MYTHIC", "EQUIPMENT", "RAIDS", "OVERVIEW", "ACCOUNT", "TALENTS", "PVP" },
}

-- Icon: nimm einen, der bei dir existiert (du kannst ihn per /run testen)
local ICON = "Interface\\Icons\\INV_Misc_Head_Human_01"

-- ###########################################################################
-- #	HELPERS (style aligned)
-- ###########################################################################

local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, err = pcall(fn, ...)
	if not ok then
		LOCAL_LOG("ERROR", "CharInfo error: %s", tostring(err))
		if type(GMS.Print) == "function" then
			GMS:Print("CharInfo Fehler: " .. tostring(err))
		end
	end
	return ok
end

local function UIRef()
	return (GMS and (GMS.UI or GMS:GetModule("UI", true))) or nil
end

local function GetNavContext(consume)
	local ui = UIRef()
	if ui and type(ui.GetNavigationContext) == "function" then
		return ui:GetNavigationContext(consume == true)
	end
	return nil
end

local function SetNavContext(ctx)
	local ui = UIRef()
	if ui and type(ui.SetNavigationContext) == "function" then
		ui:SetNavigationContext(ctx)
		return true
	end
	return false
end

local function OpenSelf()
	local ui = UIRef()
	if not ui then return false end

	-- Avoid forcing ApplyWindowState() while already open:
	-- use Navigate for in-place refresh to preserve current resize state.
	local isShown = ui._frame and type(ui._frame.IsShown) == "function" and ui._frame:IsShown()
	if isShown and ui._page == "CHARINFO" and type(ui.Navigate) == "function" then
		ui:Navigate("CHARINFO")
		return true
	end

	if type(ui.Open) == "function" then
		ui:Open("CHARINFO")
		return true
	end
	return false
end

local function FormatNameRealm(name, realm)
	name = tostring(name or "")
	realm = tostring(realm or "")
	if name == "" then return "-" end
	if realm ~= "" then
		return name .. "-" .. realm
	end
	return name
end

local function LocalizeFactionName(faction)
	local f = tostring(faction or "-")
	if f == "" then return "-" end

	if type(GetLocale) == "function" and GetLocale() == "deDE" then
		if f == "Alliance" then return "Allianz" end
		if f == "Horde" then return "Horde" end
	end

	return f
end

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

	local parsedShort = full:match("^([^%-]+)")
	if parsedShort and parsedShort ~= short and TryInvite(parsedShort) then
		return true
	end

	return false
end

CHARINFO._headerContextMenuFrame = CHARINFO._headerContextMenuFrame or nil

local function EnsureDropdownAPI()
	if type(EasyMenu) == "function" then return true end
	if type(LoadAddOn) == "function" then
		pcall(LoadAddOn, "Blizzard_UIDropDownMenu")
	end
	EasyMenu = (type(_G) == "table" and rawget(_G, "EasyMenu")) or EasyMenu
	UIDropDownMenu_Initialize = (type(_G) == "table" and rawget(_G, "UIDropDownMenu_Initialize")) or UIDropDownMenu_Initialize
	UIDropDownMenu_AddButton = (type(_G) == "table" and rawget(_G, "UIDropDownMenu_AddButton")) or UIDropDownMenu_AddButton
	ToggleDropDownMenu = (type(_G) == "table" and rawget(_G, "ToggleDropDownMenu")) or ToggleDropDownMenu
	return type(EasyMenu) == "function"
		or (type(UIDropDownMenu_Initialize) == "function"
			and type(UIDropDownMenu_AddButton) == "function"
			and type(ToggleDropDownMenu) == "function")
end

local function LocalMenuText(en, de)
	if type(GetLocale) == "function" and GetLocale() == "deDE" and tostring(de or "") ~= "" then
		return tostring(de)
	end
	return tostring(en or "")
end

local function ShowHeaderActionsMenu(details)
	if not EnsureDropdownAPI() then return end
	if type(CreateFrame) ~= "function" then return end

	if not CHARINFO._headerContextMenuFrame then
		CHARINFO._headerContextMenuFrame = CreateFrame("Frame", "GMSCharInfoHeaderContextMenu", UIParent, "UIDropDownMenuTemplate")
	end
	if not CHARINFO._headerContextMenuFrame then return end

	local fullName = tostring(details and details.general and details.general.name or "")
	local shortName = fullName:match("^([^%-]+)") or fullName
	local guid = tostring(details and details.general and details.general.guid or "")
	local isSelf = (type(UnitGUID) == "function" and guid ~= "" and guid == tostring(UnitGUID("player") or ""))

	local menu = {
		{ text = fullName ~= "" and fullName or "-", isTitle = true, notCheckable = true },
		{
			text = LocalMenuText("Whisper", "Anfluestern"),
			notCheckable = true,
			disabled = (fullName == ""),
			func = function()
				if fullName ~= "" then
					OpenChatEditWithText("/w " .. fullName .. " ")
				end
			end,
		},
		{
			text = LocalMenuText("Copy name", "Name kopieren"),
			notCheckable = true,
			disabled = (fullName == ""),
			func = function()
				if fullName ~= "" then
					OpenChatEditWithText(fullName)
				end
			end,
		},
		{
			text = LocalMenuText("Invite to group", "In Gruppe einladen"),
			notCheckable = true,
			disabled = (fullName == "" or isSelf),
			func = function()
				if fullName == "" or isSelf then return end
				if TryInviteUnitByName(fullName, shortName) then return end
				OpenChatEditWithText("/invite " .. fullName)
			end,
		},
		{
			text = LocalMenuText("Target", "Anvisieren"),
			notCheckable = true,
			disabled = (shortName == ""),
			func = function()
				if shortName ~= "" then
					-- Avoid protected-call taint from dropdown callbacks.
					OpenChatEditWithText("/target " .. shortName)
				end
			end,
		},
	}

	if type(EasyMenu) == "function" then
		EasyMenu(menu, CHARINFO._headerContextMenuFrame, "cursor", 0, 0, "MENU")
		return
	end
	if type(UIDropDownMenu_Initialize) == "function"
		and type(UIDropDownMenu_AddButton) == "function"
		and type(ToggleDropDownMenu) == "function" then
		UIDropDownMenu_Initialize(CHARINFO._headerContextMenuFrame, function(_, level)
			if level ~= 1 then return end
			for i = 1, #menu do
				UIDropDownMenu_AddButton(menu[i], level)
			end
		end, "MENU")
		ToggleDropDownMenu(1, nil, CHARINFO._headerContextMenuFrame, "cursor", 0, 0)
	end
end

local function GetPlayerSnapshot()
	local name, realm = UnitFullName("player")
	local className, classFile = UnitClass("player") -- localized + token
	local raceName = UnitRace("player") -- localized
	local level = UnitLevel("player")

	local guildName = GetGuildInfo and GetGuildInfo("player") or nil

	local specName = "-"
	if type(GetSpecialization) == "function" and type(GetSpecializationInfo) == "function" then
		local specIndex = GetSpecialization()
		if specIndex then
			local _, sName = GetSpecializationInfo(specIndex)
			if sName and sName ~= "" then specName = sName end
		end
	end

	local ilvlEquipped = nil
	local ilvlOverall = nil
	if type(GetAverageItemLevel) == "function" then
		local overall, equipped = GetAverageItemLevel()
		ilvlOverall = overall
		ilvlEquipped = equipped
	end

	return {
		name         = name,
		realm        = realm,
		name_full    = FormatNameRealm(name, realm),
		class        = className or "-",
		classFile    = classFile or "",
		spec         = specName,
		race         = raceName or "-",
		level        = level or "-",
		guild        = guildName or "-",
		ilvl         = (ilvlEquipped and string.format("%.1f", ilvlEquipped)) or "-",
		ilvl_overall = (ilvlOverall and string.format("%.1f", ilvlOverall)) or "-",
		guid         = (UnitGUID and UnitGUID("player")) or nil,
	}
end

local function GetTargetSnapshot()
	if not (UnitExists and UnitExists("target")) then return nil end
	if not (UnitIsPlayer and UnitIsPlayer("target")) then return nil end

	local name, realm = UnitFullName("target")
	local className, classFile = UnitClass("target")
	local raceName = UnitRace("target")
	local level = UnitLevel("target")
	local guid = (UnitGUID and UnitGUID("target")) or nil

	-- Spec / ilvl fÃ¼r target sind ohne Inspect nicht zuverlÃ¤ssig -> bewusst "-"
	return {
		name         = name,
		realm        = realm,
		name_full    = FormatNameRealm(name, realm),
		class        = className or "-",
		classFile    = classFile or "",
		spec         = "-",
		race         = raceName or "-",
		level        = level or "-",
		guild        = "-",
		ilvl         = "-",
		ilvl_overall = "-",
		guid         = guid,
	}
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
	if count <= 0 then return nil, 0 end
	return (total / count), count
end

local function BuildRaidStatusFromRaidsStore(all)
	if type(all) ~= "table" then return "-" end
	local bestDiff = -1
	local bestKilled = -1
	local bestShort = "-"
	for _, raidEntry in pairs(all) do
		if type(raidEntry) == "table" and type(raidEntry.best) == "table" then
			local best = raidEntry.best
			local diff = tonumber(best.diffID) or 0
			local killed = tonumber(best.killed) or 0
			local short = tostring(best.short or "")
			if short ~= "" then
				if diff > bestDiff or (diff == bestDiff and killed > bestKilled) then
					bestDiff = diff
					bestKilled = killed
					bestShort = short
				end
			end
		end
	end
	return bestShort
end

local function GetTalentLoadoutName()
	if type(C_ClassTalents) ~= "table" or type(C_ClassTalents.GetActiveConfigID) ~= "function" then
		return "-"
	end
	local configID = C_ClassTalents.GetActiveConfigID()
	if not configID then return "-" end
	if type(C_Traits) ~= "table" or type(C_Traits.GetConfigInfo) ~= "function" then
		return tostring(configID)
	end
	local cfg = C_Traits.GetConfigInfo(configID)
	if type(cfg) == "table" then
		local n = tostring(cfg.name or "")
		if n ~= "" then return n end
	end
	return tostring(configID)
end

local function ExtractRatingFromResult(...)
	local n = select("#", ...)
	if n <= 0 then return nil end
	local first = select(1, ...)
	if type(first) == "table" then
		local tableRating = tonumber(first.rating or first.currentRating or first.personalRating)
		if tableRating and tableRating > 0 then return tableRating end
	end
	for i = 1, n do
		local v = select(i, ...)
		if type(v) == "number" and v > 0 and v < 5000 then
			return v
		end
	end
	return nil
end

local function GetLocalPvPSummary()
	local parts = {}

	local hk = nil
	if type(GetPVPLifetimeStats) == "function" then
		local ok, a = pcall(GetPVPLifetimeStats)
		if ok then
			hk = tonumber(a)
		end
	end
	if hk and hk > 0 then
		parts[#parts + 1] = string.format("HK %d", hk)
	end

	local honorLevel = nil
	if type(C_PvP) == "table" and type(C_PvP.GetHonorLevel) == "function" then
		local ok, v = pcall(C_PvP.GetHonorLevel)
		if ok then
			honorLevel = tonumber(v)
		end
	end
	if honorLevel and honorLevel > 0 then
		parts[#parts + 1] = string.format("Honor %d", honorLevel)
	end

	local ratedText = nil
	if type(C_PvP) == "table" and type(C_PvP.GetPersonalRatedInfo) == "function" then
		local brackets = {
			{ key = "solo_shuffle", label = "Shuffle" },
			{ key = "blitz", label = "Blitz" },
			{ key = "3v3", label = "3v3" },
			{ key = "2v2", label = "2v2" },
			{ key = "rbg", label = "RBG" },
		}
		for i = 1, #brackets do
			local b = brackets[i]
			local ok, a, c, d, e, f = pcall(C_PvP.GetPersonalRatedInfo, b.key)
			if ok then
				local rating = ExtractRatingFromResult(a, c, d, e, f)
				if rating and rating > 0 then
					ratedText = string.format("%s %d", b.label, rating)
					break
				end
			end
		end
	end
	if ratedText then
		parts[#parts + 1] = ratedText
	end

	if #parts <= 0 then return "-" end
	return table.concat(parts, " | ")
end

local function GetLatestDomainRecordForGuid(domain, guid)
	if type(domain) ~= "string" or domain == "" then return nil end
	if type(guid) ~= "string" or guid == "" then return nil end
	local comm = GMS and GMS.Comm or nil
	if type(comm) ~= "table" or type(comm.GetRecordsByDomain) ~= "function" then
		return nil
	end

	local records = comm:GetRecordsByDomain(domain)
	if type(records) ~= "table" then return nil end

	local best = nil
	local bestUpdated = -1
	local bestSeq = -1
	for i = 1, #records do
		local rec = records[i]
		if type(rec) == "table" then
			local rOrigin = tostring(rec.originGUID or "")
			local rChar = tostring(rec.charGUID or "")
			if rOrigin == guid or rChar == guid then
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

	return best
end

local EQUIP_SLOT_ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }
local EQUIP_SLOT_NAMES = {
	[1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
	[9] = "Wrist", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2",
	[15] = "Back", [16] = "Main Hand", [17] = "Off Hand",
}

local function BuildEquipmentRowsFromSnapshot(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.slots) ~= "table" then
		return {}, nil, 0
	end

	local rows = {}
	for i = 1, #EQUIP_SLOT_ORDER do
		local slotId = EQUIP_SLOT_ORDER[i]
		local slot = snapshot.slots[slotId]
		if type(slot) == "table" then
			local link = tostring(slot.link or "")
			local itemId = tonumber(slot.itemId or 0) or 0
			local ilvl = tonumber(slot.itemLevel or 0) or 0
			local text = "-"
			if link ~= "" then
				text = link
			elseif itemId > 0 then
				text = string.format("item:%d", itemId)
			end

			rows[#rows + 1] = {
				slotId = slotId,
				slotName = EQUIP_SLOT_NAMES[slotId] or ("Slot " .. tostring(slotId)),
				text = text,
				link = link,
				itemLevel = (ilvl > 0) and ilvl or nil,
			}
		end
	end

	local ilvl, slots = BuildItemLevelFromEquipmentSnapshot(snapshot)
	return rows, ilvl, tonumber(slots) or 0
end

local function BuildMythicRows(dungeons)
	if type(dungeons) ~= "table" then return {} end
	local rows = {}
	for i = 1, #dungeons do
		local d = dungeons[i]
		if type(d) == "table" then
			local name = tostring(d.name or "")
			if name ~= "" then
				local level = tonumber(d.level) or 0
				local score = tonumber(d.score) or 0
				rows[#rows + 1] = {
					name = name,
					level = level,
					score = score,
				}
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		if a.level ~= b.level then return a.level > b.level end
		return tostring(a.name) < tostring(b.name)
	end)
	return rows
end

local function BuildRaidRows(all)
	if type(all) ~= "table" then return {} end
	local rows = {}
	for key, entry in pairs(all) do
		if type(entry) == "table" then
			local name = tostring(entry.name or ("Raid " .. tostring(key)))
			local short = "-"
			if type(entry.best) == "table" and tostring(entry.best.short or "") ~= "" then
				short = tostring(entry.best.short)
			end
			rows[#rows + 1] = { name = name, short = short }
		end
	end
	table.sort(rows, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return rows
end

local function GetRosterMemberByGuid(guid)
	local g = tostring(guid or "")
	if g == "" then return nil end
	local roster = GMS and (GMS:GetModule("ROSTER", true) or GMS:GetModule("Roster", true)) or nil
	if type(roster) ~= "table" or type(roster.GetMemberByGUID) ~= "function" then
		return nil
	end
	local ok, member = pcall(roster.GetMemberByGUID, roster, g)
	if ok and type(member) == "table" then
		return member
	end
	return nil
end

local function GetCharScopedModuleBucket(guid, moduleKey)
	if not GMS or not GMS.db or type(GMS.db.global) ~= "table" then
		return nil
	end
	local chars = GMS.db.global.characters
	if type(chars) ~= "table" then
		return nil
	end
	local g = tostring(guid or "")
	if g == "" and type(GMS.GetCharacterGUID) == "function" then
		g = tostring(GMS:GetCharacterGUID() or "")
	end
	if g == "" then
		return nil
	end
	local c = chars[g]
	if type(c) ~= "table" then
		return nil
	end
	local mod = c[tostring(moduleKey or "")]
	if type(mod) ~= "table" then
		return nil
	end
	return mod
end

local function MergeUniqueNames(dest, source)
	if type(dest) ~= "table" or type(source) ~= "table" then return end
	local seen = {}
	for i = 1, #dest do
		seen[string.lower(tostring(dest[i]))] = true
	end
	for i = 1, #source do
		local n = tostring(source[i] or "")
		n = n:gsub("^%s+", ""):gsub("%s+$", "")
		if n ~= "" then
			local key = string.lower(n)
			if not seen[key] then
				seen[key] = true
				dest[#dest + 1] = n
			end
		end
	end
end

local function NormalizeNameList(raw)
	local out = {}
	if type(raw) == "string" and raw ~= "" then
		out[#out + 1] = raw
		return out
	end
	if type(raw) ~= "table" then return out end

	for k, v in pairs(raw) do
		if type(v) == "string" then
			out[#out + 1] = v
		elseif type(v) == "table" then
			local n = tostring(v.name or v.name_full or v.character or v.char or "")
			if n ~= "" then out[#out + 1] = n end
		elseif type(k) == "string" and k ~= "" and v == true then
			out[#out + 1] = k
		end
	end
	return out
end

local function GetAccountCharactersForGuid(guid)
	local g = tostring(guid or "")
	if g == "" then return {}, false, "No character GUID available." end

	local names = {}
	local roster = GMS and (GMS:GetModule("ROSTER", true) or GMS:GetModule("Roster", true)) or nil
	if type(roster) == "table" and type(roster.GetMemberMeta) == "function" then
		local ok, meta = pcall(roster.GetMemberMeta, roster, g)
		if ok and type(meta) == "table" then
			MergeUniqueNames(names, NormalizeNameList(meta.accountCharacters))
			MergeUniqueNames(names, NormalizeNameList(meta.accountChars))
			MergeUniqueNames(names, NormalizeNameList(meta.sameAccountChars))
			MergeUniqueNames(names, NormalizeNameList(meta.alts))
		end
	end

	local rec = GetLatestDomainRecordForGuid("ACCOUNT_CHARS_V1", g)
	if rec and type(rec.payload) == "table" then
		MergeUniqueNames(names, NormalizeNameList(rec.payload.characters))
		MergeUniqueNames(names, NormalizeNameList(rec.payload.chars))
	end

	if #names <= 0 then
		return names, false, "No same-account guild characters recorded yet."
	end
	table.sort(names)
	return names, true, "Synced account-character list"
end

local function BuildCharData(player, ctxGuid, ctxName)
	local playerGuid = tostring((player and player.guid) or "")
	local targetGuid = tostring(ctxGuid or "")
	local isContext = (targetGuid ~= "" and targetGuid ~= playerGuid)
	local selectedGuid = isContext and targetGuid or playerGuid
	local selectedName = isContext and tostring(ctxName or "-") or tostring(player and player.name_full or "-")

	local data = {
		isContext = isContext,
		selectedGuid = selectedGuid,
		selectedName = selectedName,
		gmsVersion = tostring((GMS and GMS.VERSION) or "-"),
		general = {
			name = selectedName,
			guid = selectedGuid ~= "" and selectedGuid or "-",
			class = tostring((player and player.class) or "-"),
			classFile = tostring((player and player.classFile) or ""),
			race = tostring((player and player.race) or "-"),
			faction = LocalizeFactionName((UnitFactionGroup and UnitFactionGroup("player")) or "-"),
			level = tostring((player and player.level) or "-"),
			spec = tostring((player and player.spec) or "-"),
			guild = tostring((player and player.guild) or "-"),
		},
		mythic = { score = nil, rows = {}, hasData = false, source = "-" },
		raids = { summary = "-", rows = {}, hasData = false, source = "-" },
		equipment = { ilvl = nil, slots = 0, rows = {}, hasData = false, source = "-" },
		pvp = { summary = "-", hasData = false, source = "-" },
		talents = { summary = "-", hasData = false, source = "-" },
		accountChars = { rows = {}, hasData = false, source = "-" },
		hasAnyExternalData = false,
	}

	if not isContext then
		data.general.name = tostring((player and player.name_full) or "-")
		data.general.guid = playerGuid ~= "" and playerGuid or "-"
		data.general.class = tostring((player and player.class) or "-")
		data.general.classFile = tostring((player and player.classFile) or "")
		data.general.race = tostring((player and player.race) or "-")
		data.general.faction = LocalizeFactionName((UnitFactionGroup and UnitFactionGroup("player")) or "-")
		data.general.level = tostring((player and player.level) or "-")
		data.general.spec = tostring((player and player.spec) or "-")
		data.general.guild = tostring((player and player.guild) or "-")

		local mythic = GMS and GMS:GetModule("MythicPlus", true) or nil
		if type(mythic) == "table" and type(mythic._options) == "table" then
			local score = tonumber(mythic._options.score)
			local rows = BuildMythicRows(mythic._options.dungeons)
			data.mythic.score = score
			data.mythic.rows = rows
			data.mythic.hasData = (score and score > 0) or (#rows > 0)
			data.mythic.source = "Local module data"
		end

		local raids = GMS and (GMS:GetModule("RAIDS", true) or GMS:GetModule("Raids", true)) or nil
		local raidStore = raids and raids._options and raids._options.raids or nil
		data.raids.summary = BuildRaidStatusFromRaidsStore(raidStore)
		data.raids.rows = BuildRaidRows(raidStore)
		data.raids.hasData = #data.raids.rows > 0
		data.raids.source = "Local module data"

		local equip = GMS and GMS:GetModule("Equipment", true) or nil
		local eqSnapshot = equip and equip._options and equip._options.equipment and equip._options.equipment.snapshot or nil
		if type(eqSnapshot) ~= "table" then
			local eqBucket = GetCharScopedModuleBucket(playerGuid, "EQUIPMENT")
			if type(eqBucket) == "table" and type(eqBucket.equipment) == "table" and type(eqBucket.equipment.snapshot) == "table" then
				eqSnapshot = eqBucket.equipment.snapshot
				data.equipment.source = "Saved character DB"
			end
		end
		if type(eqSnapshot) ~= "table" then
			local recEquipLocal = GetLatestDomainRecordForGuid("EQUIPMENT_V1", playerGuid)
			if recEquipLocal and type(recEquipLocal.payload) == "table" and type(recEquipLocal.payload.snapshot) == "table" then
				eqSnapshot = recEquipLocal.payload.snapshot
				data.equipment.source = "Synced EQUIPMENT_V1"
			end
		end
		local rows, ilvl, slots = BuildEquipmentRowsFromSnapshot(eqSnapshot)
		if (not ilvl or ilvl <= 0) and type(GetAverageItemLevel) == "function" then
			local _, equipped = GetAverageItemLevel()
			ilvl = tonumber(equipped)
		end
		data.equipment.rows = rows
		data.equipment.ilvl = ilvl
		data.equipment.slots = slots
		data.equipment.hasData = (ilvl and ilvl > 0) or (#rows > 0)
		if data.equipment.source == "-" then
			data.equipment.source = "Local module data"
		end

		local loadout = GetTalentLoadoutName()
		local specText = tostring((player and player.spec) or "-")
		if loadout ~= "-" and specText ~= "-" then
			data.talents.summary = specText .. " | " .. loadout
		else
			data.talents.summary = (loadout ~= "-" and loadout) or specText
		end
		data.talents.hasData = data.talents.summary ~= "-" and data.talents.summary ~= ""
		data.talents.source = "Local API"

		data.pvp.summary = GetLocalPvPSummary()
		data.pvp.hasData = data.pvp.summary ~= "-"
		data.pvp.source = "Local API"
	else
		local member = GetRosterMemberByGuid(targetGuid)
		if type(member) == "table" then
			data.general.name = tostring(member.name_full or member.name or selectedName)
			data.general.class = tostring(member.class or "-")
			data.general.classFile = tostring(member.classFileName or "")
			data.general.race = tostring(member.race or "-")
			data.general.level = tostring(member.level or "-")
			data.general.spec = tostring(member.spec or "-")
			data.general.guild = tostring(member.guild or "-")
		end

		local recMeta = GetLatestDomainRecordForGuid("roster_meta", targetGuid)
		if recMeta and type(recMeta.payload) == "table" then
			local p = recMeta.payload
			local v = tostring(p.version or "")
			if v ~= "" then data.gmsVersion = v end
			local score = tonumber(p.mplus)
			if score and score >= 0 then
				data.mythic.score = score
				data.mythic.hasData = true
				data.mythic.source = "Synced roster_meta"
			end
			local raid = tostring(p.raid or "")
			if raid ~= "" and raid ~= "-" then
				data.raids.summary = raid
				data.raids.hasData = true
				data.raids.source = "Synced roster_meta"
			end
			local ilvl = tonumber(p.ilvl)
			if ilvl and ilvl > 0 then
				data.equipment.ilvl = ilvl
				data.equipment.hasData = true
				data.equipment.source = "Synced roster_meta"
			end
			local talentText = tostring(p.talents or "")
			if talentText ~= "" then
				data.talents.summary = talentText
				data.talents.hasData = true
				data.talents.source = "Synced roster_meta"
			end
			local pvpText = tostring(p.pvp or "")
			if pvpText ~= "" then
				data.pvp.summary = pvpText
				data.pvp.hasData = true
				data.pvp.source = "Synced roster_meta"
			end
		end

		local recM = GetLatestDomainRecordForGuid("MYTHICPLUS_V1", targetGuid)
		if recM and type(recM.payload) == "table" then
			local rows = BuildMythicRows(recM.payload.dungeons)
			local score = tonumber(recM.payload.score)
			data.mythic.rows = rows
			data.mythic.score = score or data.mythic.score
			data.mythic.hasData = (score and score > 0) or (#rows > 0) or data.mythic.hasData
			data.mythic.source = "Synced MYTHICPLUS_V1"
		end

		local recR = GetLatestDomainRecordForGuid("RAIDS_V1", targetGuid)
		if recR and type(recR.payload) == "table" then
			local rows = BuildRaidRows(recR.payload.raids)
			local summary = BuildRaidStatusFromRaidsStore(recR.payload.raids)
			if summary ~= "" and summary ~= "-" then
				data.raids.summary = summary
			end
			data.raids.rows = rows
			data.raids.hasData = (#rows > 0) or (data.raids.summary ~= "-") or data.raids.hasData
			data.raids.source = "Synced RAIDS_V1"
		end

		local recEquip = GetLatestDomainRecordForGuid("EQUIPMENT_V1", targetGuid)
		if recEquip and type(recEquip.payload) == "table" then
			local rows, ilvl, slots = BuildEquipmentRowsFromSnapshot(recEquip.payload.snapshot)
			if ilvl and ilvl > 0 then
				data.equipment.ilvl = ilvl
			end
			data.equipment.rows = rows
			data.equipment.slots = slots
			data.equipment.hasData = (#rows > 0) or (data.equipment.ilvl and data.equipment.ilvl > 0) or data.equipment.hasData
			data.equipment.source = "Synced EQUIPMENT_V1"
		end

		if not data.talents.hasData then
			data.talents.summary = "No synced talents yet (placeholder)."
			data.talents.source = "Placeholder"
		end
		if not data.pvp.hasData then
			data.pvp.summary = "No synced PvP data yet (placeholder)."
			data.pvp.source = "Placeholder"
		end
	end

	local accountRows, accountHasData, accountSource = GetAccountCharactersForGuid(selectedGuid)
	data.accountChars.rows = accountRows
	data.accountChars.hasData = accountHasData
	data.accountChars.source = accountSource

	data.hasAnyExternalData = data.mythic.hasData
		or data.raids.hasData
		or data.equipment.hasData
		or data.talents.hasData
		or data.pvp.hasData
		or data.accountChars.hasData

	return data
end

local function RenderBlock(titleText, lines)
	local out = {}
	out[#out + 1] = "|cff03A9F4" .. tostring(titleText or "") .. "|r"
	for _, l in ipairs(lines or {}) do
		out[#out + 1] = tostring(l)
	end
	return table.concat(out, "\n")
end

local function AddInfoLine(parent, key, value)
	if not parent or type(parent.AddChild) ~= "function" then return end
	local lbl = AceGUI:Create("Label")
	lbl:SetFullWidth(true)
	lbl:SetText(string.format("|cff9d9d9d%s:|r |cffffffff%s|r", tostring(key or "-"), tostring(value or "-")))
	if lbl.label then
		lbl.label:SetFontObject(GameFontNormalSmallOutline)
	end
	parent:AddChild(lbl)
end

local function GetClassHex(classFile)
	local c = (type(RAID_CLASS_COLORS) == "table" and classFile ~= "" and RAID_CLASS_COLORS[classFile]) or nil
	if not c then return "FFFFFFFF" end
	return c.colorStr or "FFFFFFFF"
end

local function AddCardTitle(parent, text)
	local title = AceGUI:Create("Label")
	title:SetFullWidth(true)
	title:SetText("|cffffd200" .. tostring(text or "") .. "|r")
	parent:AddChild(title)
end

local function AddMutedLine(parent, text)
	local line = AceGUI:Create("Label")
	line:SetFullWidth(true)
	line:SetText("|cffb8b8b8" .. tostring(text or "") .. "|r")
	if line.label then
		line.label:SetFontObject(GameFontNormalSmallOutline)
	end
	parent:AddChild(line)
end

local function AddNoDataHint(parent, text)
	local line = AceGUI:Create("Label")
	line:SetFullWidth(true)
	line:SetText("|cffffb366" .. tostring(text or "No data available.") .. "|r")
	if line.label then
		line.label:SetFontObject(GameFontNormalSmallOutline)
	end
	parent:AddChild(line)
end

local function AddValueLine(parent, leftText, rightText)
	local row = AceGUI:Create("SimpleGroup")
	row:SetFullWidth(true)
	row:SetLayout("Flow")
	parent:AddChild(row)

	local left = AceGUI:Create("Label")
	left:SetWidth(140)
	left:SetText("|cff9d9d9d" .. tostring(leftText or "-") .. "|r")
	row:AddChild(left)

	local right = AceGUI:Create("Label")
	right:SetWidth(280)
	right:SetText("|cffffffff" .. tostring(rightText or "-") .. "|r")
	row:AddChild(right)
end

local function GetClassIconCoords(classFile)
	---@diagnostic disable-next-line: undefined-global
	local coords = (type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[tostring(classFile or "")]) or nil
	if type(coords) == "table" then
		return coords[1], coords[2], coords[3], coords[4]
	end
	return 0, 1, 0, 1
end

local function BuildCharInfoUIHeader(ui, details, ctxFrom)
	if not ui or type(ui.Header_Clear) ~= "function" or type(ui.GetHeaderContent) ~= "function" then
		return false
	end
	if not AceGUI then return false end

	ui:Header_Clear()
	local hc = ui:GetHeaderContent()
	if not hc then return false end
	if type(hc.SetLayout) == "function" then
		hc:SetLayout("Flow")
	end

	local icon = AceGUI:Create("Icon")
	icon:SetImage("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
	icon:SetImageSize(18, 18)
	icon:SetWidth(26)
	local cl, cr, ct, cb = GetClassIconCoords(details and details.general and details.general.classFile or "")
	if icon.image and type(icon.image.SetTexCoord) == "function" then
		icon.image:SetTexCoord(cl, cr, ct, cb)
	end
	hc:AddChild(icon)

	local classHex = GetClassHex(details and details.general and details.general.classFile or "")
	local colorCode = tostring(classHex or "FFFFFFFF")
	if #colorCode == 6 then colorCode = "FF" .. colorCode end

	local name = AceGUI:Create("Label")
	name:SetWidth(240)
	name:SetText(string.format("|c%s%s|r", colorCode, tostring(details and details.general and details.general.name or "-")))
	if name.label then
		name.label:SetFontObject(GameFontNormalOutline)
		name.label:SetJustifyH("LEFT")
		name.label:SetJustifyV("MIDDLE")
	end
	hc:AddChild(name)

	local totalWidth = 980
	if ui and ui._frame and type(ui._frame.GetWidth) == "function" then
		totalWidth = math.max(760, tonumber(ui._frame:GetWidth()) or 980)
	end
	local leftMetaWidth = math.max(260, math.floor(totalWidth - 360))

	local leftMeta = AceGUI:Create("Label")
	leftMeta:SetWidth(leftMetaWidth)
	leftMeta:SetText(string.format(
		"|cff9d9d9dLevel|r %s  |cff9d9d9dRace|r %s  |cff9d9d9dFaction|r %s  |cff9d9d9dGUID|r %s",
		tostring(details and details.general and details.general.level or "-"),
		tostring(details and details.general and details.general.race or "-"),
		LocalizeFactionName(details and details.general and details.general.faction or "-"),
		tostring(details and details.general and details.general.guid or "-")
	))
	if leftMeta.label then
		leftMeta.label:SetFontObject(GameFontNormalSmallOutline)
		leftMeta.label:SetJustifyH("LEFT")
		leftMeta.label:SetJustifyV("MIDDLE")
	end
	hc:AddChild(leftMeta)

	local actions = AceGUI:Create("Icon")
	actions:SetImage("Interface\\Icons\\INV_Misc_Gear_01")
	actions:SetImageSize(16, 16)
	actions:SetWidth(24)
	actions:SetHeight(20)
	actions:SetCallback("OnClick", function()
		ShowHeaderActionsMenu(details)
	end)
	if actions.image and type(actions.image.SetDesaturated) == "function" then
		actions.image:SetDesaturated(false)
	end
	if actions.image and type(actions.image.SetTexCoord) == "function" then
		actions.image:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
	if actions.SetLabel then
		actions:SetLabel("")
	end
	hc:AddChild(actions)

	return true
end

local DEFAULT_CARD_ORDER = { "MYTHIC", "EQUIPMENT", "RAIDS", "OVERVIEW", "ACCOUNT", "TALENTS", "PVP" }

local function ResolveCardOrder(opts)
	local allowed = {
		MYTHIC = true,
		EQUIPMENT = true,
		RAIDS = true,
		OVERVIEW = true,
		ACCOUNT = true,
		TALENTS = true,
		PVP = true,
	}

	local out = {}
	local seen = {}
	local raw = type(opts) == "table" and opts.cardOrder or nil
	if type(raw) == "table" then
		for i = 1, #raw do
			local id = tostring(raw[i] or ""):upper()
			if allowed[id] and not seen[id] then
				seen[id] = true
				out[#out + 1] = id
			end
		end
	end

	for i = 1, #DEFAULT_CARD_ORDER do
		local id = DEFAULT_CARD_ORDER[i]
		if not seen[id] then
			out[#out + 1] = id
		end
	end

	return out
end

local function BuildDetailsSignature(details)
	if type(details) ~= "table" then return "" end
	local out = {
		tostring(details.general and details.general.guid or ""),
		tostring(details.general and details.general.name or ""),
		tostring(details.general and details.general.spec or ""),
		tostring(details.general and details.general.level or ""),
		tostring(details.gmsVersion or ""),
		tostring(details.mythic and details.mythic.score or ""),
		tostring(details.raids and details.raids.summary or ""),
		tostring(details.equipment and details.equipment.ilvl or ""),
		tostring(details.talents and details.talents.summary or ""),
		tostring(details.pvp and details.pvp.summary or ""),
	}

	local mythicRows = details.mythic and details.mythic.rows or {}
	for i = 1, #mythicRows do
		local r = mythicRows[i]
		out[#out + 1] = tostring(r.name or "")
		out[#out + 1] = tostring(r.level or "")
		out[#out + 1] = tostring(r.score or "")
	end

	local raidRows = details.raids and details.raids.rows or {}
	for i = 1, #raidRows do
		local r = raidRows[i]
		out[#out + 1] = tostring(r.name or "")
		out[#out + 1] = tostring(r.short or "")
	end

	local eqRows = details.equipment and details.equipment.rows or {}
	for i = 1, #eqRows do
		local r = eqRows[i]
		out[#out + 1] = tostring(r.slotId or "")
		out[#out + 1] = tostring(r.text or "")
		out[#out + 1] = tostring(r.itemLevel or "")
	end

	local accountRows = details.accountChars and details.accountChars.rows or {}
	for i = 1, #accountRows do
		out[#out + 1] = tostring(accountRows[i] or "")
	end

	return table.concat(out, "|")
end

local function StopUIDataTicker()
	local t = CHARINFO._uiDataTicker
	if t and type(t.Cancel) == "function" then
		pcall(function() t:Cancel() end)
	end
	CHARINFO._uiDataTicker = nil
end

function CHARINFO:StartUIDataTicker(ctxState)
	StopUIDataTicker()
	if not C_Timer or type(C_Timer.NewTicker) ~= "function" then return end

	local state = type(ctxState) == "table" and ctxState or nil
	local ctxGuid = state and state.guid or nil
	local ctxName = state and state.name_full or nil

	local initialPlayer = GetPlayerSnapshot()
	local initialDetails = BuildCharData(initialPlayer, ctxGuid, ctxName)
	self._uiDataLastSig = BuildDetailsSignature(initialDetails)

	self._uiDataTicker = C_Timer.NewTicker(1.5, function()
		local ui = UIRef()
		if not ui or ui._page ~= "CHARINFO" then
			StopUIDataTicker()
			return
		end

		local playerNow = GetPlayerSnapshot()
		local detailsNow = BuildCharData(playerNow, ctxGuid, ctxName)
		local sigNow = BuildDetailsSignature(detailsNow)
		if sigNow == self._uiDataLastSig then
			return
		end

		self._uiDataLastSig = sigNow
		if state and (state.guid or state.name_full) then
			SetNavContext(state)
		end
		OpenSelf()
	end)
end

local function EnsureResizeHook(root)
	if not root or not root.frame or type(root.frame.HookScript) ~= "function" then
		return
	end
	if root.frame._gmsCharInfoResizeHooked then
		return
	end

	root.frame._gmsCharInfoResizeHooked = true
	root.frame:HookScript("OnSizeChanged", function()
		if CHARINFO._resizeRefreshPending then
			return
		end
		CHARINFO._resizeRefreshPending = true

		if C_Timer and type(C_Timer.After) == "function" then
			C_Timer.After(0.12, function()
				CHARINFO._resizeRefreshPending = false
				local ui = UIRef()
				if not ui or ui._page ~= "CHARINFO" then
					return
				end
				OpenSelf()
			end)
		else
			CHARINFO._resizeRefreshPending = false
			local ui = UIRef()
			if ui and ui._page == "CHARINFO" then
				OpenSelf()
			end
		end
	end)
end

-- ###########################################################################
-- #	UI PAGE
-- ###########################################################################

function CHARINFO:TryRegisterPage()
	if self._pageRegistered then return true end

	local ui = UIRef()
	if not ui or type(ui.RegisterPage) ~= "function" then
		return false
	end

	ui:RegisterPage("CHARINFO", 60, DISPLAY_NAME, function(root, id, isCached)
		local ui2 = UIRef()
		local ctx = GetNavContext(false) or nil
		local player = GetPlayerSnapshot()

		local ctxName = ctx and ctx.name_full or nil
		local ctxGuid = ctx and ctx.guid or nil
		local ctxFrom = ctx and (ctx.from or ctx.source) or nil

		if isCached and root and type(root.ReleaseChildren) == "function" then
			root:ReleaseChildren()
		end

		local details = BuildCharData(player, ctxGuid, ctxName)
		EnsureResizeHook(root)

		BuildCharInfoUIHeader(ui2, details, details.isContext and (ctxFrom or "external") or "local")
		if ui2 and type(ui2.SetStatusText) == "function" then
			ui2:SetStatusText(details.isContext and "CHARINFO: context active" or "CHARINFO: player only")
		end

		if type(root.SetLayout) == "function" then
			root:SetLayout("Fill")
		end

		local outer = AceGUI:Create("SimpleGroup")
		outer:SetFullWidth(true)
		outer:SetFullHeight(true)
		outer:SetLayout("Fill")
		root:AddChild(outer)

		local scroller = AceGUI:Create("ScrollFrame")
		scroller:SetFullWidth(true)
		scroller:SetFullHeight(true)
		scroller:SetLayout("Flow")
		outer:AddChild(scroller)

		local wrapper = AceGUI:Create("SimpleGroup")
		wrapper:SetFullWidth(true)
		wrapper:SetFullHeight(true)
		wrapper:SetLayout("List")
		scroller:AddChild(wrapper)

		local actions = AceGUI:Create("SimpleGroup")
		actions:SetLayout("Flow")
		actions:SetFullWidth(true)
		wrapper:AddChild(actions)

		local btnSelf = AceGUI:Create("Button")
		btnSelf:SetText("Use Player")
		btnSelf:SetWidth(150)
		btnSelf:SetCallback("OnClick", function()
			SetNavContext({
				from = "charinfo",
				name_full = player.name_full,
				guid = player.guid,
				unit = "player",
			})
			if ui2 and type(ui2.SetStatusText) == "function" then
				ui2:SetStatusText("CHARINFO: context = player")
			end
			OpenSelf()
		end)
		actions:AddChild(btnSelf)

		local btnTarget = AceGUI:Create("Button")
		btnTarget:SetText("Use Target")
		btnTarget:SetWidth(150)
		btnTarget:SetCallback("OnClick", function()
			local t = GetTargetSnapshot()
			if not t then
				if ui2 and type(ui2.SetStatusText) == "function" then
					ui2:SetStatusText("CHARINFO: no player target")
				end
				return
			end
			SetNavContext({
				from = "charinfo",
				name_full = t.name_full,
				guid = t.guid,
				unit = "target",
			})
			if ui2 and type(ui2.SetStatusText) == "function" then
				ui2:SetStatusText("CHARINFO: context = target")
			end
			OpenSelf()
		end)
		actions:AddChild(btnTarget)

		local btnClear = AceGUI:Create("Button")
		btnClear:SetText("Clear Context")
		btnClear:SetWidth(150)
		btnClear:SetCallback("OnClick", function()
			SetNavContext(nil)
			if ui2 and type(ui2.SetStatusText) == "function" then
				ui2:SetStatusText("CHARINFO: context cleared")
			end
			OpenSelf()
		end)
		actions:AddChild(btnClear)

		local btnRefresh = AceGUI:Create("Button")
		btnRefresh:SetText("Refresh")
		btnRefresh:SetWidth(150)
		btnRefresh:SetCallback("OnClick", function()
			OpenSelf()
		end)
		actions:AddChild(btnRefresh)

		if details.isContext and not details.hasAnyExternalData then
			local warn = AceGUI:Create("SimpleGroup")
			warn:SetFullWidth(true)
			warn:SetLayout("List")
			wrapper:AddChild(warn)
			AddCardTitle(warn, "No Data Found")
			AddNoDataHint(warn, "No synced data exists for this character yet. Data will appear after sync/module scans.")
		end

		local contentRow = AceGUI:Create("SimpleGroup")
		contentRow:SetFullWidth(true)
		contentRow:SetLayout("List")
		wrapper:AddChild(contentRow)

		local pageWidth = 1080
		if root and root.frame and type(root.frame.GetWidth) == "function" then
			local w = tonumber(root.frame:GetWidth()) or 1080
			if w > 0 then
				pageWidth = w
			end
		end
		local innerWidth = pageWidth - 40
		if innerWidth < 860 then innerWidth = 860 end
		local colWidth = math.floor((innerWidth - 10) / 2)
		if colWidth < 420 then colWidth = 420 end

		local opts = (type(CHARINFO._options) == "table") and CHARINFO._options or nil
		local lastUpdate = (opts and tonumber(opts.lastUpdate)) or 0

		local function NewCardContainer(parent, titleText)
			local card = AceGUI:Create("InlineGroup")
			card:SetTitle("")
			card:SetFullWidth(true)
			card:SetLayout("List")
			parent:AddChild(card)
			AddCardTitle(card, titleText)
			return card
		end

		local function BuildCard_Mythic(parent)
			local card = NewCardContainer(parent, "Mythic Dungeons")
			AddValueLine(card, "Score", (details.mythic.score and tostring(details.mythic.score)) or "-")
			AddValueLine(card, "Source", details.mythic.source or "-")
			if #details.mythic.rows <= 0 then
				AddNoDataHint(card, "No Mythic+ data available for this character.")
				return
			end
			local maxRows = math.min(#details.mythic.rows, 10)
			for i = 1, maxRows do
				local row = details.mythic.rows[i]
				local levelText = (tonumber(row.level) or 0) > 0 and ("+" .. tostring(row.level)) or "-"
				local scoreText = (tonumber(row.score) or 0) > 0 and tostring(row.score) or "-"
				AddMutedLine(card, string.format("%s   key: %s   score: %s", tostring(row.name or "-"), levelText, scoreText))
			end
		end

		local function BuildCard_Equipment(parent)
			local card = NewCardContainer(parent, "Equipment")
			local ilvlText = (details.equipment.ilvl and string.format("%.1f", details.equipment.ilvl)) or "-"
			AddValueLine(card, "Item Level", ilvlText)
			AddValueLine(card, "Captured Slots", tostring(details.equipment.slots or 0))
			AddValueLine(card, "Source", details.equipment.source or "-")
			if #details.equipment.rows <= 0 then
				AddNoDataHint(card, "No equipment snapshot available for this character.")
				return
			end
			local equipSlotWidth = 110
			local equipLvlWidth = 70
			local equipItemWidth = colWidth - equipSlotWidth - equipLvlWidth - 40
			if equipItemWidth < 180 then equipItemWidth = 180 end
			for i = 1, #details.equipment.rows do
				local e = details.equipment.rows[i]
				local row = AceGUI:Create("SimpleGroup")
				row:SetFullWidth(true)
				row:SetLayout("Flow")
				card:AddChild(row)

				local slot = AceGUI:Create("Label")
				slot:SetWidth(equipSlotWidth)
				slot:SetText("|cff9d9d9d" .. tostring(e.slotName or "-") .. "|r")
				row:AddChild(slot)

				local item = AceGUI:Create("InteractiveLabel")
				item:SetWidth(equipItemWidth)
				item:SetText(tostring(e.text or "-"))
				if item.label then
					item.label:SetJustifyH("LEFT")
					item.label:SetWordWrap(false)
				end
				if tostring(e.link or "") ~= "" then
					item:SetCallback("OnEnter", function(widget)
						if GameTooltip and widget and widget.frame then
							GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
							GameTooltip:SetHyperlink(tostring(e.link))
							GameTooltip:Show()
						end
					end)
					item:SetCallback("OnLeave", function()
						if GameTooltip then GameTooltip:Hide() end
					end)
					item:SetCallback("OnClick", function()
						if type(HandleModifiedItemClick) == "function" then
							HandleModifiedItemClick(tostring(e.link))
						end
					end)
				end
				row:AddChild(item)

				local lvl = AceGUI:Create("Label")
				lvl:SetWidth(equipLvlWidth)
				local l = tonumber(e.itemLevel)
				lvl:SetText((l and l > 0) and ("|cff03A9F4" .. tostring(l) .. "|r") or "|cff7f7f7f-|r")
				row:AddChild(lvl)
			end
		end

		local function BuildCard_Raids(parent)
			local card = NewCardContainer(parent, "Raid Data")
			AddValueLine(card, "Best", details.raids.summary or "-")
			AddValueLine(card, "Source", details.raids.source or "-")
			if #details.raids.rows <= 0 then
				AddNoDataHint(card, "No raid progress data available for this character.")
				return
			end
			local maxRows = math.min(#details.raids.rows, 8)
			for i = 1, maxRows do
				local row = details.raids.rows[i]
				AddMutedLine(card, string.format("%s: %s", tostring(row.name or "-"), tostring(row.short or "-")))
			end
		end

		local function BuildCard_Overview(parent)
			local card = NewCardContainer(parent, "Character Overview")
			AddValueLine(card, "Name", details.general.name or "-")
			AddValueLine(card, "GUID", details.general.guid or "-")
			AddValueLine(card, "Class", details.general.class or "-")
			AddValueLine(card, "Race", details.general.race or "-")
			AddValueLine(card, "Level", details.general.level or "-")
			AddValueLine(card, "Spec", details.general.spec or "-")
			AddValueLine(card, "Guild", details.general.guild or "-")
			AddValueLine(card, "GMS Version", details.gmsVersion or "-")
			AddValueLine(card, "Last Local Update", (lastUpdate > 0 and tostring(lastUpdate) or "-"))
		end

		local function BuildCard_Account(parent)
			local card = NewCardContainer(parent, "Guild Characters on Same Account")
			AddValueLine(card, "Source", details.accountChars.source or "-")
			if #details.accountChars.rows <= 0 then
				AddNoDataHint(card, "No linked account characters recorded yet (placeholder for upcoming account-link tracking).")
				return
			end
			for i = 1, #details.accountChars.rows do
				AddMutedLine(card, tostring(details.accountChars.rows[i] or "-"))
			end
		end

		local function BuildCard_Talents(parent)
			local card = NewCardContainer(parent, "Talents")
			AddValueLine(card, "Summary", details.talents.summary or "-")
			AddValueLine(card, "Source", details.talents.source or "-")
		end

		local function BuildCard_PvP(parent)
			local card = NewCardContainer(parent, "PvP")
			AddValueLine(card, "Summary", details.pvp.summary or "-")
			AddValueLine(card, "Source", details.pvp.source or "-")
		end

		local cardBuilders = {
			MYTHIC = BuildCard_Mythic,
			EQUIPMENT = BuildCard_Equipment,
			RAIDS = BuildCard_Raids,
			OVERVIEW = BuildCard_Overview,
			ACCOUNT = BuildCard_Account,
			TALENTS = BuildCard_Talents,
			PVP = BuildCard_PvP,
		}

		local function RenderCardInto(parent, cardId)
			local b = cardBuilders[cardId]
			if type(b) == "function" then
				b(parent)
				return true
			end
			return false
		end

		local leftPinned = { "RAIDS", "MYTHIC", "PVP" }
		local rightPinned = { "EQUIPMENT", "TALENTS" }
		local pinned = {}
		for i = 1, #leftPinned do pinned[leftPinned[i]] = true end
		for i = 1, #rightPinned do pinned[rightPinned[i]] = true end

		local pinnedRow = AceGUI:Create("SimpleGroup")
		pinnedRow:SetFullWidth(true)
		pinnedRow:SetLayout("Flow")
		contentRow:AddChild(pinnedRow)

		local leftStack = AceGUI:Create("SimpleGroup")
		leftStack:SetLayout("List")
		leftStack:SetRelativeWidth(0.495)
		pinnedRow:AddChild(leftStack)

		local rightStack = AceGUI:Create("SimpleGroup")
		rightStack:SetLayout("List")
		rightStack:SetRelativeWidth(0.495)
		pinnedRow:AddChild(rightStack)

		for i = 1, #leftPinned do
			RenderCardInto(leftStack, leftPinned[i])
		end
		for i = 1, #rightPinned do
			RenderCardInto(rightStack, rightPinned[i])
		end

		-- Remaining cards (not pinned) are rendered as free cards below.
		local order = ResolveCardOrder(opts)
		for i = 1, #order do
			local id = order[i]
			if not pinned[id] then
				local freeRow = AceGUI:Create("SimpleGroup")
				freeRow:SetFullWidth(true)
				freeRow:SetLayout("Flow")
				contentRow:AddChild(freeRow)

				local freeCol = AceGUI:Create("SimpleGroup")
				freeCol:SetLayout("List")
				freeCol:SetFullWidth(true)
				freeRow:AddChild(freeCol)

				RenderCardInto(freeCol, id)
			end
		end

		if C_Timer and type(C_Timer.After) == "function" then
			C_Timer.After(0, function()
				if scroller and type(scroller.DoLayout) == "function" then scroller:DoLayout() end
				if outer and type(outer.DoLayout) == "function" then outer:DoLayout() end
			end)
		end

		CHARINFO:StartUIDataTicker({
			from = ctxFrom or "charinfo",
			guid = ctxGuid,
			name_full = ctxName,
		})
	end)

	self._pageRegistered = true
	return true
end
function CHARINFO:TryRegisterDockIcon()
	if self._dockRegistered then return true end

	local ui = UIRef()
	if not ui or type(ui.AddRightDockIconTop) ~= "function" then
		return false
	end

	ui:AddRightDockIconTop({
		id = "CHARINFO",
		order = 60,
		selectable = true,
		icon = ICON,
		tooltipTitle = DISPLAY_NAME,
		tooltipText = "Ã–ffnet die Charakter-Info",
		onClick = function()
			local u = UIRef()
			if u and type(u.Open) == "function" then
				u:Open("CHARINFO")
			end
		end,
	})

	self._dockRegistered = true
	return true
end

-- ###########################################################################
-- #	INTEGRATION / RETRY
-- ###########################################################################

function CHARINFO:TryIntegrateWithUIIfAvailable()
	if self._integrated then return true end

	local okPage = self:TryRegisterPage()
	local okDock = self:TryRegisterDockIcon()

	if okPage and okDock then
		self._integrated = true
		if self._ticker then
			local ticker = self._ticker
			---@cast ticker GMSTickerHandle
			pcall(function() ticker:Cancel() end)
		end
		self._ticker = nil
		LOCAL_LOG("INFO", "Integrated with UI")
		return true
	end
	return false
end

function CHARINFO:StartIntegrationTicker()
	if self._integrated then return end
	if self._ticker then return end
	if not C_Timer or type(C_Timer.NewTicker) ~= "function" then return end

	local tries = 0
	self._ticker = C_Timer.NewTicker(0.50, function()
		tries = tries + 1
		if CHARINFO:TryIntegrateWithUIIfAvailable() then return end
		if tries >= 30 then
			if CHARINFO._ticker then
				local ticker = CHARINFO._ticker
				---@cast ticker GMSTickerHandle
				pcall(function() ticker:Cancel() end)
			end
			CHARINFO._ticker = nil
			LOCAL_LOG("WARN", "UI not available (gave up retries)")
		end
	end)
end

-- ###########################################################################
-- #	ACE LIFECYCLE
-- ###########################################################################

function CHARINFO:InitializeOptions()
	-- Register character-specific options using new API
	if GMS and type(GMS.RegisterModuleOptions) == "function" then
		pcall(function()
			GMS:RegisterModuleOptions("CHARINFO", OPTIONS_DEFAULTS, "CHAR")
		end)
	end

	-- Retrieve options table
	if GMS and type(GMS.GetModuleOptions) == "function" then
		local ok, opts = pcall(GMS.GetModuleOptions, GMS, "CHARINFO")
		if ok and opts then
			self._options = opts
		end
	end

	-- Auto-log current player character
	local opts = (type(self._options) == "table") and self._options or nil
	if opts and opts.autoLog then
		local snap = GetPlayerSnapshot()
		if snap and snap.name_full then
			opts.lastUpdate = time and time() or 0
			LOCAL_LOG("INFO", "Character auto-logged: %s", tostring(snap.name_full))
		else
			LOCAL_LOG("WARN", "Character snapshot missing; not auto-logged")
		end
	else
		LOCAL_LOG("DEBUG", "CHARINFO options not available or auto-log disabled")
	end
end

function CHARINFO:OnEnable()
	-- Initialize character-specific options
	SafeCall(CHARINFO.InitializeOptions, CHARINFO)

	-- Ensure we attempt to initialize again when player fully logs in / enters world
	if type(self.RegisterEvent) == "function" then
		self:RegisterEvent("PLAYER_LOGIN", function()
			SafeCall(CHARINFO.InitializeOptions, CHARINFO)
		end)
		self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
			SafeCall(CHARINFO.InitializeOptions, CHARINFO)
		end)
	end

	self:TryIntegrateWithUIIfAvailable()
	self:StartIntegrationTicker()

	if type(self.RegisterEvent) == "function" then
		self:RegisterEvent("PLAYER_LOGIN", function()
			SafeCall(CHARINFO.TryIntegrateWithUIIfAvailable, CHARINFO)
		end)
	end

	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
end

function CHARINFO:OnDisable()
	StopUIDataTicker()
	if self._ticker then
		local ticker = self._ticker
		---@cast ticker GMSTickerHandle
		pcall(function() ticker:Cancel() end)
	end
	self._ticker = nil
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end

