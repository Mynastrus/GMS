-- ============================================================================
--	GMS/Core/Comm.lua
--	Comm EXTENSION
--	- Global Guild Communication
--	- Uses AceComm-3.0, LibDeflate, AceSerializer-3.0
--	- Integrated Security via Permissions EXT
-- ============================================================================

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "COMM",
	SHORT_NAME   = "Comm",
	DISPLAY_NAME = "Kommunikation",
	VERSION      = "1.0.0",
}

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G        = _G
local GetTime   = GetTime
local UnitGUID  = UnitGUID
local IsInGuild = IsInGuild
local C_Timer   = C_Timer
---@diagnostic enable: undefined-global

-- ---------------------------------------------------------------------------
--	Guards
-- ---------------------------------------------------------------------------

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
local GMS = AceAddon and AceAddon:GetAddon("GMS", true) or nil
if not GMS then return end

local AceComm = LibStub("AceComm-3.0", true)
local AceSerializer = LibStub("AceSerializer-3.0", true)
local LibDeflate = LibStub("LibDeflate", true)

if not AceComm or not AceSerializer or not LibDeflate then
	-- These are requirements for this extension
	return
end

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

GMS.Comm = GMS.Comm or {}
local Comm = GMS.Comm

Comm.PREFIX = "GMS_G" -- Global GMS Prefix for AceComm
Comm._handlers = {}

-- ###########################################################################
-- #	API
-- ###########################################################################

--- Registers a handler for a specific data prefix
-- @param subPrefix string: The submodule prefix (e.g., "PERM", "ROST")
-- @param callback function: function(senderGUID, data, rawMsg)
-- @param requiredCapability string|nil: Optional capability check
function Comm:RegisterPrefix(subPrefix, callback, requiredCapability)
	if type(subPrefix) ~= "string" or subPrefix == "" then return end
	if type(callback) ~= "function" then return end

	self._handlers[subPrefix] = {
		cb = callback,
		cap = requiredCapability,
	}
	LOCAL_LOG("DEBUG", "Registered prefix handler", subPrefix)
end

--- Sends data to the guild
-- @param subPrefix string: The submodule prefix
-- @param data any: The data to send (will be serialized and compressed)
-- @param priority string: "BULK", "NORMAL", "ALERT"
-- @param target string|nil: Optional target (default "GUILD")
function Comm:SendData(subPrefix, data, priority, target)
	if not IsInGuild() then return false end
	priority = priority or "NORMAL"
	target = target or "GUILD"

	-- Build Packet
	local packet = {
		pfx = subPrefix,
		ts  = GetTime(),
		v   = METADATA.VERSION,
		src = UnitGUID("player"),
		d   = data,
	}

	-- 1. Serialize
	local serialized = AceSerializer:Serialize(packet)
	if not serialized then return false end

	-- 2. Compress
	local compressed = LibDeflate:CompressDeflate(serialized)
	local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)

	-- 3. Send
	GMS:SendCommMessage(self.PREFIX, encoded, target, nil, priority)
	LOCAL_LOG("DEBUG", "Data sent", subPrefix, target)
	return true
end

-- ###########################################################################
-- #	RECEIVE LOGIC
-- ###########################################################################

function Comm:OnCommReceive(prefix, msg, channel, sender)
	if prefix ~= self.PREFIX then return end

	-- 1. Decode & Decompress
	local decoded = LibDeflate:DecodeForWoWAddonChannel(msg)
	if not decoded then return end

	local decompressed = LibDeflate:DecompressDeflate(decoded)
	if not decompressed then return end

	-- 2. Deserialize
	local success, packet = AceSerializer:Deserialize(decompressed)
	if not success or type(packet) ~= "table" then return end

	local subPrefix = packet.pfx
	local handler = self._handlers[subPrefix]
	if not handler then return end

	-- 3. Security Check (Permissions Integration)
	if GMS.Permissions and type(GMS.Permissions.HasCapability) == "function" then
		local senderGUID = packet.src
		if handler.cap and not GMS.Permissions:HasCapability(senderGUID, handler.cap) then
			LOCAL_LOG("WARN", "Unauthorized data received", subPrefix, sender, senderGUID)
			return
		end
	end

	-- 4. Execute Callback
	pcall(handler.cb, packet.src, packet.d, packet)
end

-- ###########################################################################
-- #	BOOTSTRAP
-- ###########################################################################

function Comm:Initialize()
	GMS:RegisterComm(self.PREFIX, function(...) self:OnCommReceive(...) end)
	LOCAL_LOG("INFO", "Comm initialized")
end

Comm:Initialize()

GMS:RegisterExtension({
	key = METADATA.SHORT_NAME,
	name = METADATA.INTERN_NAME,
	displayName = METADATA.DISPLAY_NAME,
	version = METADATA.VERSION,
})

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)

LOCAL_LOG("INFO", "Comm extension loaded")
