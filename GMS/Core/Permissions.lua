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
	VERSION      = "1.1.0",
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
	if not self.db.groupsOrder then
		self.db.groupsOrder = { "ADMIN", "OFFICER", "JEDER" }
	end
	if not self.db.groupNames.JEDER then
		self.db.groupNames.JEDER = self.db.groupNames.USER or "Jeder"
		self.db.groupNames.USER = nil
	end

	-- Ensure assignments are tables (Multi-Group Support)
	for guid, val in pairs(self.db.userAssignments) do
		if type(val) == "string" then
			local old = val
			if old == "USER" then old = "JEDER" end
			self.db.userAssignments[guid] = { [old] = true }
		end
	end
	for rank, val in pairs(self.db.rankAssignments) do
		if type(val) == "string" then
			local old = val
			if old == "USER" then old = "JEDER" end
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
		self._eventFrame:SetScript("OnEvent", function()
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

	if not IsGuildLeader() then
		local label = AceGUI:Create("Label")
		label:SetText("|cffff0000Nur der Gildenleiter kann Berechtigungen verwalten.|r")
		label:SetFullWidth(true)
		container:AddChild(label)
		return
	end

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	-- 1. Groups Management
	local header = AceGUI:Create("Heading")
	header:SetText("Gruppenübersicht")
	header:SetFullWidth(true)
	scroll:AddChild(header)

	for idx, groupID in ipairs(self.db.groupsOrder) do
		local isFixed = (groupID == "ADMIN" or groupID == "OFFICER" or groupID == "EVERYONE")
		local groupName = self.db.groupNames[groupID] or groupID

		-- Group Card
		local card = AceGUI:Create("InlineGroup")
		card:SetTitle(groupName .. (isFixed and " (System)" or ""))
		card:SetFullWidth(true)
		card:SetLayout("Flow")
		scroll:AddChild(card)

		-- Actions Row
		local row = AceGUI:Create("SimpleGroup")
		row:SetFullWidth(true)
		row:SetLayout("Flow")
		card:AddChild(row)

		-- Move Up
		local btnUp = AceGUI:Create("Button")
		btnUp:SetText("▲")
		btnUp:SetWidth(40)
		btnUp:SetDisabled(idx == 1)
		btnUp:SetCallback("OnClick", function()
			table.remove(self.db.groupsOrder, idx)
			table.insert(self.db.groupsOrder, idx - 1, groupID)
			self:BuildUI(container)
		end)
		row:AddChild(btnUp)

		-- Move Down
		local btnDown = AceGUI:Create("Button")
		btnDown:SetText("▼")
		btnDown:SetWidth(40)
		btnDown:SetDisabled(idx == #self.db.groupsOrder)
		btnDown:SetCallback("OnClick", function()
			table.remove(self.db.groupsOrder, idx)
			table.insert(self.db.groupsOrder, idx + 1, groupID)
			self:BuildUI(container)
		end)
		row:AddChild(btnDown)

		-- Rename (only if not fixed)
		if not isFixed then
			local edit = AceGUI:Create("EditBox")
			edit:SetLabel("Name ändern")
			edit:SetText(groupName)
			edit:SetWidth(150)
			edit:SetCallback("OnEnterPressed", function(_, _, val)
				self.db.groupNames[groupID] = val
				self:BuildUI(container)
			end)
			row:AddChild(edit)

			local btnDel = AceGUI:Create("Button")
			btnDel:SetText("Löschen")
			btnDel:SetWidth(100)
			btnDel:SetCallback("OnClick", function()
				self.db.groupNames[groupID] = nil
				for i, id in ipairs(self.db.groupsOrder) do
					if id == groupID then
						table.remove(self.db.groupsOrder, i)
						break
					end
				end
				-- Remove from all assignments
				for guid, grps in pairs(self.db.userAssignments) do grps[groupID] = nil end
				for rid, grps in pairs(self.db.rankAssignments) do grps[groupID] = nil end
				self:BuildUI(container)
			end)
			row:AddChild(btnDel)
		end

		-- Members Tooltip / Info (Placeholder for now)
		local lbl = AceGUI:Create("Label")
		lbl:SetText("Mitglieder: (Listenansicht folgt)")
		lbl:SetFullWidth(true)
		card:AddChild(lbl)
	end

	-- Add Group Button
	local btnAdd = AceGUI:Create("Button")
	btnAdd:SetText("Neue Gruppe hinzufügen")
	btnAdd:SetFullWidth(true)
	btnAdd:SetCallback("OnClick", function()
		local newID = "CUSTOM_" .. GetTime()
		self.db.groupNames[newID] = "Neue Gruppe"
		table.insert(self.db.groupsOrder, newID)
		self:BuildUI(container)
	end)
	scroll:AddChild(btnAdd)

	scroll:DoLayout()
	container:DoLayout()
end

-- ###########################################################################
-- #	LOGIC HELPERS
-- ###########################################################################

--- Ensures the current GM is in the ADMIN group and cannot be removed
function Permissions:AutoAssignGM()
	if not IsInGuild() or not IsGuildLeader() then return end
	local guid = UnitGUID("player")
	if not guid then return end

	self.db.userAssignments[guid] = self.db.userAssignments[guid] or {}
	self.db.userAssignments[guid].ADMIN = true
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
	if not IsGuildLeader() then return false end
	if not groupID then return false end

	self.db.userAssignments[guid] = self.db.userAssignments[guid] or {}
	self.db.userAssignments[guid][groupID] = true

	self.db.configVersion = (self.db.configVersion or 0) + 1
	self.db.configTimestamp = GetTime()

	self:BroadcastConfig()
	return true
end

function Permissions:RemoveMemberFromGroup(guid, groupID)
	if not IsGuildLeader() then return false end
	if groupID == "ADMIN" and guid == UnitGUID("player") and IsGuildLeader() then
		return false -- Cannot remove GM from Admin
	end

	if self.db.userAssignments[guid] then
		self.db.userAssignments[guid][groupID] = nil
	end

	self.db.configVersion = (self.db.configVersion or 0) + 1
	self.db.configTimestamp = GetTime()

	self:BroadcastConfig()
	return true
end

function Permissions:AssignRank(rankIndex, groupID, clearOther)
	if not IsGuildLeader() then return false end
	rankIndex = tonumber(rankIndex)
	if not rankIndex then return false end

	self.db.rankAssignments[rankIndex] = self.db.rankAssignments[rankIndex] or {}
	if clearOther then wipe(self.db.rankAssignments[rankIndex]) end

	self.db.rankAssignments[rankIndex][groupID] = true

	self.db.configVersion = (self.db.configVersion or 0) + 1
	self.db.configTimestamp = GetTime()

	self:BroadcastConfig()
	return true
end

function Permissions:BroadcastConfig()
	-- Stub
end

-- ###########################################################################
-- #	SYNC (Stub - Integrated with Comm later)
-- ###########################################################################

function Permissions:BroadcastConfig()
	-- Will be implemented once Comm.lua is ready
	LOCAL_LOG("DEBUG", "BroadcastConfig requested (waiting for Comm)")
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
