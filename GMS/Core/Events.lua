	-- ============================================================================
	--	GMS/Core/Events.lua
	--	CORE MODULE: EVENTS
	--	- Zentraler Event-Router (WoW Events) für GMS
	--	- Module können Handler registrieren: Register(event, owner, fnName)
	--	- Keine direkte Event-Registrierung in Feature-Modulen nötig
	--	- Keine LoadErrors (harte Guards)
	-- ============================================================================
	
	local _G = _G
	local GMS = _G.GMS
	if not GMS then return end
	
	-- ###########################################################################
	-- #	CONSTANTS / META
	-- ###########################################################################
	
	local MODULE_NAME = "EVENTS"
	local DISPLAY_NAME = "Event Router"
	
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
	--	Normalisiert Event-Name
	--
	--	@param eventName any
	--	@return string|nil
	-- ---------------------------------------------------------------------------
	local function INTERNAL_NormalizeEventName(eventName)
		if type(eventName) ~= "string" or eventName == "" then
			return nil
		end
		return tostring(eventName)
	end
	
	-- ---------------------------------------------------------------------------
	--	Sicherer Funktionszugriff: owner[fnName]
	--
	--	@param owner table
	--	@param fnName string
	--	@return function|nil
	-- ---------------------------------------------------------------------------
	local function INTERNAL_GetHandlerFunction(owner, fnName)
		if type(owner) ~= "table" then
			return nil
		end
		if type(fnName) ~= "string" or fnName == "" then
			return nil
		end
		local fn = owner[fnName]
		if type(fn) ~= "function" then
			return nil
		end
		return fn
	end
	
	-- ###########################################################################
	-- #	NAMESPACE (auch ohne Ace verfügbar)
	-- ###########################################################################
	
	GMS[MODULE_NAME] = GMS[MODULE_NAME] or {}
	GMS.EVENTS = GMS[MODULE_NAME]
	local Events = GMS.EVENTS
	
	Events.MODULE_NAME = MODULE_NAME
	Events.DISPLAY_NAME = DISPLAY_NAME
	
	-- ###########################################################################
	-- #	STATE
	-- ###########################################################################
	
	-- handlers[eventName] = { { owner=table, fnName="EVENT_X", priority=number } ... }
	Events.INTERNAL_HANDLERS = Events.INTERNAL_HANDLERS or {}
	
	-- ###########################################################################
	-- #	PUBLIC API
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Registriert einen Handler für ein Event.
	--	owner ist typischerweise ein Modul-Table, fnName ist der Method-Name.
	--	priority: höher = früher ausgeführt
	--
	--	@param eventName string
	--	@param owner table
	--	@param fnName string
	--	@param opts table|nil { priority=number }
	--	@return boolean success
	-- ---------------------------------------------------------------------------
	function Events:Register(eventName, owner, fnName, opts)
		local evt = INTERNAL_NormalizeEventName(eventName)
		if not evt then
			LOG("ERROR", "Register: eventName ungültig.", { eventName = eventName })
			return false
		end
		if type(owner) ~= "table" then
			LOG("ERROR", "Register: owner ist keine Tabelle.", { event = evt })
			return false
		end
		if type(fnName) ~= "string" or fnName == "" then
			LOG("ERROR", "Register: fnName ungültig.", { event = evt })
			return false
		end
	
		local priority = 0
		if type(opts) == "table" and type(opts.priority) == "number" then
			priority = opts.priority
		end
	
		self.INTERNAL_HANDLERS[evt] = self.INTERNAL_HANDLERS[evt] or {}
		local list = self.INTERNAL_HANDLERS[evt]
		list[#list + 1] = { owner = owner, fnName = fnName, priority = priority }
	
		-- sort: high priority first
		table.sort(list, function(a, b)
			return (a.priority or 0) > (b.priority or 0)
		end)
	
		-- wenn AceEvent verfügbar, event bei Ace registrieren
		if self.RegisterEvent and type(self.RegisterEvent) == "function" then
			self:RegisterEvent(evt, "INTERNAL_DispatchEvent")
		end
	
		LOG("DEBUG", "Event-Handler registriert.", { event = evt, fn = fnName, priority = priority })
		return true
	end
	
	-- ---------------------------------------------------------------------------
	--	Unregister: entfernt alle Handler eines owners für eventName
	--
	--	@param eventName string
	--	@param owner table
	--	@return number removedCount
	-- ---------------------------------------------------------------------------
	function Events:Unregister(eventName, owner)
		local evt = INTERNAL_NormalizeEventName(eventName)
		if not evt then
			return 0
		end
		if type(owner) ~= "table" then
			return 0
		end
	
		local list = self.INTERNAL_HANDLERS[evt]
		if type(list) ~= "table" or #list == 0 then
			return 0
		end
	
		local kept = {}
		local removed = 0
	
		for i = 1, #list do
			local entry = list[i]
			if entry and entry.owner == owner then
				removed = removed + 1
			else
				kept[#kept + 1] = entry
			end
		end
	
		self.INTERNAL_HANDLERS[evt] = kept
	
		LOG("DEBUG", "Event-Handler unregistriert.", { event = evt, removed = removed })
		return removed
	end
	
	-- ---------------------------------------------------------------------------
	--	Dispatch: ruft alle registrierten Handler für evt auf
	--
	--	@param eventName string
	--	@param ... any
	--	@return nil
	-- ---------------------------------------------------------------------------
	function Events:INTERNAL_DispatchEvent(eventName, ...)
		local evt = INTERNAL_NormalizeEventName(eventName)
		if not evt then
			return
		end
	
		local list = self.INTERNAL_HANDLERS[evt]
		if type(list) ~= "table" or #list == 0 then
			return
		end
	
		for i = 1, #list do
			local entry = list[i]
			if entry and type(entry.owner) == "table" and type(entry.fnName) == "string" then
				local fn = INTERNAL_GetHandlerFunction(entry.owner, entry.fnName)
				if fn then
					local ok, err = pcall(fn, entry.owner, evt, ...)
					if not ok then
						LOG("ERROR", "Event-Handler Fehler.", {
							event = evt,
							fn = entry.fnName,
							error = err,
						})
					end
				else
					LOG("WARN", "Event-Handler Funktion fehlt.", {
						event = evt,
						fn = entry.fnName,
					})
				end
			end
		end
	end
	
	-- ###########################################################################
	-- #	ACE INTEGRATION (optional)
	-- ###########################################################################
	
	-- Wenn AceAddon verfügbar ist, als AceEvent-Modul einhängen.
	if GMS.Addon and type(GMS.Addon.NewModule) == "function" then
		local Addon = GMS.Addon
	
		local AceModule = Addon:NewModule(
			MODULE_NAME,
			"AceEvent-3.0",
			"AceConsole-3.0"
		)
	
		GMS[MODULE_NAME] = AceModule
		GMS.EVENTS = AceModule
	
		AceModule.MODULE_NAME = MODULE_NAME
		AceModule.DISPLAY_NAME = DISPLAY_NAME
	
		-- Re-export API + State
		AceModule.INTERNAL_HANDLERS = Events.INTERNAL_HANDLERS
		AceModule.Register = Events.Register
		AceModule.Unregister = Events.Unregister
		AceModule.INTERNAL_DispatchEvent = Events.INTERNAL_DispatchEvent
	
		-- -----------------------------------------------------------------------
		--	Ace Lifecycle: OnInitialize
		--
		--	@return nil
		-- -----------------------------------------------------------------------
		function AceModule:OnInitialize()
			LOG("INFO", "EVENTS Ace-Modul initialisiert.", nil)
	
			-- Standard-Events, die Core typischerweise braucht:
			self:RegisterEvent("ADDON_LOADED", "INTERNAL_DispatchEvent")
			self:RegisterEvent("PLAYER_LOGIN", "INTERNAL_DispatchEvent")
		end
	
		-- -----------------------------------------------------------------------
		--	Ace Lifecycle: OnEnable
		--
		--	@return nil
		-- -----------------------------------------------------------------------
		function AceModule:OnEnable()
			LOG("DEBUG", "EVENTS Ace-Modul enabled.", nil)
		end
	end
	
	-- ###########################################################################
	-- #	CORE WIRING (optional, wenn AddonLoader existiert)
	-- ###########################################################################
	
	-- Falls der AddonLoader vorhanden ist, verbinden wir ADDON_LOADED -> Queue Flush.
	if GMS.ADDONLOADER and type(GMS.ADDONLOADER.EVENT_OnAddonLoaded) == "function" then
		Events:Register("ADDON_LOADED", GMS.ADDONLOADER, "EVENT_OnAddonLoaded", { priority = 100 })
	end
	
	LOG("DEBUG", "Core EVENTS geladen.", nil)
