	-- ============================================================================
	--	GMS/Core/AddonLoader.lua
	--	CORE MODULE: ADDONLOADER
	--	- Kontrolliertes Nachladen optionaler AddOns via C_AddOns.*
	--	- Keine Schleifen/Busy-Waits (nur event-/call-basiert)
	--	- Keine LoadErrors (harte Guards)
	-- ============================================================================
	
	local _G = _G
	local GMS = _G.GMS
	if not GMS then return end
	
	-- ###########################################################################
	-- #	CONSTANTS / META
	-- ###########################################################################
	
	local MODULE_NAME = "ADDONLOADER"
	local DISPLAY_NAME = "AddOn Loader"
	
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
	--	Prüft modern, ob C_AddOns API verfügbar ist
	--
	--	@return boolean
	-- ---------------------------------------------------------------------------
	local function INTERNAL_HasModernAddonAPI()
		return (type(_G.C_AddOns) == "table"
			and type(_G.C_AddOns.IsAddOnLoaded) == "function"
			and type(_G.C_AddOns.LoadAddOn) == "function")
	end
	
	-- ---------------------------------------------------------------------------
	--	Normalisiert AddonName
	--
	--	@param addonName any
	--	@return string|nil
	-- ---------------------------------------------------------------------------
	local function INTERNAL_NormalizeAddonName(addonName)
		if type(addonName) ~= "string" or addonName == "" then
			return nil
		end
		return addonName
	end
	
	-- ###########################################################################
	-- #	NAMESPACE (auch ohne Ace verfügbar)
	-- ###########################################################################
	
	GMS[MODULE_NAME] = GMS[MODULE_NAME] or {}
	GMS.ADDONLOADER = GMS[MODULE_NAME]
	local Loader = GMS.ADDONLOADER
	
	Loader.MODULE_NAME = MODULE_NAME
	Loader.DISPLAY_NAME = DISPLAY_NAME
	
	-- ###########################################################################
	-- #	STATE
	-- ###########################################################################
	
	Loader.INTERNAL_PENDING_QUEUE = Loader.INTERNAL_PENDING_QUEUE or {}
	Loader.INTERNAL_LAST_LOAD_RESULT = Loader.INTERNAL_LAST_LOAD_RESULT or {}
	
	-- ###########################################################################
	-- #	PUBLIC API
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Prüft, ob AddOn geladen ist
	--
	--	@param addonName string
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function Loader:API_IsAddOnLoaded(addonName)
		local name = INTERNAL_NormalizeAddonName(addonName)
		if not name then
			return false
		end
	
		if GMS.IsAddOnLoaded then
			return (GMS:IsAddOnLoaded(name) == true)
		end
	
		if INTERNAL_HasModernAddonAPI() then
			return (_G.C_AddOns.IsAddOnLoaded(name) == true)
		end
	
		return false
	end
	
	-- ---------------------------------------------------------------------------
	--	Versucht ein AddOn zu laden (einmalig, keine Loops)
	--
	--	@param addonName string
	--	@return boolean success
	--	@return string|nil reason
	-- ---------------------------------------------------------------------------
	function Loader:API_TryLoadAddOn(addonName)
		local name = INTERNAL_NormalizeAddonName(addonName)
		if not name then
			return false, "invalid addonName"
		end
	
		if self:API_IsAddOnLoaded(name) then
			self.INTERNAL_LAST_LOAD_RESULT[name] = { ok = true, reason = "already_loaded" }
			return true, nil
		end
	
		if GMS.TryLoadAddOn then
			local ok, reason = GMS:TryLoadAddOn(name)
			self.INTERNAL_LAST_LOAD_RESULT[name] = { ok = ok, reason = reason }
			if ok then
				LOG("INFO", "AddOn geladen.", { addon = name })
				return true, nil
			end
			LOG("WARN", "AddOn konnte nicht geladen werden.", { addon = name, reason = reason })
			return false, reason
		end
	
		if not INTERNAL_HasModernAddonAPI() then
			self.INTERNAL_LAST_LOAD_RESULT[name] = { ok = false, reason = "no_c_addons_api" }
			return false, "C_AddOns API nicht verfügbar"
		end
	
		local ok, loadedOrReason = _G.C_AddOns.LoadAddOn(name)
		self.INTERNAL_LAST_LOAD_RESULT[name] = { ok = ok, reason = loadedOrReason }
	
		if ok then
			LOG("INFO", "AddOn geladen.", { addon = name })
			return true, nil
		end
	
		local reason = tostring(loadedOrReason or "unknown")
		LOG("WARN", "AddOn konnte nicht geladen werden.", { addon = name, reason = reason })
		return false, reason
	end
	
	-- ---------------------------------------------------------------------------
	--	Queue-Mechanik: merkt sich eine Aktion, die erst nach AddOn-Load laufen soll.
	--	Diese Funktion macht KEIN busy waiting. Sie führt den Callback sofort aus,
	--	wenn AddOn bereits geladen ist, ansonsten queued sie und erwartet später
	--	einen OnAddonLoaded Trigger (z.B. über Events-Modul).
	--
	--	@param addonName string
	--	@param callbackFn function
	--	@param context table|nil
	--	@return boolean queuedOrExecuted
	-- ---------------------------------------------------------------------------
	function Loader:API_RunWhenAddOnLoaded(addonName, callbackFn, context)
		local name = INTERNAL_NormalizeAddonName(addonName)
		if not name then
			return false
		end
		if type(callbackFn) ~= "function" then
			return false
		end
	
		if self:API_IsAddOnLoaded(name) then
			local ok, err = pcall(callbackFn, context)
			if not ok then
				LOG("ERROR", "Callback nach AddOn-Load ist fehlgeschlagen.", { addon = name, error = err })
			end
			return true
		end
	
		self.INTERNAL_PENDING_QUEUE[name] = self.INTERNAL_PENDING_QUEUE[name] or {}
		self.INTERNAL_PENDING_QUEUE[name][#self.INTERNAL_PENDING_QUEUE[name] + 1] = {
			fn = callbackFn,
			ctx = context,
		}
	
		LOG("DEBUG", "Callback queued bis AddOn geladen ist.", { addon = name })
		return true
	end
	
	-- ---------------------------------------------------------------------------
	--	Trigger für ADDON_LOADED: führt queued callbacks aus.
	--	Diese Funktion soll von einem Event-Dispatcher aufgerufen werden.
	--
	--	@param addonName string
	--	@return number executedCount
	-- ---------------------------------------------------------------------------
	function Loader:EVENT_OnAddonLoaded(addonName)
		local name = INTERNAL_NormalizeAddonName(addonName)
		if not name then
			return 0
		end
	
		local queue = self.INTERNAL_PENDING_QUEUE[name]
		if type(queue) ~= "table" or #queue == 0 then
			return 0
		end
	
		self.INTERNAL_PENDING_QUEUE[name] = {}
	
		local executed = 0
		for i = 1, #queue do
			local entry = queue[i]
			if entry and type(entry.fn) == "function" then
				local ok, err = pcall(entry.fn, entry.ctx)
				if not ok then
					LOG("ERROR", "Queued Callback fehlgeschlagen.", { addon = name, error = err })
				else
					executed = executed + 1
				end
			end
		end
	
		LOG("INFO", "Queued Callbacks ausgeführt.", { addon = name, count = executed })
		return executed
	end
	
	-- ---------------------------------------------------------------------------
	--	Gibt das letzte Load-Ergebnis für ein AddOn zurück
	--
	--	@param addonName string
	--	@return table|nil
	-- ---------------------------------------------------------------------------
	function Loader:API_GetLastLoadResult(addonName)
		local name = INTERNAL_NormalizeAddonName(addonName)
		if not name then
			return nil
		end
		return self.INTERNAL_LAST_LOAD_RESULT[name]
	end
	
	LOG("DEBUG", "ADDONLOADER geladen.", { hasCAddOns = INTERNAL_HasModernAddonAPI() })
