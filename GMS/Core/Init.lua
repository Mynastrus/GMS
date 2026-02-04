	-- ============================================================================
	--	GMS/Core/Init.lua
	--	CORE MODULE: INIT
	--	- Frühe, sichere Initialisierung (ohne LoadErrors)
	--	- Hängt sich an GMS.Addon (AceAddon) an, wenn verfügbar
	--	- Stellt Core-Flags/States bereit
	-- ============================================================================
	
	local _G = _G
	local GMS = _G.GMS
	if not GMS then return end
	
	-- ###########################################################################
	-- #	CONSTANTS / META
	-- ###########################################################################
	
	local MODULE_NAME = "INIT"
	local DISPLAY_NAME = "Core Initialization"
	
	GMS.INIT = GMS.INIT or {}
	local INIT = GMS.INIT
	
	INIT.MODULE_NAME = MODULE_NAME
	INIT.DISPLAY_NAME = DISPLAY_NAME
	
	-- ###########################################################################
	-- #	LOCAL STATE
	-- ###########################################################################
	
	local INTERNAL_HAS_INITIALIZED = false
	local INTERNAL_HAS_ENABLED = false
	
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
	--	Markiert den Init-Status zentral im Namespace
	--
	--	@param key string
	--	@param value any
	--	@return nil
	-- ---------------------------------------------------------------------------
	local function INTERNAL_SetStateFlag(key, value)
		if type(GMS.STATE) ~= "table" then
			GMS.STATE = {}
		end
		GMS.STATE[tostring(key)] = value
	end
	
	-- ###########################################################################
	-- #	PUBLIC API (Namespace-Level)
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Gibt zurück, ob INIT bereits initialisiert wurde
	--
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function INIT:API_HasInitialized()
		return INTERNAL_HAS_INITIALIZED
	end
	
	-- ---------------------------------------------------------------------------
	--	Gibt zurück, ob INIT bereits enabled wurde
	--
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function INIT:API_HasEnabled()
		return INTERNAL_HAS_ENABLED
	end
	
	-- ###########################################################################
	-- #	ACE INTEGRATION (wenn verfügbar)
	-- ###########################################################################
	
	-- Wenn AceAddon verfügbar ist, wird INIT als internes Ace-Modul registriert.
	-- Wenn nicht, bleibt die Datei „harmlos“ und verursacht keine LoadErrors.
	if not GMS.Addon or type(GMS.Addon.NewModule) ~= "function" then
		LOG("WARN", "GMS.Addon nicht verfügbar – INIT läuft im Guard-Mode (kein Ace-Modul).", nil)
		INTERNAL_SetStateFlag("INIT_GUARD_MODE", true)
		return
	end
	
	local Addon = GMS.Addon
	
	-- internes Ace-Modul (minimal)
	local Module = Addon:NewModule(
		MODULE_NAME,
		"AceEvent-3.0",
		"AceConsole-3.0"
	)
	
	GMS[MODULE_NAME] = Module
	GMS.INIT = Module
	Module.MODULE_NAME = MODULE_NAME
	Module.DISPLAY_NAME = DISPLAY_NAME
	
	-- ---------------------------------------------------------------------------
	--	Führt frühe Initialisierungen durch (idempotent)
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_PerformEarlyInitialization()
		if INTERNAL_HAS_INITIALIZED then
			return
		end
	
		INTERNAL_HAS_INITIALIZED = true
	
		if type(GMS.STATE) ~= "table" then
			GMS.STATE = {}
		end
	
		INTERNAL_SetStateFlag("INIT_INITIALIZED", true)
		INTERNAL_SetStateFlag("CORE_READY_STAGE", "initialized")
	
		LOG("INFO", "INIT: OnInitialize abgeschlossen.", {
			coreReadyStage = GMS.STATE.CORE_READY_STAGE,
		})
	end
	
	-- ---------------------------------------------------------------------------
	--	Führt Enable-Phase durch (idempotent)
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_PerformEnablePhase()
		if INTERNAL_HAS_ENABLED then
			return
		end
	
		INTERNAL_HAS_ENABLED = true
	
		INTERNAL_SetStateFlag("INIT_ENABLED", true)
		INTERNAL_SetStateFlag("CORE_READY_STAGE", "enabled")
	
		LOG("INFO", "INIT: OnEnable abgeschlossen.", {
			coreReadyStage = GMS.STATE.CORE_READY_STAGE,
		})
	end
	
	-- ---------------------------------------------------------------------------
	--	Ace Lifecycle: OnInitialize
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function Module:OnInitialize()
		self:INTERNAL_PerformEarlyInitialization()
	end
	
	-- ---------------------------------------------------------------------------
	--	Ace Lifecycle: OnEnable
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function Module:OnEnable()
		self:INTERNAL_PerformEnablePhase()
	end
