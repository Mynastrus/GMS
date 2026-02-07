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

	local LibStub = LibStub
	if not LibStub then return end

	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end

	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end

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

	-- Local-only logger for this file
	local function LOCAL_LOG(level, source, msg, ...)
		local entry = {
			time   = now(),
			level  = tostring(level or "INFO"),
			source = tostring(source or "MODULESTATES"),
			msg    = tostring(msg or ""),
		}

		local n = select("#", ...)
		if n > 0 then
			entry.data = {}
			for i = 1, n do
				entry.data[i] = select(i, ...)
			end
		end

		GMS._LOG_BUFFER[#GMS._LOG_BUFFER + 1] = entry
	end

	local function ensureExt(key)
		key = normExtKey(key)
		local t = GMS.REGISTRY.EXT
		t[key] = t[key] or {
			key = key,
			name = key,
			displayName = key,
			version = 1,
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
			version = 1,
			readyKey = "MOD:" .. key,
			state = { READY = false, ENABLED = false },
		}
		return t[key]
	end

	local function updateRegistryState(readyKey)
		if type(readyKey) ~= "string" then return end
		local prefix, key = readyKey:match("^([^:]+):(.+)$")
		if not prefix or not key then return end

		if prefix == "EXT" then
			local e = ensureExt(key)
			e.state.READY = true
			e.state.READY_AT = now()
		elseif prefix == "MOD" then
			local m = ensureMod(key)
			m.state.READY = true
			m.state.READY_AT = now()
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
		entry.name = meta.name or key
		entry.displayName = meta.displayName or entry.name
		entry.version = meta.version or entry.version or 1
		entry.desc = meta.desc
		entry.author = meta.author
		entry.readyKey = meta.readyKey or ("EXT:" .. key)
		entry.state = entry.state or { READY = false }

		LOCAL_LOG("DEBUG", "EXT", "Registered extension", key)
		return entry
	end

	function GMS:RegisterModule(mod, meta)
		if type(mod) ~= "table" or type(mod.GetName) ~= "function" then return end
		local key = tostring(mod:GetName() or "")
		if key == "" then return end

		local entry = ensureMod(key)

		entry.key = key
		entry.name = (meta and meta.name) or key
		entry.displayName = (meta and meta.displayName) or entry.name
		entry.version = (meta and meta.version) or entry.version or 1
		entry.desc = meta and meta.desc
		entry.author = meta and meta.author
		entry.readyKey = (meta and meta.readyKey) or ("MOD:" .. key)
		entry.state = entry.state or { READY = false, ENABLED = false }

		LOCAL_LOG("DEBUG", "MOD", "Registered module", key)
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
		updateRegistryState(key)

		LOCAL_LOG("INFO", "STATE", "READY", key)

		local hooks = GMS._READY_HOOKS[key]
		if hooks then
			for i = 1, #hooks do
				pcall(hooks[i])
			end
			GMS._READY_HOOKS[key] = nil
		end
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
				pcall(addon.RegisterModule, addon, m, { displayName = tostring(name), version = 1 })
			end

			local key = tostring(name or "")
			local rkInit = "MOD_INIT:" .. key
			local rkReady = "MOD:" .. key

			local oInit = m.OnInitialize
			m.OnInitialize = function(mod, ...)
				if type(oInit) == "function" then oInit(mod, ...) end
				addon:SetReady(rkInit)
				LOCAL_LOG("DEBUG", "MOD", "INIT", key)
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

				LOCAL_LOG("INFO", "MOD", "ENABLED", key)
			end

			return m
		end
	end
