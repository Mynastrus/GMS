-- ============================================================================
--	GMS/Modules/GuildInfo.lua
--	GuildInfo MODULE (Ace)
--	- Provides current guild snapshot for other pages (e.g. Dashboard)
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local GetTime          = GetTime
local IsInGuild        = IsInGuild
local GetGuildInfo     = GetGuildInfo
local GetRealmName     = GetRealmName
local UnitFactionGroup = UnitFactionGroup
local C_GuildInfo      = C_GuildInfo
---@diagnostic enable: undefined-global

local METADATA = {
	TYPE         = "MOD",
	INTERN_NAME  = "GuildInfo",
	SHORT_NAME   = "GUILDINFO",
	DISPLAY_NAME = "Guild Info",
	VERSION      = "1.0.0",
}

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return type(GetTime) == "function" and GetTime() or nil
end

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time = now(),
		level = tostring(level or "INFO"),
		type = METADATA.TYPE,
		source = METADATA.SHORT_NAME,
		msg = tostring(msg or ""),
	}

	local n = select("#", ...)
	if n > 0 then
		entry.data = {}
		for i = 1, n do
			entry.data[i] = select(i, ...)
		end
	end

	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry
	if type(GMS._LOG_NOTIFY) == "function" then
		pcall(GMS._LOG_NOTIFY, entry, idx)
	end
end

local MODULE_NAME = "GuildInfo"

local GuildInfo = GMS:GetModule(MODULE_NAME, true)
if not GuildInfo then
	GuildInfo = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
end

if type(GMS.RegisterModule) == "function" then
	GMS:RegisterModule(GuildInfo, METADATA)
end

GuildInfo._snapshot = GuildInfo._snapshot or {
	inGuild = false,
	name = "-",
	realm = "-",
	faction = "-",
	rankName = "-",
	rankIndex = -1,
	memberCount = 0,
	memberOnline = 0,
	motd = "",
	info = "",
	guid = "",
	updatedAt = 0,
}

local function _safeGuildRoster()
	if type(C_GuildInfo) == "table" and type(C_GuildInfo.GuildRoster) == "function" then
		pcall(C_GuildInfo.GuildRoster)
	end
end

local function _readGuildMemberCounts()
	local total = 0
	local online = 0

	if type(C_GuildInfo) == "table" and type(C_GuildInfo.GetNumGuildMembers) == "function" then
		local ok, n = pcall(C_GuildInfo.GetNumGuildMembers)
		if ok and type(n) == "number" and n > 0 then
			total = n
		end
	end

	if total > 0 and type(C_GuildInfo) == "table" then
		local infoFn = C_GuildInfo.GetGuildRosterInfo
		if type(infoFn) == "function" then
			for i = 1, total do
				local ok, info = pcall(infoFn, i)
				if ok and type(info) == "table" and info.online == true then
					online = online + 1
				end
			end
		end
	end

	return total, online
end

function GuildInfo:RefreshSnapshot(reason)
	local snap = self._snapshot or {}
	snap.updatedAt = tonumber(now() or 0) or 0

	if not IsInGuild or not IsInGuild() then
		snap.inGuild = false
		snap.name = "-"
		snap.realm = tostring((GetRealmName and GetRealmName()) or "-")
		snap.faction = tostring((UnitFactionGroup and UnitFactionGroup("player")) or "-")
		snap.rankName = "-"
		snap.rankIndex = -1
		snap.memberCount = 0
		snap.memberOnline = 0
		snap.motd = ""
		snap.info = ""
		snap.guid = ""
		self._snapshot = snap
		return snap
	end

	snap.inGuild = true
	snap.realm = tostring((GetRealmName and GetRealmName()) or "-")
	snap.faction = tostring((UnitFactionGroup and UnitFactionGroup("player")) or "-")

	local guildName, guildRankName, guildRankIndex, guildGUID = nil, nil, nil, nil
	if type(GetGuildInfo) == "function" then
		local n, rName, rIdx, _, _, _, _, _, _, _, _, _, _, _, _, _, g = GetGuildInfo("player")
		guildName = n
		guildRankName = rName
		guildRankIndex = rIdx
		guildGUID = g
	end

	snap.name = tostring(guildName or "-")
	snap.rankName = tostring(guildRankName or "-")
	snap.rankIndex = tonumber(guildRankIndex) or -1
	snap.guid = tostring(guildGUID or "")

	if type(C_GuildInfo) == "table" and type(C_GuildInfo.GetGuildRosterMOTD) == "function" then
		local ok, motd = pcall(C_GuildInfo.GetGuildRosterMOTD)
		if ok and type(motd) == "string" then
			snap.motd = motd
		end
	end

	if type(C_GuildInfo) == "table" and type(C_GuildInfo.GetGuildInfoText) == "function" then
		local ok, infoText = pcall(C_GuildInfo.GetGuildInfoText)
		if ok and type(infoText) == "string" then
			snap.info = infoText
		end
	end

	local total, online = _readGuildMemberCounts()
	snap.memberCount = tonumber(total) or 0
	snap.memberOnline = tonumber(online) or 0

	self._snapshot = snap
	LOCAL_LOG("DEBUG", "GuildInfo refreshed", tostring(reason or "unknown"))
	return snap
end

function GuildInfo:GetSnapshot()
	return self:RefreshSnapshot("get")
end

function GuildInfo:OnEnable()
	self:RegisterEvent("PLAYER_LOGIN", function() self:RefreshSnapshot("PLAYER_LOGIN") end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:RefreshSnapshot("PLAYER_ENTERING_WORLD") end)
	self:RegisterEvent("PLAYER_GUILD_UPDATE", function() self:RefreshSnapshot("PLAYER_GUILD_UPDATE") end)
	self:RegisterEvent("GUILD_ROSTER_UPDATE", function() self:RefreshSnapshot("GUILD_ROSTER_UPDATE") end)

	_safeGuildRoster()
	self:RefreshSnapshot("enable")
	GMS:SetReady("MOD:" .. METADATA.INTERN_NAME)
end

function GuildInfo:OnDisable()
	GMS:SetNotReady("MOD:" .. METADATA.INTERN_NAME)
end

