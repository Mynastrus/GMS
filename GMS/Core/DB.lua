	-- ============================================================================
	--	GMS/Core/DB.lua
	--	CORE MODULE: DB
	--	- Zentrale Datenhaltung (AceDB-3.0)
	--	- Module registrieren Defaults + Options via RegisterModule(...)
	--	- Versions-/Migrations-Placeholder (später ausbauen)
	--	- Keine LoadErrors (harte Guards)
	-- ============================================================================
	
	local _G = _G
	local GMS = _G.GMS
	if not GMS then return end
	
	-- ###########################################################################
	-- #	CONSTANTS / META
	-- ###########################################################################
	
	local MODULE_NAME = "DB"
	local DISPLAY_NAME = "Database"
	
	local DB = nil
	
	-- ###########################################################################
	-- #	HELPERS
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Loggt über den globalen Standard-Logger
	--
	--	@param level string
	--	@param message string
	--	@param context table|nil
	--	@return nil
	-- ---------------------------------------------------------------------------
	local function LOG(level, message, context)
		if type(_G.LOG) == "function" then
			_G.LOG(level, "GMS", MODULE_NAME, message, context)
		end
	end
	
	-- ---------------------------------------------------------------------------
	--	Safe LibStub
	--
	--	@param libName string
	--	@return any|nil
	-- ---------------------------------------------------------------------------
	local function INTERNAL_LibStubSafe(libName)
		if type(_G.LibStub) ~= "function" then
			return nil
		end
		return _G.LibStub(tostring(libName), true)
	end
	
	-- ---------------------------------------------------------------------------
	--	Ensures that the root saved variable table exists
	--
	--	@return table
	-- ---------------------------------------------------------------------------
	local function INTERNAL_EnsureSavedVariableRootExists()
		_G.GMS_DB = _G.GMS_DB or {}
		return _G.GMS_DB
	end
	
	-- ###########################################################################
	-- #	NAMESPACE (auch ohne Ace verfügbar)
	-- ###########################################################################
	
	GMS[MODULE_NAME] = GMS[MODULE_NAME] or {}
	GMS.DB = GMS[MODULE_NAME]
	DB = GMS.DB
	
	DB.MODULE_NAME = MODULE_NAME
	DB.DISPLAY_NAME = DISPLAY_NAME
	
	-- ###########################################################################
	-- #	STATE
	-- ###########################################################################
	
	DB.INTERNAL_MODULE_REGISTRY = DB.INTERNAL_MODULE_REGISTRY or {}
	DB.INTERNAL_DEFAULTS_BY_MODULE = DB.INTERNAL_DEFAULTS_BY_MODULE or {}
	DB.INTERNAL_OPTIONS_FNS_BY_MODULE = DB.INTERNAL_OPTIONS_FNS_BY_MODULE or {}
	
	DB.INTERNAL_ACE_DB = DB.INTERNAL_ACE_DB or nil
	DB.INTERNAL_ACE_DB_NAME = "GMS_DB"
	DB.INTERNAL_ACE_DB_DEFAULTS = DB.INTERNAL_ACE_DB_DEFAULTS or nil
	
	-- ###########################################################################
	-- #	PUBLIC API (Registrierung)
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Registriert ein Modul in der DB. Speichert Defaults + Options-Fn.
	--	Wird typischerweise im Modul-Load (Datei-Load) oder OnInitialize aufgerufen.
	--
	--	@param moduleName string
	--	@param defaults table
	--	@param optionsFn function|nil
	--	@return boolean success
	-- ---------------------------------------------------------------------------
	function DB:RegisterModule(moduleName, defaults, optionsFn)
		if type(moduleName) ~= "string" or moduleName == "" then
			LOG("ERROR", "RegisterModule: moduleName ungültig.", { moduleName = moduleName })
			return false
		end
		if type(defaults) ~= "table" then
			LOG("ERROR", "RegisterModule: defaults ist keine Tabelle.", { moduleName = moduleName })
			return false
		end
		if optionsFn ~= nil and type(optionsFn) ~= "function" then
			LOG("ERROR", "RegisterModule: optionsFn ist keine Funktion.", { moduleName = moduleName })
			return false
		end
	
		local name = tostring(moduleName):upper()
	
		self.INTERNAL_MODULE_REGISTRY[name] = true
		self.INTERNAL_DEFAULTS_BY_MODULE[name] = defaults
		self.INTERNAL_OPTIONS_FNS_BY_MODULE[name] = optionsFn
	
		LOG("DEBUG", "DB:RegisterModule registriert.", { module = name })
		return true
	end
	
	-- ---------------------------------------------------------------------------
	--	Gibt die registrierten Defaults eines Moduls zurück
	--
	--	@param moduleName string
	--	@return table|nil
	-- ---------------------------------------------------------------------------
	function DB:API_GetRegisteredDefaults(moduleName)
		if type(moduleName) ~= "string" or moduleName == "" then
			return nil
		end
		return self.INTERNAL_DEFAULTS_BY_MODULE[tostring(moduleName):upper()]
	end
	
	-- ---------------------------------------------------------------------------
	--	Gibt die registrierte Options-Funktion eines Moduls zurück
	--
	--	@param moduleName string
	--	@return function|nil
	-- ---------------------------------------------------------------------------
	function DB:API_GetRegisteredOptionsFunction(moduleName)
		if type(moduleName) ~= "string" or moduleName == "" then
			return nil
		end
		return self.INTERNAL_OPTIONS_FNS_BY_MODULE[tostring(moduleName):upper()]
	end
	
	-- ###########################################################################
	-- #	PUBLIC API (AceDB Zugriff)
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Gibt die AceDB-Instanz zurück (oder nil, wenn AceDB nicht verfügbar/initialisiert)
	--
	--	@return table|nil
	-- ---------------------------------------------------------------------------
	function DB:API_GetAceDB()
		return self.INTERNAL_ACE_DB
	end
	
	-- ---------------------------------------------------------------------------
	--	Gibt Profile-DB eines Moduls zurück (Namespace im Profil)
	--	- Requires AceDB initialized
	--
	--	@param moduleName string
	--	@return table|nil
	-- ---------------------------------------------------------------------------
	function DB:DB_GetProfileNamespace(moduleName)
		if not self.INTERNAL_ACE_DB then
			return nil
		end
		if type(moduleName) ~= "string" or moduleName == "" then
			return nil
		end
	
		local name = tostring(moduleName):upper()
		local profile = self.INTERNAL_ACE_DB.profile
		if type(profile) ~= "table" then
			return nil
		end
	
		profile[name] = profile[name] or {}
		return profile[name]
	end
	
	-- ---------------------------------------------------------------------------
	--	Gibt Global-DB eines Moduls zurück (Namespace global)
	--	- Requires AceDB initialized
	--
	--	@param moduleName string
	--	@return table|nil
	-- ---------------------------------------------------------------------------
	function DB:DB_GetGlobalNamespace(moduleName)
		if not self.INTERNAL_ACE_DB then
			return nil
		end
		if type(moduleName) ~= "string" or moduleName == "" then
			return nil
		end
	
		local name = tostring(moduleName):upper()
		local global = self.INTERNAL_ACE_DB.global
		if type(global) ~= "table" then
			return nil
		end
	
		global[name] = global[name] or {}
		return global[name]
	end
	
	-- ###########################################################################
	-- #	INTERNAL: Defaults sammeln + AceDB initialisieren
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Baut die Root-Defaults-Struktur für AceDB aus allen registrierten Modulen.
	--
	--	@return table
	-- ---------------------------------------------------------------------------
	function DB:INTERNAL_BuildAceDBDefaults()
		local defaults = {
			profile = {},
			global = {},
		}
	
		for moduleName, moduleDefaults in pairs(self.INTERNAL_DEFAULTS_BY_MODULE) do
			if type(moduleDefaults) == "table" then
				-- Standard: Module defaults werden unter profile[MODULE] abgelegt.
				-- (kann später erweitert werden: global/char/guild etc.)
				defaults.profile[moduleName] = moduleDefaults
			end
		end
	
		self.INTERNAL_ACE_DB_DEFAULTS = defaults
		return defaults
	end
	
	-- ---------------------------------------------------------------------------
	--	Initialisiert AceDB (wenn verfügbar). Idempotent.
	--
	--	@return boolean success
	-- ---------------------------------------------------------------------------
	function DB:INTERNAL_InitializeAceDBIfPossible()
		if self.INTERNAL_ACE_DB then
			return true
		end
	
		INTERNAL_EnsureSavedVariableRootExists()
	
		local AceDB = INTERNAL_LibStubSafe("AceDB-3.0")
		if not AceDB then
			LOG("WARN", "AceDB-3.0 nicht verfügbar – DB läuft im Guard-Mode.", nil)
			return false
		end
	
		local defaults = self:INTERNAL_BuildAceDBDefaults()
	
		local ok, dbOrError = pcall(AceDB.New, AceDB, self.INTERNAL_ACE_DB_NAME, defaults, true)
		if not ok then
			LOG("ERROR", "AceDB.New fehlgeschlagen.", { error = dbOrError })
			return false
		end
	
		self.INTERNAL_ACE_DB = dbOrError
	
		LOG("INFO", "AceDB initialisiert.", {
			savedVariable = self.INTERNAL_ACE_DB_NAME,
			registeredModules = (self.INTERNAL_MODULE_REGISTRY and true) or false,
		})
	
		return true
	end
	
	-- ###########################################################################
	-- #	ACE INTEGRATION (optional)
	-- ###########################################################################
	
	-- Falls AceAddon verfügbar ist, als Ace-Modul einhängen (DB Lifecycle).
	if GMS.Addon and type(GMS.Addon.NewModule) == "function" then
		local Addon = GMS.Addon
	
		local AceModule = Addon:NewModule(
			MODULE_NAME,
			"AceEvent-3.0",
			"AceConsole-3.0"
		)
	
		GMS[MODULE_NAME] = AceModule
		GMS.DB = AceModule
	
		AceModule.MODULE_NAME = MODULE_NAME
		AceModule.DISPLAY_NAME = DISPLAY_NAME
	
		-- Re-export API
		AceModule.RegisterModule = DB.RegisterModule
		AceModule.API_GetRegisteredDefaults = DB.API_GetRegisteredDefaults
		AceModule.API_GetRegisteredOptionsFunction = DB.API_GetRegisteredOptionsFunction
		AceModule.API_GetAceDB = DB.API_GetAceDB
		AceModule.DB_GetProfileNamespace = DB.DB_GetProfileNamespace
		AceModule.DB_GetGlobalNamespace = DB.DB_GetGlobalNamespace
		AceModule.INTERNAL_BuildAceDBDefaults = DB.INTERNAL_BuildAceDBDefaults
		AceModule.INTERNAL_InitializeAceDBIfPossible = DB.INTERNAL_InitializeAceDBIfPossible
	
		-- -----------------------------------------------------------------------
		--	Ace Lifecycle: OnInitialize
		--
		--	@return nil
		-- -----------------------------------------------------------------------
		function AceModule:OnInitialize()
			self:INTERNAL_InitializeAceDBIfPossible()
		end
	
		-- -----------------------------------------------------------------------
		--	Ace Lifecycle: OnEnable
		--
		--	@return nil
		-- -----------------------------------------------------------------------
		function AceModule:OnEnable()
			LOG("DEBUG", "DB Ace-Modul enabled.", nil)
		end
	end
	
	LOG("DEBUG", "Core DB geladen.", nil)
