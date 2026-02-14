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
	VERSION      = "1.0.0",
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
local C_GuildInfo = C_GuildInfo
local GuildRoster = GuildRoster
local C_Timer = C_Timer
local wipe = wipe
---@diagnostic enable: undefined-global

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

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
GuildLog._snapshot = GuildLog._snapshot or nil
GuildLog._pageRegistered = GuildLog._pageRegistered or false
GuildLog._dockRegistered = GuildLog._dockRegistered or false
GuildLog._scanScheduled = GuildLog._scanScheduled or false
GuildLog._ui = GuildLog._ui or nil
GuildLog._uiRefreshToken = GuildLog._uiRefreshToken or 0

local OPTIONS_DEFAULTS = {
	chatEcho = false,
	maxEntries = 1000,
}

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

local function EnsureOptions()
	if type(GMS.RegisterModuleOptions) == "function" then
		pcall(function()
			GMS:RegisterModuleOptions(MODULE_NAME, OPTIONS_DEFAULTS, "GUILD")
		end)
	end
	if type(GMS.GetModuleOptions) ~= "function" then return nil end
	local ok, opts = pcall(GMS.GetModuleOptions, GMS, MODULE_NAME)
	if not ok or type(opts) ~= "table" then return nil end
	if opts.chatEcho == nil then opts.chatEcho = false end
	opts.maxEntries = ClampMaxEntries(opts.maxEntries)
	if type(opts.entries) ~= "table" then opts.entries = {} end
	if type(opts.memberHistory) ~= "table" then opts.memberHistory = {} end
	GuildLog._options = opts
	return opts
end

local function Entries()
	local opts = GuildLog._options or EnsureOptions()
	if type(opts) ~= "table" then return nil end
	if type(opts.entries) ~= "table" then opts.entries = {} end
	return opts.entries
end

local function MemberHistory()
	local opts = GuildLog._options or EnsureOptions()
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
	local opts = GuildLog._options or EnsureOptions()
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

local function NormalizeName(name)
	local n = tostring(name or "")
	n = n:gsub("^%s+", ""):gsub("%s+$", "")
	return n
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

local function BuildCurrentRosterSnapshot()
	local out = {}
	if not IsInGuild or not IsInGuild() then return out end
	if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
		return out
	end

	local total = tonumber(GetNumGuildMembers()) or 0
	for i = 1, total do
		local name, rank, rankIndex, level, class, zone, note, officerNote, online, status, classFileName, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		if type(guid) == "string" and guid ~= "" then
			out[guid] = {
				guid = guid,
				name = NormalizeName(name),
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

	for guid, newM in pairs(curr) do
		local oldM = prev[guid]
		if not oldM then
			local history, isRejoin = MarkJoin(guid, newM.name, true)
			if isRejoin then
				PushEntry("REJOIN", T("GA_REJOIN", "%s rejoined the guild.", tostring(newM.name or guid)), {
					guid = guid,
					history = history,
				})
			else
				PushEntry("JOIN", T("GA_JOIN", "%s joined the guild.", tostring(newM.name or guid)), {
					guid = guid,
					history = history,
				})
			end
		else
			EnsureHistoryEntry(guid, newM.name)
			if oldM.rankIndex ~= newM.rankIndex then
				if newM.rankIndex < oldM.rankIndex then
					PushEntry("PROMOTE", T("GA_PROMOTE", "%s promoted (%s -> %s).", tostring(newM.name or guid), tostring(oldM.rank or oldM.rankIndex), tostring(newM.rank or newM.rankIndex)))
				else
					PushEntry("DEMOTE", T("GA_DEMOTE", "%s demoted (%s -> %s).", tostring(newM.name or guid), tostring(oldM.rank or oldM.rankIndex), tostring(newM.rank or newM.rankIndex)))
				end
			end
			if oldM.online ~= newM.online then
				if newM.online then
					PushEntry("ONLINE", T("GA_ONLINE", "%s is now online.", tostring(newM.name or guid)))
				else
					PushEntry("OFFLINE", T("GA_OFFLINE", "%s went offline.", tostring(newM.name or guid)))
				end
			end
			if oldM.note ~= newM.note then
				PushEntry("NOTE", T(
					"GA_NOTE_CHANGED_DETAIL",
					"%s updated public note (%s -> %s).",
					tostring(newM.name or guid),
					tostring(oldM.note or "-"),
					tostring(newM.note or "-")
				))
			end
			if oldM.officerNote ~= newM.officerNote then
				PushEntry("OFFICER_NOTE", T(
					"GA_OFFICER_NOTE_CHANGED_DETAIL",
					"%s updated officer note (%s -> %s).",
					tostring(newM.name or guid),
					tostring(oldM.officerNote or "-"),
					tostring(newM.officerNote or "-")
				))
			end
		end
	end

	for guid, oldM in pairs(prev) do
		if not curr[guid] then
			local history = MarkLeave(guid, oldM.name)
			PushEntry("LEAVE", T("GA_LEAVE", "%s left the guild.", tostring(oldM.name or guid)), {
				guid = guid,
				history = history,
			})
		end
	end
end

function GuildLog:ScanGuildChanges()
	local curr = BuildCurrentRosterSnapshot()
	if not self._snapshot then
		self._snapshot = curr
		SeedHistoryFromSnapshot(curr)
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

function GuildLog:ScheduleScan()
	if self._scanScheduled then return end
	self._scanScheduled = true
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		C_Timer.After(0.25, function()
			GuildLog._scanScheduled = false
			GuildLog:ScanGuildChanges()
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

	ui:RegisterPage(MODULE_NAME, 70, T("GA_PAGE_TITLE", "Guild Activity"), function(root, _, isCached)
		if ui and type(ui.Header_BuildIconText) == "function" then
			ui:Header_BuildIconText({
				icon = "Interface\\Icons\\Achievement_Guildperk_EverybodysFriend",
				text = "|cff03A9F4" .. T("GA_HEADER_TITLE", "Guild Activity Log") .. "|r",
				subtext = T("GA_HEADER_SUB", "Tracks guild roster changes in a dedicated module log."),
			})
		end

		if isCached then
			if GuildLog._ui and type(GuildLog._ui.render) == "function" then
				GuildLog._ui.render()
			end
			return
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

		local cbChat = AceGUI:Create("CheckBox")
		cbChat:SetLabel(T("GA_CHAT_ECHO", "Post new entries in chat"))
		cbChat:SetWidth(260)
		cbChat:SetValue((GuildLog._options and GuildLog._options.chatEcho) == true)
		cbChat:SetCallback("OnValueChanged", function(_, _, v)
			local opts = GuildLog._options or EnsureOptions()
			if type(opts) == "table" then
				opts.chatEcho = v and true or false
			end
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
			end
			if GuildLog._ui and type(GuildLog._ui.render) == "function" then
				GuildLog._ui.render()
			end
		end)
		controls:AddChild(btnClear)

		local scroller = AceGUI:Create("ScrollFrame")
		scroller:SetLayout("List")
		scroller:SetFullWidth(true)
		scroller:SetFullHeight(true)
		wrapper:AddChild(scroller)

		local function render()
			local entries = Entries() or {}
			scroller:ReleaseChildren()

			if #entries == 0 then
				local empty = AceGUI:Create("Label")
				empty:SetFullWidth(true)
				empty:SetText("|cff9d9d9d" .. T("GA_EMPTY", "No guild activity entries yet.") .. "|r")
				scroller:AddChild(empty)
				if ui and type(ui.SetStatusText) == "function" then
					ui:SetStatusText(T("GA_STATUS_FMT", "Guild Activity: %d entries", 0))
				end
				return
			end

			for i = #entries, 1, -1 do
				local e = entries[i]
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
			end

			if ui and type(ui.SetStatusText) == "function" then
				ui:SetStatusText(T("GA_STATUS_FMT", "Guild Activity: %d entries", #entries))
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
		alias = { "glog", "activity" },
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
end

function GuildLog:OnEnable()
	self:InitializeOptions()
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

	self:RegisterEvent("GUILD_ROSTER_UPDATE", "ScheduleScan")
	self:RegisterEvent("PLAYER_GUILD_UPDATE", "ScheduleScan")

	self:RequestRosterRefresh()
	self:ScheduleScan()

	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
	LOCAL_LOG("INFO", "GuildLog enabled")
end

function GuildLog:OnDisable()
	self._scanScheduled = false
	self._ui = nil
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end
