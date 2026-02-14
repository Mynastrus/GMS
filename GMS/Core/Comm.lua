-- ============================================================================
--	GMS/Core/Comm.lua
--	Comm EXTENSION
--	- Generic guild comm (existing API: RegisterPrefix/SendData)
--	- New sync protocol for shared character/module records
--	- Large datasets: announce on GUILD, pull via WHISPER (no group transport)
-- ============================================================================

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "COMM",
	SHORT_NAME   = "Comm",
	DISPLAY_NAME = "Kommunikation",
	VERSION      = "1.2.0",
}

---@diagnostic disable: undefined-global
local _G                = _G
local GetTime           = GetTime
local UnitGUID          = UnitGUID
local IsInGuild         = IsInGuild
local C_Timer           = C_Timer
local GetNumGuildMembers = GetNumGuildMembers
local GetGuildRosterInfo = GetGuildRosterInfo
local GetRealmName      = GetRealmName
---@diagnostic enable: undefined-global

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
local GMS = AceAddon and AceAddon:GetAddon("GMS", true) or nil
if not GMS then return end

local AceComm = LibStub("AceComm-3.0", true)
local AceSerializer = LibStub("AceSerializer-3.0", true)
local LibDeflate = LibStub("LibDeflate", true)

if not AceComm or not AceSerializer or not LibDeflate then
	return
end

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return GetTime and GetTime() or 0
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
	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry
	if type(GMS._LOG_NOTIFY) == "function" then
		pcall(GMS._LOG_NOTIFY, entry, idx)
	end
end

GMS.Comm = GMS.Comm or {}
local Comm = GMS.Comm

Comm.PREFIX = "GMS_G"
Comm.SYNC_SUBPREFIX = "__SYNC_V1"

Comm._handlers = Comm._handlers or {}
Comm._recordListeners = Comm._recordListeners or {}
Comm._requestCooldown = Comm._requestCooldown or {}
Comm._chunkInbox = Comm._chunkInbox or {}
Comm._relayTicker = Comm._relayTicker or nil

Comm.SYNC_CFG = Comm.SYNC_CFG or {
	SMALL_PUSH_MAX = 900,
	CHUNK_SIZE = 700,
	CHUNK_TTL = 120,
	REQUEST_COOLDOWN = 5,
	RELAY_INTERVAL = 180,
	RELAY_BATCH = 20,
}

local COMM_SYNC_DEFAULTS = {
	records = {},
	state = { seq = {} },
}
Comm._syncOptionsRegistered = Comm._syncOptionsRegistered or false

local function NormalizeName(name)
	if type(name) ~= "string" or name == "" then return "" end
	return string.lower(name:gsub("%s+", ""))
end

local function ResolveSenderGUIDFromGuildRoster(sender)
	if type(sender) ~= "string" or sender == "" then return nil end
	if not IsInGuild or not IsInGuild() then return nil end
	if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
		return nil
	end

	local senderNorm = NormalizeName(sender)
	local senderShort = NormalizeName(sender:match("^([^%-]+)") or sender)
	local realmName = NormalizeName((GetRealmName and GetRealmName()) or "")
	local senderWithLocalRealm = senderShort
	if realmName ~= "" then
		senderWithLocalRealm = senderShort .. "-" .. realmName
	end

	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		if name and guid then
			local full = NormalizeName(name)
			local short = NormalizeName(name:match("^([^%-]+)") or name)
			if full == senderNorm or short == senderShort or full == senderWithLocalRealm then
				return guid
			end
		end
	end
	return nil
end

local function GetGuildRoot()
	if not Comm._syncOptionsRegistered and type(GMS.RegisterModuleOptions) == "function" then
		pcall(function()
			GMS:RegisterModuleOptions("COMM_SYNC", COMM_SYNC_DEFAULTS, "GUILD")
		end)
		Comm._syncOptionsRegistered = true
	end
	if type(GMS.GetModuleOptions) ~= "function" then return nil end
	local ok, root = pcall(GMS.GetModuleOptions, GMS, "COMM_SYNC")
	if not ok or type(root) ~= "table" then return nil end
	return root
end

local function GetSyncStore()
	local root = GetGuildRoot()
	if type(root) ~= "table" then return nil end
	root.records = type(root.records) == "table" and root.records or {}
	root.state = type(root.state) == "table" and root.state or {}
	root.state.seq = type(root.state.seq) == "table" and root.state.seq or {}
	return root
end

local function ComputeChecksumFromString(s)
	local txt = tostring(s or "")
	local h = 0
	local mod = 4294967291
	for i = 1, #txt do
		local b = txt:byte(i)
		h = (h * 131 + b) % mod
	end
	return string.format("%08x", h % 0xFFFFFFFF)
end

local function SerializePayload(payload)
	local ok, serialized = pcall(AceSerializer.Serialize, AceSerializer, payload)
	if not ok then return nil end
	return serialized
end

local function BuildRecordKey(originGUID, charGUID, domain)
	return string.format("%s:%s:%s", tostring(originGUID or ""), tostring(charGUID or ""), tostring(domain or ""))
end

local function CompareRecordFreshness(a, b)
	-- returns 1 if a newer, -1 if b newer, 0 equal
	local aSeq = tonumber(a and a.seq) or 0
	local bSeq = tonumber(b and b.seq) or 0
	if aSeq ~= bSeq then
		return (aSeq > bSeq) and 1 or -1
	end
	local aTs = tonumber(a and a.updatedAt) or 0
	local bTs = tonumber(b and b.updatedAt) or 0
	if aTs ~= bTs then
		return (aTs > bTs) and 1 or -1
	end
	return 0
end

local function ValidateRecord(record)
	if type(record) ~= "table" then return false, "record-not-table" end
	if type(record.key) ~= "string" or record.key == "" then return false, "missing-key" end
	if type(record.originGUID) ~= "string" or record.originGUID == "" then return false, "missing-origin" end
	if type(record.charGUID) ~= "string" or record.charGUID == "" then return false, "missing-char" end
	if type(record.domain) ~= "string" or record.domain == "" then return false, "missing-domain" end
	if type(record.seq) ~= "number" then return false, "missing-seq" end
	if type(record.updatedAt) ~= "number" then return false, "missing-updatedAt" end
	if type(record.checksum) ~= "string" or record.checksum == "" then return false, "missing-checksum" end
	if record.payload == nil then return false, "missing-payload" end

	local serialized = SerializePayload(record.payload)
	if not serialized then return false, "payload-serialize-failed" end
	local checksum = ComputeChecksumFromString(serialized)
	if checksum ~= record.checksum then
		return false, "checksum-mismatch"
	end
	return true
end

local function BuildMeta(record, payloadSize)
	return {
		k = record.key,
		og = record.originGUID,
		cg = record.charGUID,
		d = record.domain,
		seq = record.seq,
		ts = record.updatedAt,
		cs = record.checksum,
		sz = tonumber(payloadSize) or 0,
	}
end

local function ParseMeta(m)
	if type(m) ~= "table" then return nil end
	local out = {
		key = tostring(m.k or ""),
		originGUID = tostring(m.og or ""),
		charGUID = tostring(m.cg or ""),
		domain = tostring(m.d or ""),
		seq = tonumber(m.seq) or 0,
		updatedAt = tonumber(m.ts) or 0,
		checksum = tostring(m.cs or ""),
		size = tonumber(m.sz) or 0,
	}
	if out.key == "" or out.originGUID == "" or out.charGUID == "" or out.domain == "" then
		return nil
	end
	return out
end

local function SendRaw(subPrefix, data, priority, distribution, targetName)
	if not IsInGuild or not IsInGuild() then return false end
	if type(distribution) ~= "string" or distribution == "" then
		distribution = "GUILD"
	end
	if distribution == "WHISPER" and (type(targetName) ~= "string" or targetName == "") then
		return false
	end

	local packet = {
		pfx = subPrefix,
		ts  = now(),
		v   = METADATA.VERSION,
		src = (type(UnitGUID) == "function") and UnitGUID("player") or nil,
		d   = data,
	}

	local serialized = AceSerializer:Serialize(packet)
	if not serialized then return false end
	local compressed = LibDeflate:CompressDeflate(serialized)
	local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)

	GMS:SendCommMessage(Comm.PREFIX, encoded, distribution, targetName, priority or "NORMAL")
	return true
end

function Comm:RegisterPrefix(subPrefix, callback, requiredCapability)
	if type(subPrefix) ~= "string" or subPrefix == "" then return end
	if type(callback) ~= "function" then return end
	self._handlers[subPrefix] = { cb = callback, cap = requiredCapability }
	LOCAL_LOG("DEBUG", "Registered prefix handler", subPrefix)
end

function Comm:RegisterRecordListener(domain, callback)
	if type(domain) ~= "string" or domain == "" then return false end
	if type(callback) ~= "function" then return false end
	self._recordListeners[domain] = self._recordListeners[domain] or {}
	self._recordListeners[domain][#self._recordListeners[domain] + 1] = callback
	return true
end

-- Backward-compatible signature:
-- SendData(subPrefix, data, priority, target[, targetName])
function Comm:SendData(subPrefix, data, priority, target, targetName)
	local distribution = target or "GUILD"
	local ok = SendRaw(subPrefix, data, priority or "NORMAL", distribution, targetName)
	if ok then
		LOCAL_LOG("DEBUG", "Data sent", subPrefix, distribution, targetName or "")
	end
	return ok
end

local function StoreIfNewer(record, senderGUID, channel)
	local store = GetSyncStore()
	if type(store) ~= "table" then return false, "no-store" end
	local records = store.records
	local existing = records[record.key]

	if existing and CompareRecordFreshness(record, existing) < 0 then
		return false, "older"
	end

	records[record.key] = {
		key = record.key,
		originGUID = record.originGUID,
		charGUID = record.charGUID,
		domain = record.domain,
		seq = record.seq,
		updatedAt = record.updatedAt,
		checksum = record.checksum,
		payload = record.payload,
		receivedAt = now(),
		lastSender = senderGUID or "",
		lastChannel = channel or "",
	}

	local listeners = Comm._recordListeners[record.domain]
	if type(listeners) == "table" then
		for i = 1, #listeners do
			local cb = listeners[i]
			if type(cb) == "function" then
				pcall(cb, records[record.key], senderGUID, channel)
			end
		end
	end
	return true
end

function Comm:GetRecord(originGUID, charGUID, domain)
	local key = BuildRecordKey(originGUID, charGUID, domain)
	local store = GetSyncStore()
	if type(store) ~= "table" then return nil end
	return store.records[key]
end

function Comm:GetRecordsByDomain(domain)
	local d = tostring(domain or "")
	local out = {}
	local store = GetSyncStore()
	if type(store) ~= "table" then return out end
	for _, rec in pairs(store.records) do
		if rec and rec.domain == d then
			out[#out + 1] = rec
		end
	end
	return out
end

local function NextSequenceFor(ownerCharDomainKey)
	local store = GetSyncStore()
	if type(store) ~= "table" then return 1 end
	local seqMap = store.state and store.state.seq
	if type(seqMap) ~= "table" then
		store.state = store.state or {}
		store.state.seq = {}
		seqMap = store.state.seq
	end
	local nextSeq = (tonumber(seqMap[ownerCharDomainKey]) or 0) + 1
	seqMap[ownerCharDomainKey] = nextSeq
	return nextSeq
end

local function SendSyncAnnounce(record, payloadSize)
	return SendRaw(Comm.SYNC_SUBPREFIX, {
		op = "ANN",
		m = BuildMeta(record, payloadSize),
	}, "BULK", "GUILD", nil)
end

local function SendSyncRequest(key, senderName, preferWhisper)
	local distribution = (preferWhisper and type(senderName) == "string" and senderName ~= "") and "WHISPER" or "GUILD"
	local targetName = (distribution == "WHISPER") and senderName or nil
	return SendRaw(Comm.SYNC_SUBPREFIX, {
		op = "REQ",
		k = tostring(key or ""),
		mode = (distribution == "WHISPER") and "WHISPER" or "GUILD",
	}, "NORMAL", distribution, targetName)
end

local function SendRecordPush(record, distribution, targetName)
	return SendRaw(Comm.SYNC_SUBPREFIX, {
		op = "PUSH",
		r = record,
	}, "NORMAL", distribution, targetName)
end

local function SendRecordChunked(record, distribution, targetName)
	local serializedRecord = SerializePayload(record)
	if not serializedRecord then return false end

	local chunkSize = tonumber(Comm.SYNC_CFG.CHUNK_SIZE) or 700
	if chunkSize < 200 then chunkSize = 200 end
	local total = math.ceil(#serializedRecord / chunkSize)
	local tx = string.format("%d:%s:%s", math.floor(now() * 1000), tostring(record.key or ""), tostring(UnitGUID("player") or ""))

	for i = 1, total do
		local from = (i - 1) * chunkSize + 1
		local to = math.min(i * chunkSize, #serializedRecord)
		local part = serializedRecord:sub(from, to)
		local ok = SendRaw(Comm.SYNC_SUBPREFIX, {
			op = "PCH",
			tx = tx,
			k = record.key,
			i = i,
			n = total,
			p = part,
		}, "BULK", distribution, targetName)
		if not ok then return false end
	end
	return true
end

local function SendRecordToPeer(record, senderName, requestedMode)
	local payloadSerialized = SerializePayload(record and record.payload)
	local payloadSize = payloadSerialized and #payloadSerialized or 0
	local whisperPreferred = (requestedMode == "WHISPER")
	local canWhisper = (type(senderName) == "string" and senderName ~= "")
	local distribution = (whisperPreferred and canWhisper) and "WHISPER" or "GUILD"
	local targetName = (distribution == "WHISPER") and senderName or nil

	if payloadSize <= (tonumber(Comm.SYNC_CFG.SMALL_PUSH_MAX) or 900) then
		return SendRecordPush(record, distribution, targetName)
	end
	return SendRecordChunked(record, distribution, targetName)
end

function Comm:PublishRecord(domain, charGUID, payload, opts)
	opts = opts or {}
	local owner = (type(UnitGUID) == "function") and UnitGUID("player") or nil
	if type(owner) ~= "string" or owner == "" then return false, "no-owner" end

	local cGuid = tostring(charGUID or owner)
	local d = tostring(domain or "")
	if d == "" then return false, "no-domain" end

	local ownerCharDomainKey = owner .. ":" .. cGuid .. ":" .. d
	local seq = tonumber(opts.seq) or NextSequenceFor(ownerCharDomainKey)
	local updatedAt = tonumber(opts.updatedAt) or now()
	local payloadSerialized = SerializePayload(payload)
	if not payloadSerialized then return false, "payload-serialize-failed" end

	local record = {
		key = BuildRecordKey(owner, cGuid, d),
		originGUID = owner,
		charGUID = cGuid,
		domain = d,
		seq = seq,
		updatedAt = updatedAt,
		checksum = ComputeChecksumFromString(payloadSerialized),
		payload = payload,
	}

	local valid, reason = ValidateRecord(record)
	if not valid then return false, reason end

	local stored, storeReason = StoreIfNewer(record, owner, "LOCAL")
	if not stored and storeReason ~= "older" then
		return false, storeReason
	end

	SendSyncAnnounce(record, #payloadSerialized)
	if #payloadSerialized <= (tonumber(self.SYNC_CFG.SMALL_PUSH_MAX) or 900) then
		SendRecordPush(record, "GUILD", nil)
	end
	return true, record.key
end

function Comm:PublishCharacterRecord(domain, payload, opts)
	local charGUID = (type(UnitGUID) == "function") and UnitGUID("player") or nil
	return self:PublishRecord(domain, charGUID, payload, opts)
end

local function CleanupChunkInbox()
	local ttl = tonumber(Comm.SYNC_CFG.CHUNK_TTL) or 120
	local cutoff = now() - ttl
	for key, info in pairs(Comm._chunkInbox) do
		if type(info) ~= "table" or (tonumber(info.startedAt) or 0) < cutoff then
			Comm._chunkInbox[key] = nil
		end
	end
end

local function HandleChunkPacket(senderGUID, senderName, channel, d)
	if type(d) ~= "table" then return end
	local tx = tostring(d.tx or "")
	local idx = tonumber(d.i) or 0
	local total = tonumber(d.n) or 0
	local part = tostring(d.p or "")
	if tx == "" or idx < 1 or total < 1 or part == "" then return end

	CleanupChunkInbox()
	local inboxKey = tostring(senderGUID or senderName or "?") .. ":" .. tx
	local entry = Comm._chunkInbox[inboxKey]
	if type(entry) ~= "table" then
		entry = { startedAt = now(), parts = {}, total = total, key = tostring(d.k or "") }
		Comm._chunkInbox[inboxKey] = entry
	end
	entry.total = total
	entry.parts[idx] = part

	local count = 0
	for i = 1, entry.total do
		if entry.parts[i] then count = count + 1 end
	end
	if count < entry.total then return end

	local chunks = {}
	for i = 1, entry.total do
		chunks[i] = entry.parts[i]
	end
	local serialized = table.concat(chunks, "")
	Comm._chunkInbox[inboxKey] = nil

	local ok, record = AceSerializer:Deserialize(serialized)
	if not ok or type(record) ~= "table" then
		LOCAL_LOG("WARN", "Chunk reassembly deserialize failed", senderGUID or "", senderName or "")
		return
	end

	local valid, reason = ValidateRecord(record)
	if not valid then
		LOCAL_LOG("WARN", "Invalid chunked record", reason, record and record.key or "")
		return
	end

	local stored = StoreIfNewer(record, senderGUID, channel)
	if stored then
		LOCAL_LOG("DEBUG", "Stored chunked sync record", record.key, channel or "")
	end
end

local function HandleSyncAnnounce(senderName, senderGUID, d)
	local meta = ParseMeta(d and d.m)
	if not meta then return end

	local store = GetSyncStore()
	if type(store) ~= "table" then return end
	local existing = store.records[meta.key]
	local incomingPseudo = {
		seq = meta.seq,
		updatedAt = meta.updatedAt,
	}
	local needsUpdate = (not existing) or CompareRecordFreshness(incomingPseudo, existing) > 0
	if not needsUpdate then return end

	local cooldownKey = tostring(meta.key or "")
	local lastReq = tonumber(Comm._requestCooldown[cooldownKey]) or 0
	if now() - lastReq < (tonumber(Comm.SYNC_CFG.REQUEST_COOLDOWN) or 5) then
		return
	end
	Comm._requestCooldown[cooldownKey] = now()

	local preferWhisper = (meta.size >= (tonumber(Comm.SYNC_CFG.SMALL_PUSH_MAX) or 900))
	SendSyncRequest(meta.key, senderName, preferWhisper)
end

local function HandleSyncRequest(senderName, senderGUID, d)
	local key = tostring(d and d.k or "")
	if key == "" then return end
	local mode = tostring(d and d.mode or "GUILD")

	local store = GetSyncStore()
	if type(store) ~= "table" then return end
	local record = store.records[key]
	if type(record) ~= "table" then return end

	SendRecordToPeer(record, senderName, mode)
end

local function HandleSyncPush(senderGUID, channel, d)
	local record = d and d.r
	local valid, reason = ValidateRecord(record)
	if not valid then
		LOCAL_LOG("WARN", "Invalid sync push record", reason, record and record.key or "")
		return
	end
	local stored = StoreIfNewer(record, senderGUID, channel)
	if stored then
		LOCAL_LOG("DEBUG", "Stored sync push record", record.key, channel or "")
	end
end

local function HandleSyncPacket(senderName, senderGUID, channel, d)
	local op = tostring(d and d.op or "")
	if op == "ANN" then
		return HandleSyncAnnounce(senderName, senderGUID, d)
	end
	if op == "REQ" then
		return HandleSyncRequest(senderName, senderGUID, d)
	end
	if op == "PUSH" then
		return HandleSyncPush(senderGUID, channel, d)
	end
	if op == "PCH" then
		return HandleChunkPacket(senderGUID, senderName, channel, d)
	end
end

function Comm:BroadcastRelayAnnounces(limit)
	local store = GetSyncStore()
	if type(store) ~= "table" then return 0 end
	local maxCount = tonumber(limit) or tonumber(self.SYNC_CFG.RELAY_BATCH) or 20
	if maxCount < 1 then return 0 end

	local list = {}
	for _, rec in pairs(store.records) do
		if type(rec) == "table" then
			list[#list + 1] = rec
		end
	end
	table.sort(list, function(a, b)
		local at = tonumber(a.updatedAt) or 0
		local bt = tonumber(b.updatedAt) or 0
		return at > bt
	end)

	local sent = 0
	for i = 1, #list do
		if sent >= maxCount then break end
		local rec = list[i]
		local payloadSerialized = SerializePayload(rec.payload)
		local payloadSize = payloadSerialized and #payloadSerialized or 0
		if SendSyncAnnounce(rec, payloadSize) then
			sent = sent + 1
		end
	end
	if sent > 0 then
		LOCAL_LOG("DEBUG", "Relay announce batch sent", sent)
	end
	return sent
end

function Comm:OnCommReceive(prefix, msg, channel, sender)
	if prefix ~= self.PREFIX then return end

	local decoded = LibDeflate:DecodeForWoWAddonChannel(msg)
	if not decoded then return end
	local decompressed = LibDeflate:DecompressDeflate(decoded)
	if not decompressed then return end
	local success, packet = AceSerializer:Deserialize(decompressed)
	if not success or type(packet) ~= "table" then return end

	local subPrefix = packet.pfx
	local senderGUID = ResolveSenderGUIDFromGuildRoster(sender) or packet.src

	if packet.src and senderGUID and packet.src ~= senderGUID then
		LOCAL_LOG("WARN", "Source GUID mismatch", subPrefix, sender, packet.src, senderGUID)
		return
	end

	if subPrefix == self.SYNC_SUBPREFIX then
		return HandleSyncPacket(sender, senderGUID, channel, packet.d)
	end

	local handler = self._handlers[subPrefix]
	if not handler then return end

	if GMS.Permissions and type(GMS.Permissions.HasCapability) == "function" then
		if handler.cap and not senderGUID then
			LOCAL_LOG("WARN", "Missing sender GUID for secured prefix", subPrefix, sender)
			return
		end
		if handler.cap and not GMS.Permissions:HasCapability(senderGUID, handler.cap) then
			LOCAL_LOG("WARN", "Unauthorized data received", subPrefix, sender, senderGUID)
			return
		end
	end

	packet.src_claimed = packet.src
	packet.src = senderGUID
	pcall(handler.cb, senderGUID, packet.d, packet)
end

function Comm:Initialize()
	GMS:RegisterComm(self.PREFIX, function(...) self:OnCommReceive(...) end)

	if not self._relayTicker and C_Timer and type(C_Timer.NewTicker) == "function" then
		local interval = tonumber(self.SYNC_CFG.RELAY_INTERVAL) or 180
		self._relayTicker = C_Timer.NewTicker(interval, function()
			Comm:BroadcastRelayAnnounces()
		end)
	end

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
