-- ============================================================================
--	GMS/Core/Permissions.lua
--	Permissions EXTENSION
--	- Handles Group-based Permissions (Admin, Officer, User)
--	- Authority-System: Only Guild Leader can update permissions
--	- Assignments: GUID-based (high priority) or Rank-based
-- ============================================================================

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "PERMISSIONS",
	SHORT_NAME   = "Permissions",
	DISPLAY_NAME = "Berechtigungen",
	VERSION      = "1.1.4",
}

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G                      = _G
local GetTime                 = GetTime
local UnitGUID                = UnitGUID
local IsInGuild               = IsInGuild
local IsGuildLeader           = IsGuildLeader
local GetGuildInfo            = GetGuildInfo
local C_Timer                 = C_Timer
local C_GuildInfo             = C_GuildInfo
local GetNumGuildRanks        = GetNumGuildRanks
local GetGuildRankName        = GetGuildRankName
local GuildRoster             = GuildRoster
local GuildControlGetNumRanks = GuildControlGetNumRanks
local GuildControlGetRankName = GuildControlGetRankName
local GetNumGuildMembers      = GetNumGuildMembers
local GetGuildRosterInfo      = GetGuildRosterInfo
local RAID_CLASS_COLORS       = RAID_CLASS_COLORS
local HIGHLIGHT_FONT_COLOR    = HIGHLIGHT_FONT_COLOR
---@diagnostic enable: undefined-global

local AceGUI = LibStub("AceGUI-3.0", true)

-- ---------------------------------------------------------------------------
--	Guards
-- ---------------------------------------------------------------------------

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
local GMS = AceAddon and AceAddon:GetAddon("GMS", true) or nil
if not GMS then return end

-- ###########################################################################
-- #	LOG BUFFER + LOCAL LOGGER
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return GetTime and GetTime() or nil
end

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time   = now(),
		level  = tostring(level or "INFO"),
		type   = METADATA.TYPE,
		source = METADATA.SHORT_NAME,
		msg    = tostring(msg or ""),
	}

	local n = select("#", ...)
	if n > 0 then
		entry.data = { ... }
	end

	local buffer = GMS._LOG_BUFFER
	local idx = #buffer + 1
	buffer[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		pcall(GMS._LOG_NOTIFY, entry, idx)
	end
end

-- ###########################################################################
-- #	INTERNAL STATE
-- ###########################################################################

GMS.Permissions = GMS.Permissions or {}
local Permissions = GMS.Permissions

Permissions.GROUPS = {
	ADMIN    = "ADMIN",
	EVERYONE = "EVERYONE",
}

local DEFAULTS = {
	profile = {
		groupNames = {
			ADMIN    = "Administrator",
			EVERYONE = "Everyone",
		},
		-- Ordered list of group IDs
		groupsOrder = { "ADMIN", "OFFICER", "EVERYONE" },
		-- Custom groups: [id] = { name = string, isFixed = bool }
		customGroups = {},
		-- GUID-based assignments: [GUID] = { [groupID] = true }
		userAssignments = {},
		-- Rank-based assignments: [rankIndex] = { [groupID] = true }
		rankAssignments = {},
		-- Version of the permission config (for sync)
		configVersion = 0,
		configTimestamp = 0,
	},
}

-- ###########################################################################
-- #	LOGIC
-- ###########################################################################

function Permissions:Initialize()
	if GMS and type(GMS.RegisterModuleOptions) == "function" then
		GMS:RegisterModuleOptions(METADATA.INTERN_NAME, DEFAULTS, "PROFILE")
	end

	self.db = GMS:GetModuleOptions(METADATA.INTERN_NAME)

	-- Migration / Initialization
	self.db.groupNames = self.db.groupNames or {}
	self.db.userAssignments = self.db.userAssignments or {}
	self.db.rankAssignments = self.db.rankAssignments or {}

	if not self.db.groupsOrder then
		self.db.groupsOrder = { "ADMIN", "OFFICER", "EVERYONE" }
	end

	-- Migration: JEDER/USER -> EVERYONE
	if not self.db.groupNames.EVERYONE then
		self.db.groupNames.EVERYONE = self.db.groupNames.JEDER or self.db.groupNames.USER or "Everyone"
		self.db.groupNames.JEDER = nil
		self.db.groupNames.USER = nil
	end

	-- Ensure groupOrder points to EVERYONE not JEDER
	for i, id in ipairs(self.db.groupsOrder) do
		if id == "JEDER" or id == "USER" then
			self.db.groupsOrder[i] = "EVERYONE"
		end
	end

	-- Ensure assignments are tables (Multi-Group Support)
	for guid, val in pairs(self.db.userAssignments) do
		if type(val) == "string" then
			local old = val
			if old == "USER" or old == "JEDER" then old = "EVERYONE" end
			self.db.userAssignments[guid] = { [old] = true }
		end
	end
	for rank, val in pairs(self.db.rankAssignments) do
		if type(val) == "string" then
			local old = val
			if old == "USER" or old == "JEDER" then old = "EVERYONE" end
			self.db.rankAssignments[rank] = { [old] = true }
		end
	end

	self:AutoAssignGM()
	LOCAL_LOG("INFO", "Permissions initialized")

	-- Event Frame for Roster Updates
	if not self._eventFrame then
		self._eventFrame = CreateFrame("Frame")
		self._eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
		self._eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
		self._eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		self._eventFrame:SetScript("OnEvent", function(f, event)
			-- Always check GM status on guild events
			self:AutoAssignGM()

			-- If UI is open on our page, refresh it
			if GMS.UI and GMS.UI._page == "PERMISSIONS" and self._container then
				self:BuildUI(self._container)
			end
		end)
	end

	-- Request Roster Info once
	if IsInGuild() then
		LOCAL_LOG("DEBUG", "Initial GuildRoster request")
		if C_GuildInfo and C_GuildInfo.GuildRoster then
			C_GuildInfo.GuildRoster()
		else
			GuildRoster()
		end
	end

	self:StartIntegrationTicker()
end

-- ###########################################################################
-- #	UI INTEGRATION
-- ###########################################################################

function Permissions:TryRegisterUI()
	if not GMS.UI or type(GMS.UI.RegisterPage) ~= "function" or type(GMS.UI.AddRightDockIconTop) ~= "function" then
		return false
	end

	-- 1. Register Page
	GMS.UI:RegisterPage("PERMISSIONS", 100, METADATA.DISPLAY_NAME, function(...) self:BuildUI(...) end)

	-- 2. Register Dock Icon
	GMS.UI:AddRightDockIconTop({
		id           = "PERMISSIONS",
		order        = 90, -- Kurz vor Settings
		selectable   = true,
		icon         = "Interface\\Icons\\INV_Misc_Key_04",
		tooltipTitle = METADATA.DISPLAY_NAME,
		tooltipText  = "Verwalte Gruppen und Berechtigungen",
		onClick      = function()
			if GMS.UI and type(GMS.UI.Navigate) == "function" then
				GMS.UI:Navigate("PERMISSIONS")
			end
		end,
	})
	return true
end

function Permissions:StartIntegrationTicker()
	if self._integrated then return end
	if self._ticker then return end

	local tries = 0
	self._ticker = C_Timer.NewTicker(0.5, function()
		tries = tries + 1
		local ok = self:TryRegisterUI()
		if ok or tries >= 20 then
			self._integrated = ok
			if self._ticker then self._ticker:Cancel() end
			self._ticker = nil
		end
	end)
end

-- ###########################################################################
-- #	UI BUILDER
-- ###########################################################################

function Permissions:BuildUI(container)
	if not container then return end
	self._container = container

	-- DB Guard
	if not self.db then return end
	container:ReleaseChildren()

	if not self:IsAuthorized() then
		local label = AceGUI:Create("Label")
		label:SetText("|cffff0000Nur der Gildenleiter kann Berechtigungen verwalten.|r")
		label:SetFullWidth(true)
		container:AddChild(label)
		return
	end

	-- Create TreeGroup
	local tree = AceGUI:Create("TreeGroup")
	tree:SetFullWidth(true)
	tree:SetFullHeight(true)
	tree:SetLayout("Fill")
	container:AddChild(tree)

	-- Build Tree Data
	local treeData = {}
	for idx, groupID in ipairs(self.db.groupsOrder) do
		local groupName = self.db.groupNames[groupID] or groupID
		table.insert(treeData, {
			value = groupID,
			text = groupName,
			icon = (groupID == "ADMIN" or groupID == "OFFICER" or groupID == "EVERYONE") and "Interface\\Icons\\INV_Misc_Key_03"
				or "Interface\\Icons\\INV_Misc_Key_04",
		})
	end

	tree:SetTree(treeData)

	-- State for selection
	self._selectedGroup = self._selectedGroup or self.db.groupsOrder[1]
	if not self.db.groupNames[self._selectedGroup] then
		self._selectedGroup = self.db.groupsOrder[1]
	end

	tree:SelectByValue(self._selectedGroup)

	tree:SetCallback("OnGroupSelected", function(_, _, value)
		self._selectedGroup = value
		self:RenderGroupContent(tree, value)
	end)

	-- Initial Render
	self:RenderGroupContent(tree, self._selectedGroup)
end

function Permissions:RenderGroupContent(parent, groupID)
	parent:ReleaseChildren()

	local groupName = self.db.groupNames[groupID] or groupID
	local isFixed = (groupID == "ADMIN" or groupID == "OFFICER" or groupID == "EVERYONE")

	local tabGroup = AceGUI:Create("TabGroup")
	tabGroup:SetFullWidth(true)
	tabGroup:SetFullHeight(true)
	tabGroup:SetLayout("Flow")
	tabGroup:SetTabs({
		{ value = "MEMBERS", text = "Mitglieder" },
		{ value = "RANKS", text = "Ränge & Rollen" },
		{ value = "SETTINGS", text = "Einstellungen" },
	})

	self._selectedTab = self._selectedTab or "MEMBERS"
	tabGroup:SelectTab(self._selectedTab)

	tabGroup:SetCallback("OnGroupSelected", function(_, _, value)
		self._selectedTab = value
		self:RenderTabContent(tabGroup, groupID, value)
	end)

	parent:AddChild(tabGroup)
	self:RenderTabContent(tabGroup, groupID, self._selectedTab)
end

function Permissions:RenderTabContent(parent, groupID, tab)
	parent:ReleaseChildren()

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	parent:AddChild(scroll)

	if tab == "MEMBERS" then
		self:RenderMembersTab(scroll, groupID)
	elseif tab == "RANKS" then
		self:RenderRanksTab(scroll, groupID)
	elseif tab == "SETTINGS" then
		self:RenderSettingsTab(scroll, groupID)
	end

	scroll:DoLayout()
end

function Permissions:RenderMembersTab(container, groupID)
	local header = AceGUI:Create("Heading")
	header:SetText("Mitglieder in " .. (self.db.groupNames[groupID] or groupID))
	header:SetFullWidth(true)
	container:AddChild(header)

	-- Add Member Row
	local addRow = AceGUI:Create("SimpleGroup")
	addRow:SetFullWidth(true)
	addRow:SetLayout("Flow")
	container:AddChild(addRow)

	local addEdit = AceGUI:Create("EditBox")
	addEdit:SetLabel("Spieler hinzufügen (Name oder GUID)")
	addEdit:SetWidth(400)
	addEdit:SetCallback("OnEnterPressed", function(_, _, val)
		local targetGUID = val
		if not val:find("^Player%-") then
			if GMS.Roster and GMS.Roster.GetMemberByName then
				local m = GMS.Roster:GetMemberByName(val)
				targetGUID = m and m.guid or val
			end
		end
		if self:AddMemberToGroup(targetGUID, groupID) then
			self:BuildUI(self._container)
		end
	end)
	addRow:AddChild(addEdit)

	local listGroup = AceGUI:Create("InlineGroup")
	listGroup:SetTitle("Aktuelle Mitglieder")
	listGroup:SetFullWidth(true)
	listGroup:SetLayout("Flow")
	container:AddChild(listGroup)

	local memberCount = 0
	if IsInGuild() then
		local num = GetNumGuildMembers()
		for i = 1, num do
			local name, rankName, rankIndex, level, class, zone, note, officernote, online, status, classFileName, achievementPoints, isMobile, canSoR, reputation, guid = GetGuildRosterInfo(i)
			if guid then
				local pGroups = self:GetPlayerGroups(guid)
				if pGroups[groupID] then
					memberCount = memberCount + 1

					local memRow = AceGUI:Create("SimpleGroup")
					memRow:SetFullWidth(true)
					memRow:SetLayout("Flow")
					listGroup:AddChild(memRow)

					local memLabel = AceGUI:Create("Label")
					local classColor = RAID_CLASS_COLORS[classFileName] or HIGHLIGHT_FONT_COLOR
					local nameText = string.format("|c%s%s|r (|cffaaaaaa%s|r)", classColor.colorStr, name:gsub("%-.*", ""), rankName)
					memLabel:SetText(nameText)
					memLabel:SetWidth(300)
					memRow:AddChild(memLabel)

					local isManual = self.db.userAssignments[guid] and self.db.userAssignments[guid][groupID]
					local isGM = (groupID == "ADMIN" and guid == UnitGUID("player") and IsGuildLeader())

					if isManual and not isGM then
						local delBtn = AceGUI:Create("Button")
						delBtn:SetText("Entfernen")
						delBtn:SetWidth(100)
						delBtn:SetCallback("OnClick", function()
							if self:RemoveMemberFromGroup(guid, groupID) then
								self:BuildUI(self._container)
							end
						end)
						memRow:AddChild(delBtn)
					elseif isGM then
						local gmLabel = AceGUI:Create("Label")
						gmLabel:SetText("|cff00ff00[Gildenleiter]|r")
						gmLabel:SetWidth(100)
						memRow:AddChild(gmLabel)
					end
				end
			end
		end
	end

	if memberCount == 0 then
		local emptyLocal = AceGUI:Create("Label")
		emptyLocal:SetText("|cff888888Keine Mitglieder in dieser Gruppe.|r")
		emptyLocal:SetFullWidth(true)
		listGroup:AddChild(emptyLocal)
	end
end

function Permissions:RenderRanksTab(container, groupID)
	local header = AceGUI:Create("Heading")
	header:SetText("Gildenrang-Zuweisung")
	header:SetFullWidth(true)
	container:AddChild(header)

	local numRanks = 0
	if C_GuildInfo and C_GuildInfo.GetNumRanks then
		numRanks = C_GuildInfo.GetNumRanks()
	elseif GuildControlGetNumRanks then
		numRanks = GuildControlGetNumRanks()
	end

	for i = 1, numRanks do
		local rankName
		if C_GuildInfo and C_GuildInfo.GetRankName then
			rankName = C_GuildInfo.GetRankName(i)
		elseif GuildControlGetRankName then
			rankName = GuildControlGetRankName(i)
		end
		rankName = rankName or ("Rang " .. i)

		local cb = AceGUI:Create("CheckBox")
		cb:SetLabel(rankName)
		cb:SetFullWidth(true)
		cb:SetValue(self.db.rankAssignments[i] and self.db.rankAssignments[i][groupID])
		cb:SetCallback("OnValueChanged", function(_, _, val)
			self.db.rankAssignments[i] = self.db.rankAssignments[i] or {}
			self.db.rankAssignments[i][groupID] = val or nil
			self.db.configVersion = (self.db.configVersion or 0) + 1
			-- We don't need a full rebuild here usually, but for consistency:
			self:BuildUI(self._container)
		end)
		container:AddChild(cb)
	end
end

function Permissions:RenderSettingsTab(container, groupID)
	local isFixed = (groupID == "ADMIN" or groupID == "OFFICER" or groupID == "EVERYONE")

	local header = AceGUI:Create("Heading")
	header:SetText("Gruppeneinstellungen")
	header:SetFullWidth(true)
	container:AddChild(header)

	-- Rename
	local edit = AceGUI:Create("EditBox")
	edit:SetLabel("Gruppenname")
	edit:SetText(self.db.groupNames[groupID] or groupID)
	edit:SetFullWidth(true)
	if isFixed then edit:SetDisabled(true) end
	edit:SetCallback("OnEnterPressed", function(_, _, val)
		self.db.groupNames[groupID] = val
		self:BuildUI(self._container)
	end)
	container:AddChild(edit)

	-- Sort
	local sortGroup = AceGUI:Create("InlineGroup")
	sortGroup:SetTitle("Sortierung")
	sortGroup:SetFullWidth(true)
	sortGroup:SetLayout("Flow")
	container:AddChild(sortGroup)

	local idx
	for i, id in ipairs(self.db.groupsOrder) do
		if id == groupID then idx = i; break end
	end

	local btnUp = AceGUI:Create("Button")
	btnUp:SetText("Nach oben")
	btnUp:SetWidth(150)
	btnUp:SetDisabled(idx == 1)
	btnUp:SetCallback("OnClick", function()
		table.remove(self.db.groupsOrder, idx)
		table.insert(self.db.groupsOrder, idx - 1, groupID)
		self:BuildUI(self._container)
	end)
	sortGroup:AddChild(btnUp)

	local btnDown = AceGUI:Create("Button")
	btnDown:SetText("Nach unten")
	btnDown:SetWidth(150)
	btnDown:SetDisabled(idx == #self.db.groupsOrder)
	btnDown:SetCallback("OnClick", function()
		table.remove(self.db.groupsOrder, idx)
		table.insert(self.db.groupsOrder, idx + 1, groupID)
		self:BuildUI(self._container)
	end)
	sortGroup:AddChild(btnDown)

	-- Delete
	if not isFixed then
		local delBtn = AceGUI:Create("Button")
		delBtn:SetText("Gruppe löschen")
		delBtn:SetFullWidth(true)
		delBtn:SetCallback("OnClick", function()
			self.db.groupNames[groupID] = nil
			for i, id in ipairs(self.db.groupsOrder) do
				if id == groupID then
					table.remove(self.db.groupsOrder, i)
					break
				end
			end
			for guid, grps in pairs(self.db.userAssignments) do grps[groupID] = nil end
			for rid, grps in pairs(self.db.rankAssignments) do grps[groupID] = nil end
			self._selectedGroup = self.db.groupsOrder[1]
			self:BuildUI(self._container)
		end)
		container:AddChild(delBtn)
	end

	-- Add Group Button at the bottom (useful here too)
	local btnAdd = AceGUI:Create("Button")
	btnAdd:SetText("Völlig neue Gruppe erstellen")
	btnAdd:SetFullWidth(true)
	btnAdd:SetCallback("OnClick", function()
		local newID = "CUSTOM_" .. GetTime()
		self.db.groupNames[newID] = "Neue Gruppe"
		table.insert(self.db.groupsOrder, newID)
		self._selectedGroup = newID
		self:BuildUI(self._container)
	end)
	container:AddChild(btnAdd)
end

-- ###########################################################################
-- #	LOGIC HELPERS
-- ###########################################################################

--- Returns true if the current player is authorized to modify permissions
function Permissions:IsAuthorized()
	if not IsInGuild() then return false end

	if IsGuildLeader() then return true end

	-- Fallback to Core module if available
	if GMS.Core and GMS.Core.IsLeader then
		return GMS.Core:IsLeader()
	end

	return false
end

--- Ensures the current GM is in the ADMIN group and cannot be removed
function Permissions:AutoAssignGM()
	if not self:IsAuthorized() then return end

	local guid = UnitGUID("player")
	if not guid then return end

	self.db.userAssignments[guid] = self.db.userAssignments[guid] or {}
	if not self.db.userAssignments[guid].ADMIN then
		self.db.userAssignments[guid].ADMIN = true
		LOCAL_LOG("INFO", "Auto-assigned GM to ADMIN group")
	end
end

--- Returns all groups a player belongs to
-- @param guid string: Player GUID
-- @return table: Set of group IDs [id] = true
function Permissions:GetPlayerGroups(guid)
	local groups = { EVERYONE = true } -- Everyone is in "EVERYONE"

	-- 1. Check if GM (Hardcoded ADMIN)
	if guid == UnitGUID("player") and IsGuildLeader() then
		groups.ADMIN = true
	end

	-- 2. Rank Assignments
	if IsInGuild() then
		local rankIndex
		if guid == UnitGUID("player") then
			_, _, rankIndex = GetGuildInfo("player")
		else
			-- Try to get from Roster
			if GMS.Roster and GMS.Roster.GetMemberByGUID then
				local m = GMS.Roster:GetMemberByGUID(guid)
				rankIndex = m and m.rankIndex
			end
		end

		if rankIndex and self.db.rankAssignments[rankIndex] then
			for gid, active in pairs(self.db.rankAssignments[rankIndex]) do
				if active then groups[gid] = true end
			end
		end
	end

	-- 3. Explicit User Assignments
	if self.db.userAssignments[guid] then
		for gid, active in pairs(self.db.userAssignments[guid]) do
			if active then groups[gid] = true end
		end
	end

	return groups
end

--- Checks if a player has a specific capability
function Permissions:HasCapability(guid, capability)
	local pGroups = self:GetPlayerGroups(guid)

	if pGroups.ADMIN then return true end

	-- Simple logic for now
	if pGroups.OFFICER then
		if capability == "MODIFY_PERMISSIONS" then return false end
		return true
	end

	-- Default / JEDER
	if capability == "SEND_DATA" or capability == "MODIFY_PERMISSIONS" then return false end
	return true
end

-- ###########################################################################
-- #	MANAGEMENT
-- ###########################################################################

function Permissions:AddMemberToGroup(guid, groupID)
	if not self:IsAuthorized() then return false end
	if not groupID then return false end

	self.db.userAssignments[guid] = self.db.userAssignments[guid] or {}
	self.db.userAssignments[guid][groupID] = true

	self.db.configVersion = (self.db.configVersion or 0) + 1
	self.db.configTimestamp = GetTime()

	self:BroadcastConfig()
	LOCAL_LOG("INFO", "Member added to group", guid, groupID)
	return true
end

function Permissions:RemoveMemberFromGroup(guid, groupID)
	if not self:IsAuthorized() then return false end
	if groupID == "ADMIN" and guid == UnitGUID("player") and self:IsAuthorized() then
		return false -- Cannot remove GM from Admin
	end

	if self.db.userAssignments[guid] then
		self.db.userAssignments[guid][groupID] = nil
	end

	self.db.configVersion = (self.db.configVersion or 0) + 1
	self.db.configTimestamp = GetTime()

	self:BroadcastConfig()
	LOCAL_LOG("INFO", "Member removed from group", guid, groupID)
	return true
end

function Permissions:AssignRank(rankIndex, groupID, clearOther)
	if not self:IsAuthorized() then return false end
	rankIndex = tonumber(rankIndex)
	if not rankIndex then return false end

	self.db.rankAssignments[rankIndex] = self.db.rankAssignments[rankIndex] or {}
	if clearOther then wipe(self.db.rankAssignments[rankIndex]) end

	self.db.rankAssignments[rankIndex][groupID] = true

	self.db.configVersion = (self.db.configVersion or 0) + 1
	self.db.configTimestamp = GetTime()

	self:BroadcastConfig()
	LOCAL_LOG("INFO", "Rank assigned to group", rankIndex, groupID)
	return true
end

function Permissions:BroadcastConfig()
	-- Stub
end

-- ###########################################################################
-- #	READY
-- ###########################################################################

Permissions:Initialize()

GMS:RegisterExtension({
	key = METADATA.SHORT_NAME,
	name = METADATA.INTERN_NAME,
	displayName = METADATA.DISPLAY_NAME,
	version = METADATA.VERSION,
})

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)

LOCAL_LOG("INFO", "Permissions extension loaded")
