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
	VERSION      = "1.3.6",
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

Permissions.CAPABILITIES = {
	{ id = "MODIFY_PERMISSIONS", name = "Berechtigungen verwalten",
		desc = "Ermöglicht das Erstellen, Umbenennen und Löschen von Gruppen sowie das Ändern von Berechtigungen." },
	{ id = "SEND_DATA", name = "Daten senden",
		desc = "Erlaubt das Senden von Addon-Daten (z.B. Roster-Synchronisation, Raids) an andere Gildenmitglieder." },
	{ id = "RECEIVE_DATA", name = "Daten empfangen",
		desc = "Erlaubt den Empfang und die Verarbeitung von Addon-Daten anderer Mitglieder." },
	{ id = "EDIT_ROSTER", name = "Roster bearbeiten",
		desc = "Ermöglicht das Bearbeiten von Notizen und Rängen innerhalb des GMS Roster-Moduls." },
	{ id = "MANAGE_RAIDS", name = "Raids verwalten",
		desc = "Erlaubt das Erstellen, Starten und Verwalten von Raids und Anmeldungen." },
	{ id = "VIEW_LOGS", name = "Logs einsehen", desc = "Gewährt Zugriff auf detaillierte Addon-Logs und Historien." },
}

local DEFAULTS = {
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
	-- Group permissions: [groupID] = { [capability] = true }
	groupPermissions = {},
	-- Version of the permission config (for sync)
	configVersion = 0,
	configTimestamp = 0,
}

-- ###########################################################################
-- #	LOGIC
-- ###########################################################################

function Permissions:Initialize()
	if GMS and type(GMS.RegisterModuleOptions) == "function" then
		GMS:RegisterModuleOptions(METADATA.INTERN_NAME, DEFAULTS, "PROFILE")
	end

	self.db = GMS:GetModuleOptions(METADATA.INTERN_NAME)

	-- Migration: Fix double-wrapped profile from v1.3.0-1.3.5
	if self.db.profile and type(self.db.profile) == "table" then
		for k, v in pairs(self.db.profile) do
			if self.db[k] == nil then
				self.db[k] = v
			end
		end
		self.db.profile = nil
		LOCAL_LOG("INFO", "Migrated double-wrapped profile data to root")
	end

	-- Migration / Initialization
	self.db.groupNames = self.db.groupNames or {}
	self.db.userAssignments = self.db.userAssignments or {}
	self.db.rankAssignments = self.db.rankAssignments or {}
	self.db.groupPermissions = self.db.groupPermissions or {}

	if not self.db.groupsOrder then
		self.db.groupsOrder = { "ADMIN", "OFFICER", "EVERYONE" }
	end

	-- Migration: Everyone/JEDER/USER -> EVERYONE
	if self.db.groupNames.EVERYONE or self.db.groupNames.Everyone or self.db.groupNames.JEDER or self.db.groupNames.USER then
		self.db.groupNames.EVERYONE = "EVERYONE"
		self.db.groupNames.Everyone = nil
		self.db.groupNames.JEDER = nil
		self.db.groupNames.USER = nil
	end

	-- Cleanup invalid guid assignments (legacy bug where reputation was used as GUID)
	for guid, grps in pairs(self.db.userAssignments) do
		if guid == "1" or guid == "2" or guid == "3" or guid == "4" or guid == "5" or guid == "6" or guid == "7" or guid == "8"
			or not guid:find("^Player%-") then
			self.db.userAssignments[guid] = nil
		end
	end

	-- Ensure groupOrder points to EVERYONE
	for i, id in ipairs(self.db.groupsOrder) do
		if id == "Everyone" or id == "JEDER" or id == "USER" then
			self.db.groupsOrder[i] = "EVERYONE"
		end
	end

	-- Ensure assignments are tables (Multi-Group Support)
	for guid, val in pairs(self.db.userAssignments) do
		if type(val) == "string" then
			local old = val
			if old == "USER" or old == "JEDER" or old == "Everyone" then old = "EVERYONE" end
			self.db.userAssignments[guid] = { [old] = true }
		end
	end

	-- Migration: 1-based ranks to 0-based
	if not self.db._rankMigrationDone then
		local newRanks = {}
		for rank, val in pairs(self.db.rankAssignments) do
			local rIdx = tonumber(rank)
			if rIdx and rIdx > 0 then
				-- We assume old was 1-based (Blizzard UI style)
				newRanks[rIdx - 1] = val
			else
				newRanks[rank] = val
			end
		end
		self.db.rankAssignments = newRanks
		self.db._rankMigrationDone = true
		LOCAL_LOG("INFO", "Migrated rank assignments to 0-based indexing")
	end

	for rank, val in pairs(self.db.rankAssignments) do
		if type(val) == "string" then
			local old = val
			if old == "USER" or old == "JEDER" or old == "Everyone" then old = "EVERYONE" end
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

			-- Refresh UI with throttling
			if GMS.UI and GMS.UI._page == "PERMISSIONS" and self._container then
				if self._refreshTimer then self._refreshTimer:Cancel() end
				self._refreshTimer = C_Timer.NewTimer(2, function()
					self:BuildUI(self._container)
					self._refreshTimer = nil
				end)
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
	-- Validate selection (in case a group was deleted)
	local validSelection = false
	for _, id in ipairs(self.db.groupsOrder) do
		if id == self._selectedGroup then validSelection = true; break end
	end
	if not validSelection then
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
		{ value = "PERMISSIONS", text = "Berechtigungen" },
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
	elseif tab == "PERMISSIONS" then
		self:RenderPermissionsTab(scroll, groupID)
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

	-- Suggestion Container
	local suggestGroup = AceGUI:Create("InlineGroup")
	suggestGroup:SetTitle("Vorschläge")
	suggestGroup:SetFullWidth(true)
	suggestGroup:SetLayout("Flow")
	suggestGroup.frame:Hide() -- Start hidden (Accessing the underlying frame)
	container:AddChild(suggestGroup)

	-- Add Suggestion Logic
	local rosterData = {} -- [name] = { guid, class }
	if IsInGuild() then
		for i = 1, GetNumGuildMembers() do
			local name, _, _, _, _, _, _, _, _, _, _, class, _, _, _, _, guid = GetGuildRosterInfo(i)
			if name and guid then
				rosterData[name] = { guid = guid, class = class }
			end
		end
	end

	local function UpdateSuggestions(val)
		suggestGroup:ReleaseChildren()
		if not val or #val < 2 then
			suggestGroup.frame:Hide()
			container:DoLayout()
			return
		end

		local matches = 0
		for fullPlayerName, data in pairs(rosterData) do
			local shortName = fullPlayerName:gsub("%-.*", "")
			if fullPlayerName:lower():find(val:lower(), 1, true) or shortName:lower():find(val:lower(), 1, true) then
				local btn = AceGUI:Create("Button")
				local color = RAID_CLASS_COLORS[data.class] or HIGHLIGHT_FONT_COLOR
				local display = string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, fullPlayerName)
				btn:SetText(display)
				btn:SetWidth(150)
				btn:SetCallback("OnClick", function()
					if self:AddMemberToGroup(data.guid, groupID) then
						self:BuildUI(self._container)
					end
				end)
				suggestGroup:AddChild(btn)
				matches = matches + 1
				if matches >= 10 then break end
			end
		end

		if matches > 0 then
			suggestGroup.frame:Show()
		else
			suggestGroup.frame:Hide()
		end
		container:DoLayout()
	end

	addEdit:SetCallback("OnTextChanged", function(_, _, val)
		UpdateSuggestions(val)
	end)

	addEdit:SetCallback("OnEnterPressed", function(_, _, val)
		local targetGUID = tostring(val)
		if not targetGUID:find("^Player%-") then
			-- Exact name match in roster
			if rosterData[val] then
				targetGUID = rosterData[val].guid
			else
				-- Case-insensitive check
				for name, data in pairs(rosterData) do
					if name:lower() == val:lower() or name:gsub("%-.*", ""):lower() == val:lower() then
						targetGUID = data.guid
						break
					end
				end
			end
		end

		if targetGUID and type(targetGUID) == "string" and targetGUID:find("^Player%-") then
			if self:AddMemberToGroup(targetGUID, groupID) then
				self:BuildUI(self._container)
			end
		else
			LOCAL_LOG("ERROR", "Could not find member GUID for", val)
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
			local name, rankName, rankIndex, level, class, zone, note, officernote, online, status, classFileName, achievementPoints, achievementRank, isMobile, canSoR, reputation, guid = GetGuildRosterInfo(i)
			if guid and guid:find("^Player%-") then
				local pGroups = self:GetPlayerGroups(guid, rankIndex)
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

	-- Blizzard Ranks are 0-based internally (0 = GM, 1 = Officer, etc.)
	for i = 0, numRanks - 1 do
		local rankName
		if C_GuildInfo and C_GuildInfo.GetRankName then
			rankName = C_GuildInfo.GetRankName(i)
		elseif GuildControlGetRankName then
			rankName = GuildControlGetRankName(i + 1)
		end

		-- Only show active/named ranks
		if rankName and rankName ~= "" then
			local cb = AceGUI:Create("CheckBox")
			cb:SetLabel(rankName)
			cb:SetFullWidth(true)
			cb:SetValue(self.db.rankAssignments[i] and self.db.rankAssignments[i][groupID])
			cb:SetCallback("OnValueChanged", function(_, _, val)
				self.db.rankAssignments[i] = self.db.rankAssignments[i] or {}
				self.db.rankAssignments[i][groupID] = val or nil
				self.db.configVersion = (self.db.configVersion or 0) + 1
				self:BuildUI(self._container)
			end)
			container:AddChild(cb)
		end
	end
end

function Permissions:RenderPermissionsTab(container, groupID)
	local header = AceGUI:Create("Heading")
	header:SetText("Gruppenberechtigungen")
	header:SetFullWidth(true)
	container:AddChild(header)

	local isRootAdmin = (groupID == "ADMIN")

	for _, cap in ipairs(self.CAPABILITIES) do
		local cb = AceGUI:Create("CheckBox")
		cb:SetLabel(cap.name)
		cb:SetDescription("|cff888888ID: " .. cap.id .. "|r")
		cb:SetWidth(200)

		-- Add Tooltip
		cb:SetCallback("OnEnter", function(widget)
			GameTooltip:SetOwner(widget.frame, "ANCHOR_TOPRIGHT")
			GameTooltip:SetText(cap.name, 1, 1, 1)
			GameTooltip:AddLine(cap.desc, nil, nil, nil, true)
			GameTooltip:AddLine(" ", 1, 1, 1)
			GameTooltip:AddLine("|cff888888ID: " .. cap.id .. "|r", 1, 1, 1)
			GameTooltip:Show()
		end)
		cb:SetCallback("OnLeave", function()
			GameTooltip:Hide()
		end)

		-- Root Admin always has all permissions and cannot change them
		if isRootAdmin then
			cb:SetValue(true)
			cb:SetDisabled(true)
		else
			cb:SetValue(self.db.groupPermissions[groupID] and self.db.groupPermissions[groupID][cap.id])
			cb:SetCallback("OnValueChanged", function(_, _, val)
				self.db.groupPermissions[groupID] = self.db.groupPermissions[groupID] or {}
				self.db.groupPermissions[groupID][cap.id] = val or nil
				self.db.configVersion = (self.db.configVersion or 0) + 1
				-- No full rebuild needed for checkboxes usually
			end)
		end
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
	-- Renaming allowed for all now
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

	-- 1. Blizzard API IsGuildLeader
	if IsGuildLeader() then return true end

	-- 2. Rank-based check (Index 0 is always GM)
	local _, _, rankIndex = GetGuildInfo("player")
	if rankIndex == 0 then return true end

	-- 3. Core module fallback
	if GMS.Core and GMS.Core.IsLeader then
		if GMS.Core:IsLeader() then return true end
	end

	-- 4. Name comparison (last resort)
	local leaderName = GetGuildInfo("player")
	local playerName = UnitName("player")
	if leaderName and playerName and leaderName == playerName then
		return true
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
-- @param providedRankIndex number|nil: Optional known rank index (0-based)
-- @return table: Set of group IDs [id] = true
function Permissions:GetPlayerGroups(guid, providedRankIndex)
	local groups = { EVERYONE = true } -- Everyone is in "EVERYONE"

	local playerGUID = UnitGUID("player")
	local isPlayer = (guid == playerGUID)

	-- 1. Identify Rank Index
	local rankIndex = providedRankIndex
	if not rankIndex then
		if isPlayer then
			_, _, rankIndex = GetGuildInfo("player")
		elseif GMS.Roster and GMS.Roster.GetMemberByGUID then
			local m = GMS.Roster:GetMemberByGUID(guid)
			rankIndex = m and m.rankIndex
		end
	end

	-- 2. Check if GM (Hardcoded ADMIN)
	if isPlayer and (IsGuildLeader() or rankIndex == 0) then
		groups.ADMIN = true
	end

	-- 3. Rank Assignments
	if rankIndex and self.db.rankAssignments[rankIndex] then
		for gid, active in pairs(self.db.rankAssignments[rankIndex]) do
			if active then groups[gid] = true end
		end
	end

	-- 4. Explicit User Assignments
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

	-- 1. Admins have everything
	if pGroups.ADMIN then return true end

	-- 2. Check each group for the capability
	for groupID, active in pairs(pGroups) do
		if active and self.db.groupPermissions[groupID] and self.db.groupPermissions[groupID][capability] then
			return true
		end
	end

	-- 3. Hardcoded Fallbacks for basic functionality
	if capability == "SEND_DATA" or capability == "RECEIVE_DATA" then
		return true -- Basic communication is usually allowed for everyone
	end

	return false
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
