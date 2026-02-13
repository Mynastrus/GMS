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
	VERSION      = "1.0.0",
}

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G            = _G
local GetTime       = GetTime
local UnitGUID      = UnitGUID
local IsInGuild     = IsInGuild
local IsGuildLeader = IsGuildLeader
local GetGuildInfo  = GetGuildInfo
local C_Timer       = C_Timer
---@diagnostic enable: undefined-global

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
	ADMIN   = "ADMIN",
	OFFICER = "OFFICER",
	USER    = "USER",
}

local DEFAULTS = {
	profile = {
		groupNames = {
			ADMIN   = "Administrator",
			OFFICER = "Offizier",
			USER    = "Benutzer",
		},
		-- GUID-based assignments: [GUID] = groupKey
		userAssignments = {},
		-- Rank-based assignments: [rankIndex] = groupKey
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
	LOCAL_LOG("INFO", "Permissions initialized")

	if GMS.UI and type(GMS.UI.RegisterPage) == "function" then
		GMS.UI:RegisterPage("PERMISSIONS", 100, METADATA.DISPLAY_NAME, function(...) self:BuildUI(...) end)
	end
end

-- ###########################################################################
-- #	UI BUILDER
-- ###########################################################################

function Permissions:BuildUI(container)
	if not container then return end
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

	-- 1. Group Names Header
	local headerGroups = AceGUI:Create("Heading")
	headerGroups:SetText("Gruppennamen")
	headerGroups:SetFullWidth(true)
	scroll:AddChild(headerGroups)

	for key, internal in pairs(self.GROUPS) do
		local edit = AceGUI:Create("EditBox")
		edit:SetLabel("Gruppe: " .. internal)
		edit:SetText(self.db.groupNames[internal] or internal)
		edit:SetCallback("OnEnterPressed", function(_, _, val)
			self.db.groupNames[internal] = val
			LOCAL_LOG("INFO", "Group name changed", internal, val)
		end)
		scroll:AddChild(edit)
	end

	-- 2. Rank Assignments
	local headerRanks = AceGUI:Create("Heading")
	headerRanks:SetText("Gildenränge")
	headerRanks:SetFullWidth(true)
	scroll:AddChild(headerRanks)

	local numRanks = (C_GuildInfo and C_GuildInfo.GetNumGuildRanks) and C_GuildInfo.GetNumGuildRanks() or 0
	for i = 1, numRanks do
		local rankName = (C_GuildInfo and C_GuildInfo.GetGuildRankName) and C_GuildInfo.GetGuildRankName(i) or ("Rang " .. i)
		local dropdown = AceGUI:Create("Dropdown")
		dropdown:SetLabel(rankName)
		dropdown:SetList({
			ADMIN   = self.db.groupNames.ADMIN,
			OFFICER = self.db.groupNames.OFFICER,
			USER    = self.db.groupNames.USER,
		})
		dropdown:SetValue(self.db.rankAssignments[i] or "USER")
		dropdown:SetCallback("OnValueChanged", function(_, _, val)
			self:AssignRank(i, val)
		end)
		scroll:AddChild(dropdown)
	end

	-- 3. Player Assignments (Stub for now)
	local headerPlayers = AceGUI:Create("Heading")
	headerPlayers:SetText("Einzelne Spieler (GUID)")
	headerPlayers:SetFullWidth(true)
	scroll:AddChild(headerPlayers)

	local listLabel = AceGUI:Create("Label")
	listLabel:SetText("In dieser Version können Spieler noch nicht manuell via UI hinzugefügt werden (Coming soon).")
	listLabel:SetFullWidth(true)
	scroll:AddChild(listLabel)
end

--- Returns the effective group of a player
-- @param guid string: Player GUID
-- @return string: Group key (ADMIN, OFFICER, USER)
function Permissions:GetPlayerGroup(guid)
	if not guid or guid == "" then return self.GROUPS.USER end

	-- 1. Check if GM (Always Admin)
	if guid == UnitGUID("player") and IsGuildLeader() then
		return self.GROUPS.ADMIN
	end

	-- 2. Check manual GUID assignment
	local db = self.db
	if db and db.userAssignments and db.userAssignments[guid] then
		return db.userAssignments[guid]
	end

	-- 3. Check Rank assignment
	if IsInGuild() then
		-- This requires guild roster info; if not available, we can only check ourselves accurately
		local playerGUID = UnitGUID("player")
		if guid == playerGUID then
			local _, _, rankIndex = GetGuildInfo("player")
			if rankIndex and db and db.rankAssignments and db.rankAssignments[rankIndex] then
				return db.rankAssignments[rankIndex]
			end
		else
			-- For other players, we would need to look them up in the roster cache
			-- We will integrate this with the Roster module later
			if GMS.Roster and type(GMS.Roster.GetMemberByGUID) == "function" then
				local member = GMS.Roster:GetMemberByGUID(guid)
				if member and member.rankIndex and db and db.rankAssignments and db.rankAssignments[member.rankIndex] then
					return db.rankAssignments[member.rankIndex]
				end
			end
		end
	end

	return self.GROUPS.USER
end

--- Checks if a player has a specific capability
function Permissions:HasCapability(guid, capability)
	local group = self:GetPlayerGroup(guid)

	-- Basic Capability-Map (hardcoded for now, can be expanded)
	if group == self.GROUPS.ADMIN then
		return true -- Admins can do everything
	elseif group == self.GROUPS.OFFICER then
		-- Officers can send data and view logs, but not change permissions
		if capability == "MODIFY_PERMISSIONS" then return false end
		return true
	elseif group == self.GROUPS.USER then
		-- Users can only receive data and view their own info
		if capability == "SEND_DATA" or capability == "MODIFY_PERMISSIONS" then return false end
		return true
	end

	return false
end

-- ###########################################################################
-- #	MANAGEMENT (Admin only)
-- ###########################################################################

function Permissions:AssignPlayer(guid, groupKey)
	if not IsGuildLeader() then return false end
	if not self.GROUPS[groupKey] then return false end

	self.db.userAssignments[guid] = groupKey
	self.db.configVersion = self.db.configVersion + 1
	self.db.configTimestamp = GetTime()

	LOCAL_LOG("INFO", "Assigned player to group", guid, groupKey)
	self:BroadcastConfig()
	return true
end

function Permissions:AssignRank(rankIndex, groupKey)
	if not IsGuildLeader() then return false end
	if not self.GROUPS[groupKey] then return false end

	self.db.rankAssignments[tonumber(rankIndex)] = groupKey
	self.db.configVersion = self.db.configVersion + 1
	self.db.configTimestamp = GetTime()

	LOCAL_LOG("INFO", "Assigned rank to group", rankIndex, groupKey)
	self:BroadcastConfig()
	return true
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
