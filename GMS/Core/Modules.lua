	-- ============================================================================
	--	GMS/Core/Modules.lua
	--	CORE MODULE: MODULES
	--	- Zentrale Modulverwaltung für interne GMS-Module (Ace + Nicht-Ace)
	--	- Registry: Meta-Infos, Status, Zugriff auf DISPLAY_NAME, etc.
	--	- Standardisierte Helper für Module (DB/LOG/UI Zugriff bleibt getrennt)
	--	- Keine LoadErrors (harte Guards)
	-- ============================================================================
	
	local _G = _G
	local GMS = _G.GMS
	if not GMS then return end
	
	-- ###########################################################################
	-- #	CONSTANTS / META
	-- ###########################################################################
	
	local MODULE_NAME = "MODULES"
	local DISPLAY_NAME = "Module Registry"
	
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
	--	Normalisiert Modulnamen (UPPERCASE, string)
	--
	--	@param moduleName any
	--	@return string|nil
	-- ---------------------------------------------------------------------------
	local function INTERNAL_NormalizeModuleName(moduleName)
		if type(moduleName) ~= "string" or moduleName == "" then
			return nil
		end
		return tostring(moduleName):upper()
	end
	
	-- ###########################################################################
	-- #	NAMESPACE (auch ohne Ace verfügbar)
	-- ###########################################################################
	
	GMS[MODULE_NAME] = GMS[MODULE_NAME] or {}
	GMS.MODULES = GMS[MODULE_NAME]
	local Modules = GMS.MODULES
	
	Modules.MODULE_NAME = MODULE_NAME
	Modules.DISPLAY_NAME = DISPLAY_NAME
	
	-- ###########################################################################
	-- #	STATE / REGISTRY
	-- ###########################################################################
	
	Modules.INTERNAL_REGISTRY = Modules.INTERNAL_REGISTRY or {}
	-- INTERNAL_REGISTRY[name] = {
	--		name = "CHARINFO",
	--		displayName = "Character Info",
	--		object = <moduleRef>,
	--		isAceModule = boolean,
	--		enabled = boolean|nil,
	--		loadedAt = number|nil,
	-- }
	
	-- ###########################################################################
	-- #	PUBLIC API
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Registriert ein internes Modul in der Registry (idempotent)
	--
	--	@param moduleName string (UPPERCASE empfohlen, wird normalisiert)
	--	@param moduleObject table|nil
	--	@param displayName string|nil
	--	@param isAceModule boolean|nil
	--	@return boolean success
	-- ---------------------------------------------------------------------------
	function Modules:API_RegisterInternalModule(moduleName, moduleObject, displayName, isAceModule)
		local name = INTERNAL_NormalizeModuleName(moduleName)
		if not name then
			LOG("ERROR", "API_RegisterInternalModule: moduleName ungültig.", { moduleName = moduleName })
			return false
		end
	
		local entry = self.INTERNAL_REGISTRY[name]
		if type(entry) ~= "table" then
			entry = { name = name }
			self.INTERNAL_REGISTRY[name] = entry
		end
	
		if type(displayName) == "string" and displayName ~= "" then
			entry.displayName = displayName
		elseif type(entry.displayName) ~= "string" or entry.displayName == "" then
			entry.displayName = name
		end
	
		if type(moduleObject) == "table" then
			entry.object = moduleObject
		end
	
		if type(isAceModule) == "boolean" then
			entry.isAceModule = isAceModule
		elseif entry.isAceModule == nil then
			entry.isAceModule = false
		end
	
		entry.loadedAt = entry.loadedAt or (type(_G.time) == "function" and _G.time() or 0)
	
		LOG("DEBUG", "Modul registriert.", {
			module = name,
			displayName = entry.displayName,
			isAceModule = entry.isAceModule,
		})
	
		return true
	end
	
	-- ---------------------------------------------------------------------------
	--	Setzt Enabled-Status in der Registry (für UI/Debug)
	--
	--	@param moduleName string
	--	@param isEnabled boolean
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function Modules:API_SetModuleEnabledState(moduleName, isEnabled)
		local name = INTERNAL_NormalizeModuleName(moduleName)
		if not name then
			return false
		end
	
		local entry = self.INTERNAL_REGISTRY[name]
		if type(entry) ~= "table" then
			entry = { name = name, displayName = name }
			self.INTERNAL_REGISTRY[name] = entry
		end
	
		entry.enabled = (isEnabled == true)
		return true
	end
	
	-- ---------------------------------------------------------------------------
	--	Gibt Registry-Eintrag zurück
	--
	--	@param moduleName string
	--	@return table|nil
	-- ---------------------------------------------------------------------------
	function Modules:API_GetModuleEntry(moduleName)
		local name = INTERNAL_NormalizeModuleName(moduleName)
		if not name then
			return nil
		end
		return self.INTERNAL_REGISTRY[name]
	end
	
	-- ---------------------------------------------------------------------------
	--	Gibt Modul-Objekt zurück (falls bekannt)
	--
	--	@param moduleName string
	--	@return table|nil
	-- ---------------------------------------------------------------------------
	function Modules:API_GetModuleObject(moduleName)
		local entry = self:API_GetModuleEntry(moduleName)
		if entry and type(entry.object) == "table" then
			return entry.object
		end
		return nil
	end
	
	-- ---------------------------------------------------------------------------
	--	Listet alle registrierten Module als flaches Array von Entries
	--
	--	@return table
	-- ---------------------------------------------------------------------------
	function Modules:API_ListModules()
		local out = {}
		for _, entry in pairs(self.INTERNAL_REGISTRY) do
			out[#out + 1] = entry
		end
		return out
	end
	
	-- ###########################################################################
	-- #	ACE INTEGRATION (optional)
	-- ###########################################################################
	
	-- Falls AceAddon verfügbar ist, als Ace-Modul einhängen.
	if GMS.Addon and type(GMS.Addon.NewModule) == "function" then
		local Addon = GMS.Addon
	
		local AceModule = Addon:NewModule(
			MODULE_NAME,
			"AceEvent-3.0",
			"AceConsole-3.0"
		)
	
		GMS[MODULE_NAME] = AceModule
		GMS.MODULES = AceModule
	
		AceModule.MODULE_NAME = MODULE_NAME
		AceModule.DISPLAY_NAME = DISPLAY_NAME
	
		-- Re-export API
		AceModule.API_RegisterInternalModule = Modules.API_RegisterInternalModule
		AceModule.API_SetModuleEnabledState = Modules.API_SetModuleEnabledState
		AceModule.API_GetModuleEntry = Modules.API_GetModuleEntry
		AceModule.API_GetModuleObject = Modules.API_GetModuleObject
		AceModule.API_ListModules = Modules.API_ListModules
	
		-- -----------------------------------------------------------------------
		--	Ace Lifecycle: OnInitialize
		--
		--	@return nil
		-- -----------------------------------------------------------------------
		function AceModule:OnInitialize()
			-- Registry sich selbst eintragen
			self:API_RegisterInternalModule(MODULE_NAME, self, DISPLAY_NAME, true)
			LOG("INFO", "MODULES Ace-Modul initialisiert.", nil)
		end
	
		-- -----------------------------------------------------------------------
		--	Ace Lifecycle: OnEnable
		--
		--	@return nil
		-- -----------------------------------------------------------------------
		function AceModule:OnEnable()
			self:API_SetModuleEnabledState(MODULE_NAME, true)
			LOG("DEBUG", "MODULES Ace-Modul enabled.", nil)
		end
	
		-- -----------------------------------------------------------------------
		--	Ace Lifecycle: OnDisable
		--
		--	@return nil
		-- -----------------------------------------------------------------------
		function AceModule:OnDisable()
			self:API_SetModuleEnabledState(MODULE_NAME, false)
			LOG("DEBUG", "MODULES Ace-Modul disabled.", nil)
		end
	end
	
	LOG("DEBUG", "Core MODULES geladen.", nil)
