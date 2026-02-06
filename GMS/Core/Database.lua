	-- ============================================================================
	--	GMS/Core/Database.lua
	--	Registriert Standard-SavedVariables via AceDB-3.0
	-- ============================================================================

	local ADDON_NAME = ...
	local _G = _G

	local LibStub = _G.LibStub
	if not LibStub then return end

	local AceDB = LibStub("AceDB-3.0", true)
	if not AceDB then
		if _G.GMS and type(_G.GMS.LOG_Warn) == "function" then
			_G.GMS:LOG_Warn("DB", "AceDB-3.0 not available; skipping DB init", nil)
		end
		return
	end

	local GMS = _G.GMS
	if not GMS then
		local AceAddon = LibStub("AceAddon-3.0", true)
		if AceAddon then
			GMS = AceAddon:GetAddon("GMS", true)
		end
	end

	if not GMS then
		-- If GMS is not available, nothing sensible to attach to.
		return
	end

	-- Fallback defaults (Core may override these earlier)
	local DB_DEFAULTS = GMS.DEFAULTS or {
		profile = {
			debug = false,
		},
		global = {
			version = 1,
		},
	}

	local LOGGING_DEFAULTS = {
		profile = {},
		global = {
			logs = {},
		},
	}

	function GMS:InitializeStandardDatabases(force)
		if not AceDB then
			self:LOG_Warn("DB", "AceDB-3.0 not available", nil)
			return false
		end

		if self.db and self.logging_db and not force then
			return true
		end

		-- Create / bind SavedVariables via AceDB
		self.db = self.db or AceDB:New("GMS_DB", DB_DEFAULTS, true)
		self.logging_db = self.logging_db or AceDB:New("GMS_Logging_DB", LOGGING_DEFAULTS, true)

		self:LOG_Info("DB", "Standard databases initialized", nil)
		return true
	end

	-- Versuchen, beim File-Load die DBs zu initialisieren (harmless, falls Core später erneut init)
	if type(GMS.InitializeStandardDatabases) == "function" then
		_G.GMS = GMS
		GMS:InitializeStandardDatabases(false)
	end

	-- ============================================================================
	--	GMS.DB helper API
	--
	--	Provides a small wrapper to register per-module namespaces and retrieve them.
	-- ============================================================================

	GMS.DB = GMS.DB or {}

	-- Register a module's DB namespace. `defaults` is optional table.
	function GMS.DB:RegisterModule(moduleName, defaults, optionsProvider)
		if not moduleName then return nil end
		if not self._parent or not self._parent.db then return nil end

		local ok, ns = pcall(function()
			return self._parent.db:RegisterNamespace(moduleName, defaults)
		end)
		if ok and ns then
			self._modules = self._modules or {}
			self._modules[moduleName] = ns
			-- if optionsProvider callback provided, call it to attach options (optional)
			if type(optionsProvider) == "function" then
				pcall(optionsProvider)
			end
			return ns
		end
		return nil
	end

	function GMS.DB:GetModuleDB(moduleName)
		if not moduleName then return nil end
		self._modules = self._modules or {}
		if self._modules[moduleName] then return self._modules[moduleName] end
		if self.db then
			local ok, ns = pcall(function()
				return self.db:GetNamespace(moduleName, true)
			end)
			if ok and ns then
				self._modules[moduleName] = ns
				return ns
			end
		end
		return nil
	end

	-- attach parent references for convenience
	GMS.DB._parent = GMS


	-- Notify that Database core finished loading
	pcall(function()
		if GMS and type(GMS.Print) == "function" then
			GMS:Print("Database wurde geladen")
		end
	end)

