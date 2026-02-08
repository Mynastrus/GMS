-- ============================================================================
--	GMS/Core/ChatLinks.lua
--	ChatLinks EXTENSION
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- ###########################################################################
-- #	METADATA
-- ###########################################################################

local METADATA = {
	TYPE = "EXTENSION",
	INTERN_NAME = "CHATLINKS",
	SHORT_NAME = "ChatLinks",
	DISPLAY_NAME = "Chat Links",
	VERSION = "1.0.2",
}

-- ###########################################################################
-- #	LOG BUFFER + LOCAL LOGGER
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return GetTime and GetTime() or nil
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

	local buffer = GMS._LOG_BUFFER
	local idx = #buffer + 1
	buffer[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		GMS._LOG_NOTIFY(entry, idx)
	end
end

-- ###########################################################################
-- #	MODULESTATES REGISTRATION
-- ###########################################################################

if type(GMS.RegisterExtension) == "function" then
	GMS:RegisterExtension({
		key = METADATA.INTERN_NAME,
		name = METADATA.SHORT_NAME,
		displayName = METADATA.DISPLAY_NAME,
		version = METADATA.VERSION,
		desc = "Clickable chat links with tooltip and click handling",
	})
end

-- ###########################################################################
-- #	REGISTRY
-- ###########################################################################

GMS.ChatLinks = GMS.ChatLinks or {}
local ChatLinks = GMS.ChatLinks

ChatLinks.REGISTRY = ChatLinks.REGISTRY or {}
ChatLinks.LINK_TYPE = ChatLinks.LINK_TYPE or "GMS"

ChatLinks.COLOR = ChatLinks.COLOR or "FFFFCC00"
ChatLinks.COLOR_TOOLTIP_TEXT = ChatLinks.COLOR_TOOLTIP_TEXT or { 0.8, 0.8, 0.8 }

ChatLinks.DEFAULT_FLAGS = ChatLinks.DEFAULT_FLAGS or {
	showLabel = true,
	showHint = true,
	showTooltipLines = true,
	showActionFallback = true,
}

local function UPPER(s) return string.upper(tostring(s or "")) end

local function TRIM(s) return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local function MergeFlags(dst, src)
	for k, v in pairs(src or {}) do dst[k] = v end
	return dst
end

local function ResolveFlags(entry)
	local out = MergeFlags({}, ChatLinks.DEFAULT_FLAGS)
	if entry and type(entry.flags) == "table" then
		out = MergeFlags(out, entry.flags)
	end
	return out
end

local function ParseLink(link)
	local linkType, action, title = strsplit(":", tostring(link or ""))
	if UPPER(linkType) ~= ChatLinks.LINK_TYPE then return end
	action = UPPER(action)
	if action == "" then return end
	title = TRIM(title)
	if title == "" then title = nil end
	return action, title
end

-- ###########################################################################
-- #	PUBLIC API
-- ###########################################################################

function GMS:ChatLink_Define(action, spec)
	action = UPPER(action)
	if action == "" then return false end

	spec = spec or {}
	ChatLinks.REGISTRY[action] = {
		action = action,
		title = tostring(spec.title or "|cff03A9F4[GMS]|r"),
		label = tostring(spec.label or action),
		hint = tostring(spec.hint or ""),
		tooltip = spec.tooltip,
		flags = spec.flags,
	}

	LOCAL_LOG("DEBUG", "Defined action", action)
	return true
end

function GMS:ChatLink_Build(action, labelOverride, tooltipTitleOverride)
	action = UPPER(action)
	local entry = ChatLinks.REGISTRY[action] or { label = action }
	local label = tostring(labelOverride or entry.label)
	local color = ChatLinks.COLOR

	local title = TRIM(tooltipTitleOverride)
	if title == "" then
		return ("|c%s|H%s:%s|h%s|h|r"):format(color, ChatLinks.LINK_TYPE, action, label)
	end

	return ("|c%s|H%s:%s:%s|h%s|h|r"):format(color, ChatLinks.LINK_TYPE, action, title, label)
end

ChatLinks.CLICK_HANDLERS = ChatLinks.CLICK_HANDLERS or {}

function GMS:ChatLink_OnClick(action, fn)
	action = UPPER(action)
	if type(fn) ~= "function" then return false end
	ChatLinks.CLICK_HANDLERS[action] = fn
	return true
end

-- ###########################################################################
-- #	TOOLTIP + CLICK
-- ###########################################################################

local function Tooltip_AddLine(tt, text)
	local c = ChatLinks.COLOR_TOOLTIP_TEXT
	tt:AddLine(tostring(text), c[1], c[2], c[3], true)
end

local function Tooltip_Show(frame, link)
	local action, titleOverride = ParseLink(link)
	if not action then return end

	local entry = ChatLinks.REGISTRY[action]
	local flags = ResolveFlags(entry)

	GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
	GameTooltip:SetText(titleOverride or (entry and entry.title) or "|cff03A9F4[GMS]|r")

	if entry then
		if flags.showLabel and entry.label ~= "" then Tooltip_AddLine(GameTooltip, entry.label) end
		if flags.showHint and entry.hint ~= "" then
			Tooltip_AddLine(GameTooltip, "Befehl: |cFFFFCC00" .. entry.hint .. "|r")
		end
	end

	GameTooltip:Show()
end

local function OnClick(link, text, button)
	local action = select(1, ParseLink(link))
	local fn = action and ChatLinks.CLICK_HANDLERS[action]
	if fn then
		local ok, err = pcall(fn, action, link, text, button)
		if not ok then
			LOCAL_LOG("ERROR", "Click handler error", err)
		end
	end
end

-- ###########################################################################
-- #	HOOKS
-- ###########################################################################

if not ChatLinks._hooked then
	ChatLinks._hooked = true

	for i = 1, NUM_CHAT_WINDOWS do
		local chat = _G["ChatFrame" .. i]
		if chat then
			GMS:HookScript(chat, "OnHyperlinkEnter", Tooltip_Show)
			GMS:HookScript(chat, "OnHyperlinkLeave", GameTooltip.Hide)
		end
	end

	GMS:SecureHook("SetItemRef", OnClick)
end

-- ###########################################################################
-- #	READY
-- ###########################################################################

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)

LOCAL_LOG("INFO", "ChatLinks loaded")
