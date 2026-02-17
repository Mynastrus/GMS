-- ============================================================================
--	GMS/Core/ModuleStates.lua
--	ModuleStates EXTENSION (no GMS:NewModule)
--	- Unified META registry for Extensions + AceModules
--	- Ready Hooks: GMS:OnReady(key, fn), GMS:SetReady(key), GMS:IsReady(key)
--	- Local-only logging into global buffer for later import by Logs.lua
--
--	Registry:
--		GMS.REGISTRY.EXT[KEY] = { key,name,displayName,version,desc,author,readyKey,state }
--		GMS.REGISTRY.MOD[KEY] = { ... }
--
--	Keys (recommended):
--		Extensions: "UI", "SLASH", "LOGS", "DB"  -> readyKey = "EXT:UI" etc.
--		Modules:    "CharInfo", "Roster"         -> readyKey = "MOD:CharInfo"
-- ============================================================================

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "MODULESTATES",
	SHORT_NAME   = "ModuleStates",
	DISPLAY_NAME = "Module States",
	VERSION      = "1.1.3",
}

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G = _G
local GetTime = GetTime
---@diagnostic enable: undefined-global

-- Prevent double-load
if GMS.ModuleStates then return end

local ModuleStates = {}
GMS.ModuleStates = ModuleStates

-- ###########################################################################
-- #	STATE
-- ###########################################################################

GMS.REGISTRY = GMS.REGISTRY or {}
GMS.REGISTRY.EXT = GMS.REGISTRY.EXT or {}
GMS.REGISTRY.MOD = GMS.REGISTRY.MOD or {}

GMS._READY = GMS._READY or {}
GMS._READY_HOOKS = GMS._READY_HOOKS or {}

-- Global log buffer (consumed later by Logs.lua)
GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

-- ###########################################################################
-- #	HELPERS
-- ###########################################################################

local function now()
	if type(GetTime) == "function" then
		return GetTime()
	end
	return nil
end

local function normExtKey(k)
	k = tostring(k or "")
	k = k:gsub("^%s+", ""):gsub("%s+$", "")
	return k:upper()
end

local function buildDisplayNameKey(meta)
	if type(meta) ~= "table" then
		return nil
	end
	local explicit = meta.DISPLAY_NAME_KEY or meta.displayNameKey
	if type(explicit) == "string" and explicit ~= "" then
		return explicit
	end
	local intern = meta.INTERN_NAME or meta.internName or meta.key or meta.name
	intern = tostring(intern or ""):gsub("[^%w]+", "_"):upper()
	if intern == "" then
		return nil
	end
	return "NAME_" .. intern
end

function GMS:ResolveDisplayName(displayNameKey, fallback)
	local key = tostring(displayNameKey or "")
	if key ~= "" and type(self.T) == "function" then
		local ok, text = pcall(self.T, self, key)
		if ok and type(text) == "string" and text ~= "" and text ~= key then
			return text
		end
	end
	return tostring(fallback or "")
end

function GMS:ResolveRegistryDisplayName(entry, fallback)
	if type(entry) ~= "table" then
		return tostring(fallback or "")
	end
	local rawFallback = entry.displayName or entry.name or entry.key or fallback or ""
	local key = entry.displayNameKey
	return self:ResolveDisplayName(key, rawFallback)
end

-- Local-only logger for this file (project standard)
local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time = now(),
		level = tostring(level or "INFO"),
		type = tostring(METADATA.TYPE or "UNKNOWN"),
		source = tostring(METADATA.SHORT_NAME or "UNKNOWN"),
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

local function ensureExt(key)
	key = normExtKey(key)
	local t = GMS.REGISTRY.EXT
	t[key] = t[key] or {
		key = key,
		name = key,
		displayName = key,
		version = "1.0.0",
		readyKey = "EXT:" .. key,
		state = { READY = false },
	}
	return t[key]
end

local function ensureMod(key)
	local t = GMS.REGISTRY.MOD
	t[key] = t[key] or {
		key = key,
		name = key,
		displayName = key,
		version = "1.0.0",
		readyKey = "MOD:" .. key,
		state = { READY = false, ENABLED = false },
	}
	return t[key]
end

local function updateRegistryState(readyKey, isReady)
	if type(readyKey) ~= "string" then return end
	local prefix, key = readyKey:match("^([^:]+):(.+)$")
	if not prefix or not key then return end

	if prefix == "EXT" then
		local e = ensureExt(key)
		e.state.READY = isReady
		if isReady then e.state.READY_AT = now() end
	elseif prefix == "MOD" then
		local m = ensureMod(key)
		m.state.READY = isReady
		if isReady then m.state.READY_AT = now() end
	end
end

-- ###########################################################################
-- #	PUBLIC: META REGISTRATION
-- ###########################################################################

function GMS:RegisterExtension(meta)
	if type(meta) ~= "table" then return end

	local rawKey = meta.key or meta.name or ""
	local key = normExtKey(rawKey)
	if key == "" then return end

	local entry = ensureExt(key)

	entry.key = key
	entry.name = (meta and (meta.NAME or meta.name)) or key
	entry.shortName = (meta and (meta.SHORT_NAME or meta.shortName)) or entry.shortName
	entry.displayNameKey = buildDisplayNameKey(meta) or entry.displayNameKey
	entry.displayName = GMS:ResolveDisplayName(entry.displayNameKey, (meta and (meta.DISPLAY_NAME or meta.displayName)) or entry.name)
	entry.version = (meta and (meta.VERSION or meta.version)) or entry.version or "1.0.0"
	entry.desc = meta.DESC or meta.desc
	entry.author = meta.AUTHOR or meta.author
	entry.readyKey = meta.readyKey or ("EXT:" .. key)
	entry.state = entry.state or { READY = false }

	LOCAL_LOG("DEBUG", "Registered extension", key)
	return entry
end

function GMS:RegisterModule(mod, meta)
	if type(mod) ~= "table" or type(mod.GetName) ~= "function" then return end
	local key = tostring(mod:GetName() or "")
	if key == "" then return end

	local entry = ensureMod(key)

	entry.key = key
	entry.name = (meta and (meta.NAME or meta.name)) or key
	entry.shortName = (meta and (meta.SHORT_NAME or meta.shortName)) or entry.shortName
	entry.displayNameKey = buildDisplayNameKey(meta) or entry.displayNameKey
	entry.displayName = GMS:ResolveDisplayName(entry.displayNameKey, (meta and (meta.DISPLAY_NAME or meta.displayName)) or entry.name)
	entry.version = (meta and (meta.VERSION or meta.version)) or entry.version or "1.0.0"
	entry.desc = meta and (meta.DESC or meta.desc)
	entry.author = meta and (meta.AUTHOR or meta.author)
	entry.readyKey = (meta and (meta.READY_KEY or meta.readyKey)) or ("MOD:" .. key)
	entry.state = entry.state or { READY = false, ENABLED = false }

	LOCAL_LOG("DEBUG", "Registered module", key)
	return entry
end

-- ###########################################################################
-- #	PUBLIC: READY HOOKS
-- ###########################################################################

function GMS:IsReady(key)
	return GMS._READY[key] == true
end

function GMS:SetReady(key)
	if type(key) ~= "string" or key == "" then return end

	-- Normalize EXT:* keys
	do
		local pfx, rest = key:match("^([^:]+):(.+)$")
		if pfx == "EXT" and rest then
			key = "EXT:" .. normExtKey(rest)
		end
	end

	if GMS._READY[key] then
		return
	end

	GMS._READY[key] = true
	updateRegistryState(key, true)

	LOCAL_LOG("INFO", "READY", key)

	local hooks = GMS._READY_HOOKS[key]
	if hooks then
		for i = 1, #hooks do
			pcall(hooks[i])
		end
		GMS._READY_HOOKS[key] = nil
	end
end

function GMS:SetNotReady(key)
	if type(key) ~= "string" or key == "" then return end

	-- Normalize EXT:* keys
	do
		local pfx, rest = key:match("^([^:]+):(.+)$")
		if pfx == "EXT" and rest then
			key = "EXT:" .. normExtKey(rest)
		end
	end

	if not GMS._READY[key] then
		return
	end

	GMS._READY[key] = false
	updateRegistryState(key, false)

	LOCAL_LOG("INFO", "UNREADY", key)
end

function GMS:OnReady(key, fn)
	if type(key) ~= "string" or key == "" then return end
	if type(fn) ~= "function" then return end

	if GMS:IsReady(key) then
		pcall(fn)
		return
	end

	GMS._READY_HOOKS[key] = GMS._READY_HOOKS[key] or {}
	table.insert(GMS._READY_HOOKS[key], fn)
end

-- ###########################################################################
-- #	OPTIONAL: ACE MODULE AUTO-TRACKING (opt-in)
-- ###########################################################################

function GMS:ModuleStates_InstallAceModuleHooks()
	if ModuleStates._aceHooksInstalled then return end
	ModuleStates._aceHooksInstalled = true

	if type(self.NewModule) ~= "function" then return end

	local origNewModule = self.NewModule
	self.NewModule = function(addon, name, ...)
		local m = origNewModule(addon, name, ...)

		if type(addon.RegisterModule) == "function" then
			pcall(addon.RegisterModule, addon, m, { displayName = tostring(name), version = "1.0.0" })
		end

		local key = tostring(name or "")
		local rkInit = "MOD_INIT:" .. key
		local rkReady = "MOD:" .. key

		local oInit = m.OnInitialize
		m.OnInitialize = function(mod, ...)
			if type(oInit) == "function" then oInit(mod, ...) end
			addon:SetReady(rkInit)
			LOCAL_LOG("DEBUG", "INIT", key)
		end

		local oEnable = m.OnEnable
		m.OnEnable = function(mod, ...)
			if type(oEnable) == "function" then oEnable(mod, ...) end
			addon:SetReady(rkReady)

			local e = GMS.REGISTRY and GMS.REGISTRY.MOD and GMS.REGISTRY.MOD[key]
			if e and e.state then
				e.state.ENABLED = true
				e.state.ENABLED_AT = now()
			end

			LOCAL_LOG("INFO", "ENABLED", key)
		end

		return m
	end
end

-- Register self metadata after API functions exist.
GMS:RegisterExtension({
	key = METADATA.INTERN_NAME,
	name = METADATA.SHORT_NAME,
	displayName = METADATA.DISPLAY_NAME,
	version = METADATA.VERSION,
})

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)
LOCAL_LOG("INFO", "ModuleStates extension loaded", METADATA.VERSION)
