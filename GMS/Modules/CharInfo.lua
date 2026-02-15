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
	VERSION      = "1.0.8",
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
local UnitFullName               = UnitFullName
local UnitClass                  = UnitClass
local UnitRace                   = UnitRace
local UnitLevel                  = UnitLevel
local GetGuildInfo               = GetGuildInfo
local GetSpecialization          = GetSpecialization
local GetSpecializationInfo      = GetSpecializationInfo
local GetAverageItemLevel        = GetAverageItemLevel
local UnitGUID                   = UnitGUID
local UnitExists                 = UnitExists
local UnitIsPlayer               = UnitIsPlayer
local C_Timer                    = C_Timer
local GetProfessions             = GetProfessions
local GetProfessionInfo          = GetProfessionInfo
local C_TradeSkillUI             = C_TradeSkillUI
local C_ClassTalents             = C_ClassTalents
local C_Traits                   = C_Traits
local GameFontNormalSmallOutline = GameFontNormalSmallOutline
local RAID_CLASS_COLORS          = RAID_CLASS_COLORS
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

---@class GMSTickerHandle
---@field Cancel fun(self: GMSTickerHandle)

-- DB for character-specific options (migrated to new API)
CHARINFO._options = CHARINFO._options or nil

local OPTIONS_DEFAULTS = {
	autoLog = true, -- Auto-log character on login
	lastUpdate = 0,
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
	if ui and type(ui.Open) == "function" then
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

local function GetProfessionsSummary()
	local parts = {}
	if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
		local p1, p2, arch, fish, cook = GetProfessions()
		local indices = { p1, p2, cook, fish, arch }
		for i = 1, #indices do
			local idx = indices[i]
			if idx then
				local name, _, skillLevel, maxSkillLevel = GetProfessionInfo(idx)
				if name and name ~= "" then
					local cur = tonumber(skillLevel) or 0
					local maxv = tonumber(maxSkillLevel) or 0
					parts[#parts + 1] = string.format("%s (%d/%d)", tostring(name), cur, maxv)
				end
			end
		end
	end

	if #parts == 0
		and type(C_TradeSkillUI) == "table"
		and type(C_TradeSkillUI.GetAllProfessionTradeSkillLines) == "function"
		and type(C_TradeSkillUI.GetProfessionInfoBySkillLineID) == "function" then
		local lines = C_TradeSkillUI.GetAllProfessionTradeSkillLines()
		if type(lines) == "table" then
			for i = 1, #lines do
				local lineID = lines[i]
				local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(lineID)
				if type(info) == "table" then
					local name = tostring(info.professionName or "")
					local cur = tonumber(info.skillLevel) or 0
					local maxv = tonumber(info.maxSkillLevel) or 0
					if name ~= "" then
						parts[#parts + 1] = string.format("%s (%d/%d)", name, cur, maxv)
					end
				end
			end
		end
	end

	if #parts <= 0 then return "-" end
	return table.concat(parts, ", ")
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

local function BuildCharData(player, ctxGuid)
	local data = {
		isContext = false,
		gmsVersion = tostring((GMS and GMS.VERSION) or "-"),
		mythicPlus = "-",
		raidStatus = "-",
		equipment = "-",
		equipmentItemLevel = nil,
		equipmentSlots = 0,
		talents = "-",
		professions = "-",
	}

	local playerGuid = tostring((player and player.guid) or "")
	local targetGuid = tostring(ctxGuid or "")
	if targetGuid == "" or targetGuid == playerGuid then
		local equip = GMS and GMS:GetModule("Equipment", true)
		local eqSnapshot = equip and equip._options and equip._options.equipment and equip._options.equipment.snapshot or nil
		local ilvl, slots = BuildItemLevelFromEquipmentSnapshot(eqSnapshot)
		if not ilvl and type(GetAverageItemLevel) == "function" then
			local _, equipped = GetAverageItemLevel()
			ilvl = tonumber(equipped)
		end
		data.equipmentItemLevel = ilvl
		data.equipmentSlots = tonumber(slots) or 0
		if ilvl and ilvl > 0 then
			data.equipment = string.format("%.1f (%d slots)", ilvl, data.equipmentSlots)
		end

		local mythic = GMS and GMS:GetModule("MythicPlus", true)
		local score = mythic and mythic._options and tonumber(mythic._options.score) or nil
		if score and score >= 0 then
			data.mythicPlus = tostring(score)
		end

		local raids = GMS and (GMS:GetModule("RAIDS", true) or GMS:GetModule("Raids", true))
		local raidStore = raids and raids._options and raids._options.raids or nil
		data.raidStatus = BuildRaidStatusFromRaidsStore(raidStore)

		local loadout = GetTalentLoadoutName()
		local specText = tostring((player and player.spec) or "-")
		if loadout ~= "-" and specText ~= "-" then
			data.talents = specText .. " | " .. loadout
		else
			data.talents = (loadout ~= "-" and loadout) or specText
		end
		data.professions = GetProfessionsSummary()
		return data
	end

	data.isContext = true
	data.talents = "-"
	data.professions = "-"

	local recMeta = GetLatestDomainRecordForGuid("roster_meta", targetGuid)
	if recMeta and type(recMeta.payload) == "table" then
		local p = recMeta.payload
		local v = tostring(p.version or "")
		if v ~= "" then data.gmsVersion = v end
		local ilvl = tonumber(p.ilvl)
		if ilvl and ilvl > 0 then
			data.equipmentItemLevel = ilvl
			data.equipment = string.format("%.1f", ilvl)
		end
		local mplus = tonumber(p.mplus)
		if mplus and mplus >= 0 then
			data.mythicPlus = tostring(mplus)
		end
		local raid = tostring(p.raid or "")
		if raid ~= "" then data.raidStatus = raid end
	end

	local recEquip = GetLatestDomainRecordForGuid("EQUIPMENT_V1", targetGuid)
	if recEquip and type(recEquip.payload) == "table" then
		local ilvl, slots = BuildItemLevelFromEquipmentSnapshot(recEquip.payload.snapshot)
		if ilvl and ilvl > 0 then
			data.equipmentItemLevel = ilvl
			data.equipmentSlots = tonumber(slots) or 0
			data.equipment = string.format("%.1f (%d slots)", ilvl, data.equipmentSlots)
		end
	end

	local recM = GetLatestDomainRecordForGuid("MYTHICPLUS_V1", targetGuid)
	if recM and type(recM.payload) == "table" then
		local mplus = tonumber(recM.payload.score)
		if mplus and mplus >= 0 then
			data.mythicPlus = tostring(mplus)
		end
	end

	local recR = GetLatestDomainRecordForGuid("RAIDS_V1", targetGuid)
	if recR and type(recR.payload) == "table" then
		local raid = BuildRaidStatusFromRaidsStore(recR.payload.raids)
		if raid ~= "" and raid ~= "-" then
			data.raidStatus = raid
		end
	end

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
		local ctx = GetNavContext(true) or nil
		local player = GetPlayerSnapshot()

		local ctxName = ctx and ctx.name_full or nil
		local ctxGuid = ctx and ctx.guid or nil
		local ctxFrom = ctx and (ctx.from or ctx.source) or nil

		if ui2 and type(ui2.Header_BuildIconText) == "function" then
			ui2:Header_BuildIconText({
				icon = ICON,
				text = "|cff03A9F4" .. METADATA.DISPLAY_NAME .. "|r",
				subtext = ctxName and ("Context: |cffCCCCCC" .. tostring(ctxName) .. "|r") or "Context: -",
			})
		end
		if ui2 and type(ui2.SetStatusText) == "function" then
			ui2:SetStatusText(ctxName and "CHARINFO: context active" or "CHARINFO: player only")
		end

		if isCached and root and type(root.ReleaseChildren) == "function" then
			root:ReleaseChildren()
		end

		local details = BuildCharData(player, ctxGuid)

		local wrapper = AceGUI:Create("SimpleGroup")
		wrapper:SetFullWidth(true)
		wrapper:SetFullHeight(true)
		wrapper:SetLayout("List")
		root:AddChild(wrapper)

		local profile = AceGUI:Create("InlineGroup")
		profile:SetTitle("")
		profile:SetFullWidth(true)
		profile:SetLayout("Flow")
		wrapper:AddChild(profile)

		local portrait = AceGUI:Create("Icon")
		portrait:SetImage(ICON)
		portrait:SetImageSize(36, 36)
		portrait:SetWidth(44)
		profile:AddChild(portrait)

		local identity = AceGUI:Create("SimpleGroup")
		identity:SetLayout("List")
		identity:SetWidth(420)
		profile:AddChild(identity)

		local classHex = GetClassHex(player.classFile or "")
		local title = AceGUI:Create("Label")
		title:SetFullWidth(true)
		title:SetText(string.format("|cff%s%s|r", classHex, tostring(player.name or "-")))
		identity:AddChild(title)

		AddMutedLine(identity, string.format(
			"Level %s   %s   %s   %s",
			tostring(player.level or "-"),
			tostring(player.race or "-"),
			tostring(player.class or "-"),
			tostring(player.spec or "-")
		))

		AddMutedLine(identity, string.format(
			"%s",
			tostring(player.guild or "-")
		))

		local contextSummary = AceGUI:Create("SimpleGroup")
		contextSummary:SetLayout("List")
		contextSummary:SetWidth(260)
		profile:AddChild(contextSummary)
		AddMutedLine(contextSummary, "Context")
		AddValueLine(contextSummary, "Name", ctxName or "-")
		AddValueLine(contextSummary, "Source", ctxFrom or "-")

		local contentRow = AceGUI:Create("SimpleGroup")
		contentRow:SetFullWidth(true)
		contentRow:SetLayout("Flow")
		wrapper:AddChild(contentRow)

		local leftCol = AceGUI:Create("SimpleGroup")
		leftCol:SetLayout("List")
		leftCol:SetWidth(520)
		contentRow:AddChild(leftCol)

		local rightCol = AceGUI:Create("SimpleGroup")
		rightCol:SetLayout("List")
		rightCol:SetWidth(520)
		contentRow:AddChild(rightCol)

		local cardOverview = AceGUI:Create("InlineGroup")
		cardOverview:SetTitle("")
		cardOverview:SetFullWidth(true)
		cardOverview:SetLayout("List")
		leftCol:AddChild(cardOverview)
		AddCardTitle(cardOverview, "Character")
		AddValueLine(cardOverview, "Full Name", player.name_full or "-")
		AddValueLine(cardOverview, "Class", player.class or "-")
		AddValueLine(cardOverview, "Spec", player.spec or "-")
		AddValueLine(cardOverview, "Itemlevel", string.format("%s (overall %s)", tostring(player.ilvl or "-"), tostring(player.ilvl_overall or "-")))
		AddValueLine(cardOverview, "Mythic Plus", details.mythicPlus or "-")
		AddValueLine(cardOverview, "Raidstatus", details.raidStatus or "-")
		AddValueLine(cardOverview, "Equipment", details.equipment or "-")
		AddValueLine(cardOverview, "Talents", details.talents or "-")
		AddValueLine(cardOverview, "Professions", details.professions or "-")
		AddValueLine(cardOverview, "GUID", player.guid or "-")

		local cardContext = AceGUI:Create("InlineGroup")
		cardContext:SetTitle("")
		cardContext:SetFullWidth(true)
		cardContext:SetLayout("List")
		leftCol:AddChild(cardContext)
		AddCardTitle(cardContext, "Context")
		AddValueLine(cardContext, "Name", ctxName or "-")
		AddValueLine(cardContext, "GUID", ctxGuid or "-")
		AddValueLine(cardContext, "Source", ctxFrom or "-")
		AddValueLine(cardContext, "GMS Version", details.gmsVersion or "-")
		AddValueLine(cardContext, "Context Data", details.isContext and "synced guild records" or "local player")

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
		rightCol:AddChild(btnSelf)

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
		rightCol:AddChild(btnTarget)

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
		rightCol:AddChild(btnClear)

		local btnRefresh = AceGUI:Create("Button")
		btnRefresh:SetText("Refresh")
		btnRefresh:SetWidth(150)
		btnRefresh:SetCallback("OnClick", function()
			OpenSelf()
		end)
		rightCol:AddChild(btnRefresh)

		local opts = (type(CHARINFO._options) == "table") and CHARINFO._options or nil
		local lastUpdate = (opts and tonumber(opts.lastUpdate)) or 0
		local cardMeta = AceGUI:Create("InlineGroup")
		cardMeta:SetTitle("")
		cardMeta:SetFullWidth(true)
		cardMeta:SetLayout("List")
		rightCol:AddChild(cardMeta)
		AddCardTitle(cardMeta, "Meta")
		AddValueLine(cardMeta, "Last Update", (lastUpdate > 0 and tostring(lastUpdate) or "-"))
		AddValueLine(cardMeta, "Module Version", METADATA.VERSION)
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
	if self._ticker then
		local ticker = self._ticker
		---@cast ticker GMSTickerHandle
		pcall(function() ticker:Cancel() end)
	end
	self._ticker = nil
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end

