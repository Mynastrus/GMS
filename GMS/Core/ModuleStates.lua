	-- ============================================================================
	--	GMS/Core/ModuleStates.lua
	--	ModuleStates EXTENSION (no GMS:NewModule)
	--	- Unified META registry for Extensions + AceModules
	--	- Ready Hooks: GMS:OnReady(key, fn), GMS:SetReady(key), GMS:IsReady(key)
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

	local function now()
		if type(GetTime) == "function" then
			return GetTime()
		end
		return true
	end

	local function ensureExt(key)
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
		-- Map readyKey to registry entry, best-effort:
		-- "EXT:UI" -> EXT["UI"], "MOD:CharInfo" -> MOD["CharInfo"]
		if type(readyKey) ~= "string" then return end
		local prefix, key = readyKey:match("^([^:]+):(.+)$")
		if not prefix or not key then return end

		if prefix == "EXT" then
			local e = ensureExt(key)
			e.state = e.state or {}
			e.state.READY = true
			e.state.READY_AT = now()
		elseif prefix == "MOD" then
			local m = ensureMod(key)
			m.state = m.state or {}
			m.state.READY = true
			m.state.READY_AT = now()
		end
	end

	-- ###########################################################################
	-- #	PUBLIC: META REGISTRATION
	-- ###########################################################################

	function GMS:RegisterExtension(meta)
		if type(meta) ~= "table" then return end
		local key = tostring(meta.key or meta.name or "")
		if key == "" then return end

		local entry = ensureExt(key)
		entry.key = key
		entry.name = meta.name or key
		entry.displayName = meta.displayName or entry.name
		entry.version = meta.version or entry.version or 1
		entry.desc = meta.desc
		entry.author = meta.author
		entry.readyKey = meta.readyKey or entry.readyKey or ("EXT:" .. key)
		entry.state = entry.state or { READY = false }

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
		entry.readyKey = (meta and meta.readyKey) or entry.readyKey or ("MOD:" .. key)
		entry.state = entry.state or { READY = false, ENABLED = false }

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
		if GMS._READY[key] then
			return -- already ready; no double-fire
		end

		GMS._READY[key] = true
		updateRegistryState(key)

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

			-- Always register module meta once created (minimal defaults)
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
			end

			local oEnable = m.OnEnable
			m.OnEnable = function(mod, ...)
				if type(oEnable) == "function" then oEnable(mod, ...) end
				addon:SetReady(rkReady)
				-- mark enabled (registry best-effort)
				local e = GMS.REGISTRY and GMS.REGISTRY.MOD and GMS.REGISTRY.MOD[key]
				if e and e.state then
					e.state.ENABLED = true
					e.state.ENABLED_AT = now()
				end
			end

			return m
		end
	end
