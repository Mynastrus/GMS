	-- ============================================================================
	--	GMS/Core/Database.lua
	--	Database EXTENSION
	--	- Registers standard SavedVariables via AceDB-3.0
	-- ============================================================================

	local _G = _G

	-- ---------------------------------------------------------------------------
	--	Guards
	-- ---------------------------------------------------------------------------

	local LibStub = _G.LibStub
	if not LibStub then return end

	local AceDB = LibStub("AceDB-3.0", true)
	if not AceDB then
		return
	end

	local GMS = _G.GMS
	if not GMS then
		local AceAddon = LibStub("AceAddon-3.0", true)
		if AceAddon then
			GMS = AceAddon:GetAddon("GMS", true)
		end
	end
	if not GMS then return end

	-- ###########################################################################
	-- #	LOG BUFFER + LOCAL LOGGER
	-- ###########################################################################

	GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

	local function now()
		return GetTime and GetTime() or nil
	end

	-- Local-only logger for this file
	local function LOCAL_LOG(level, source, msg, ...)
		local entry = {
			time   = now(),
			level  = tostring(level or "INFO"),
			source = tostring(source or "DB"),
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

	-- ###########################################################################
	-- #	ModuleStates REGISTRATION
	-- ###########################################################################

	if type(GMS.RegisterExtension) == "function" then
		GMS:RegisterExtension({
			key = "DB",
			name = "Database",
			displayName = "Database",
			version = 1,
			desc = "AceDB-based SavedVariables and module namespaces",
		})
	end

	-- ###########################################################################
	-- #	DEFAULTS
	-- ###########################################################################

	local DB_DEFAULTS = GMS.DEFAULTS or {
		profile = { debug = false },
		global  = { version = 1 },
	}

	local LOGGING_DEFAULTS = {
		profile = {},
		global  = { logs = {} },
	}

	-- ###########################################################################
	-- #	STANDARD DATABASE INIT
	-- ###########################################################################

	function GMS:InitializeStandardDatabases(force)
		if not AceDB then
			LOCAL_LOG("WARN", "DB", "AceDB-3.0 not available")
			return false
		end

		if self.db and self.logging_db and not force then
			return true
		end

		self.db = self.db or AceDB:New("GMS_DB", DB_DEFAULTS, true)
		self.logging_db = self.logging_db or AceDB:New("GMS_Logging_DB", LOGGING_DEFAULTS, true)

		LOCAL_LOG("INFO", "DB", "Standard databases initialized")
		return true
	end

	-- Early init attempt (harmless if Core runs it again later)
	pcall(function()
		if type(GMS.InitializeStandardDatabases) == "function" then
			GMS:InitializeStandardDatabases(false)
		end
	end)

	-- ###########################################################################
	-- #	GMS.DB HELPER API
	-- ###########################################################################

	GMS.DB = GMS.DB or {}
	GMS.DB._parent = GMS

	function GMS.DB:RegisterModule(moduleName, defaults, optionsProvider)
		if not moduleName or not self._parent.db then
			return nil
		end

		local ok, ns = pcall(function()
			return self._parent.db:RegisterNamespace(moduleName, defaults)
		end)

		if ok and ns then
			self._modules = self._modules or {}
			self._modules[moduleName] = ns

			if type(optionsProvider) == "function" then
				pcall(optionsProvider)
			end

			LOCAL_LOG("DEBUG", "DB", "Registered module DB", moduleName)
			return ns
		end

		return nil
	end

	function GMS.DB:GetModuleDB(moduleName)
		if not moduleName then return nil end
		self._modules = self._modules or {}

		if self._modules[moduleName] then
			return self._modules[moduleName]
		end

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

	-- ###########################################################################
	-- #	READY
	-- ###########################################################################

	if type(GMS.SetReady) == "function" then
		GMS:SetReady("EXT:DB")
	end

	LOCAL_LOG("INFO", "DB", "Database extension loaded")
