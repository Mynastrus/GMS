	-- ============================================================================
	-- GMS/Core/Logging.lua
	-- Zentrales Logging-Bootstrap für GMS
	-- - Stellt globale LOG(...) Funktion bereit (immer verfügbar)
	-- - Initialisiert _G.GMS_LOGGING + BUFFER (Ringbuffer)
	-- - Optionaler Sink: _G.GMS_LOGGING.Log(...) kann später gesetzt werden
	-- - Bindet Helpers an GMS (GMS:LOG_... Funktionen)
	-- ============================================================================
	
	local _G = _G
	local GMS = _G.GMS
	if not GMS then return end
	
	local MODULE_NAME = "LOGGING_BOOTSTRAP"
	
	-- ---------------------------------------------------------------------------
	-- Stellt sicher, dass _G.GMS_LOGGING existiert inkl. BUFFER
	--
	-- @return table
	-- ---------------------------------------------------------------------------
	local function INTERNAL_EnsureGlobalLoggingNamespace()
		_G.GMS_LOGGING = _G.GMS_LOGGING or {}
		_G.GMS_LOGGING.BUFFER = _G.GMS_LOGGING.BUFFER or {}
		_G.GMS_LOGGING.META = _G.GMS_LOGGING.META or {}
		return _G.GMS_LOGGING
	end
	
	-- ---------------------------------------------------------------------------
	-- Liefert eine epoch timestamp in Sekunden (mit ms Anteil, wenn verfügbar)
	--
	-- @return number
	-- ---------------------------------------------------------------------------
	local function INTERNAL_GetTimestampSeconds()
		if type(_G.GetTime) == "function" then
			return _G.GetTime()
		end
		return 0
	end
	
	-- ---------------------------------------------------------------------------
	-- Fügt einen Logeintrag in den globalen Buffer ein (ohne Ausgabe)
	--
	-- @param level string
	-- @param addonName string
	-- @param moduleName string
	-- @param message string
	-- @param context table|nil
	-- @return table entry
	-- ---------------------------------------------------------------------------
	local function INTERNAL_BufferLogEntry(level, addonName, moduleName, message, context)
		local ns = INTERNAL_EnsureGlobalLoggingNamespace()
		
		local entry = {
			t = INTERNAL_GetTimestampSeconds(),
			lvl = tostring(level or "INFO"),
			addon = tostring(addonName or "UNKNOWN"),
			mod = tostring(moduleName or "UNKNOWN"),
			msg = tostring(message or ""),
			ctx = context,
		}
		
		ns.BUFFER[#ns.BUFFER + 1] = entry
		return entry
	end
	
	-- ---------------------------------------------------------------------------
	-- Dispatcht einen Logeintrag an einen optionalen Sink, falls vorhanden
	-- Sink-Signatur (später setzbar): _G.GMS_LOGGING.Log(level, addon, module, message, context)
	--
	-- @param entry table
	-- ---------------------------------------------------------------------------
	local function INTERNAL_TryDispatchToSink(entry)
		local ns = _G.GMS_LOGGING
		if not ns then return end
		
		local sink = ns.Log
		if type(sink) ~= "function" then
			return
		end
		
		sink(entry.lvl, entry.addon, entry.mod, entry.msg, entry.ctx)
	end
	
	-- ---------------------------------------------------------------------------
	-- Globale Standard-LOG Funktion (Self-Initializing)
	-- - Schreibt immer in _G.GMS_LOGGING.BUFFER
	-- - Versucht danach an Sink zu dispatchen, wenn vorhanden
	--
	-- @param level string
	-- @param addonName string
	-- @param moduleName string
	-- @param message string
	-- @param context table|nil
	-- ---------------------------------------------------------------------------
	_G.LOG = _G.LOG or function(level, addonName, moduleName, message, context)
		local entry = INTERNAL_BufferLogEntry(level, addonName, moduleName, message, context)
		INTERNAL_TryDispatchToSink(entry)
	end
	
	-- ---------------------------------------------------------------------------
	-- Public Helper: Loggt über globales LOG(...) (konvenient für GMS)
	--
	-- @param level string
	-- @param moduleName string
	-- @param message string
	-- @param context table|nil
	-- ---------------------------------------------------------------------------
	function GMS:LOG_Write(level, moduleName, message, context)
		_G.LOG(level, "GMS", tostring(moduleName or MODULE_NAME), message, context)
	end
	
	-- ---------------------------------------------------------------------------
	-- Public Helper: Gibt Zugriff auf den globalen Buffer (read-only usage)
	--
	-- @return table
	-- ---------------------------------------------------------------------------
	function GMS:LOG_GetBuffer()
		local ns = INTERNAL_EnsureGlobalLoggingNamespace()
		return ns.BUFFER
	end
	
	-- ---------------------------------------------------------------------------
	-- Public Helper: Setzt einen Sink für Live-Ausgabe/Weiterverarbeitung
	-- (z.B. externes AddOn GMS_Logs kann das setzen)
	--
	-- @param sinkFn function|nil
	-- ---------------------------------------------------------------------------
	function GMS:LOG_SetSinkFunction(sinkFn)
		local ns = INTERNAL_EnsureGlobalLoggingNamespace()
		if type(sinkFn) == "function" then
			ns.Log = sinkFn
		else
			ns.Log = nil
		end
	end
	
	-- ---------------------------------------------------------------------------
	-- Initialer Logeintrag, damit man sieht, dass Logging-Bootstrap geladen ist
	-- ---------------------------------------------------------------------------
	GMS:LOG_Write("DEBUG", MODULE_NAME, "Logging bootstrap loaded", {
		hasSink = type((_G.GMS_LOGGING and _G.GMS_LOGGING.Log)) == "function",
	})

	-- ---------------------------------------------------------------------------
	-- Registriert automatisch ein UI-Tab + Page "LOGS" (wenn UI verfügbar ist)
	-- - Idempotent: wird nur einmal registriert
	-- - Zeigt _G.GMS_LOGGING.BUFFER an (read-only)
	--
	-- @return nil
	-- ---------------------------------------------------------------------------
	local function INTERNAL_TryRegisterLogsTabInUI()
		if not _G.GMS or not _G.GMS.UI then return end
		if type(_G.GMS.UI.RegisterPage) ~= "function" then return end
		if type(_G.GMS.UI.AddRightDockIconBottom) ~= "function" then return end
		
		_G.GMS_LOGGING.META = _G.GMS_LOGGING.META or {}
		if _G.GMS_LOGGING.META._logsUiRegistered then
			return
		end
		
		_G.GMS_LOGGING.META._logsUiRegistered = true
		
		-- -----------------------------------------------------------------------
		-- Page: LOGS
		-- -----------------------------------------------------------------------
		_G.GMS.UI:RegisterPage("LOGS", 900, "Logs", function(root)
			local LibStub = _G.LibStub
			if not LibStub then return end
			local AceGUI = LibStub("AceGUI-3.0", true)
			if not AceGUI then return end
			
			local buffer = (_G.GMS_LOGGING and _G.GMS_LOGGING.BUFFER) or {}
			
			local wrap = AceGUI:Create("SimpleGroup")
			wrap:SetLayout("List")
			wrap:SetFullWidth(true)
			wrap:SetFullHeight(true)
			root:AddChild(wrap)
			
			local header = AceGUI:Create("Label")
			header:SetFullWidth(true)
			header:SetFontObject(_G.GameFontNormalLarge)
			header:SetText("|cff03A9F4GMS|r – Logs (" .. tostring(#buffer) .. ")")
			wrap:AddChild(header)
			
			local btnRow = AceGUI:Create("SimpleGroup")
			btnRow:SetLayout("Flow")
			btnRow:SetFullWidth(true)
			wrap:AddChild(btnRow)
			
			local refreshBtn = AceGUI:Create("Button")
			refreshBtn:SetText("Refresh")
			refreshBtn:SetWidth(120)
			refreshBtn:SetCallback("OnClick", function()
				if _G.GMS and _G.GMS.UI and _G.GMS.UI.Navigate then
					_G.GMS.UI:Navigate("LOGS")
				end
			end)
			btnRow:AddChild(refreshBtn)
			
			local clearBtn = AceGUI:Create("Button")
			clearBtn:SetText("Clear (UI only)")
			clearBtn:SetWidth(140)
			clearBtn:SetCallback("OnClick", function()
				if _G.GMS_LOGGING and _G.GMS_LOGGING.BUFFER then
					for i = #_G.GMS_LOGGING.BUFFER, 1, -1 do
						_G.GMS_LOGGING.BUFFER[i] = nil
					end
				end
				if _G.GMS and _G.GMS.UI and _G.GMS.UI.Navigate then
					_G.GMS.UI:Navigate("LOGS")
				end
			end)
			btnRow:AddChild(clearBtn)
			
			local scroll = AceGUI:Create("ScrollFrame")
			scroll:SetLayout("List")
			scroll:SetFullWidth(true)
			scroll:SetFullHeight(true)
			wrap:AddChild(scroll)
			
			-- Neueste oben
			for i = #buffer, 1, -1 do
				local e = buffer[i]
				if type(e) == "table" then
					local line = AceGUI:Create("Label")
					line:SetFullWidth(true)
					
					local ts = tostring(e.t or 0)
					local lvl = tostring(e.lvl or "INFO")
					local addon = tostring(e.addon or "UNKNOWN")
					local mod = tostring(e.mod or "UNKNOWN")
					local msg = tostring(e.msg or "")
					
					line:SetText("|cffaaaaaa" .. ts .. "|r [" .. lvl .. "] " .. addon .. ":" .. mod .. " – " .. msg)
					scroll:AddChild(line)
				end
			end
		end)
		
		-- -----------------------------------------------------------------------
		-- RightDock Tab (unten): "LOGS"
		-- -----------------------------------------------------------------------
		_G.GMS.UI:AddRightDockIconBottom({
			id = "LOGS",
			order = 2,
			selectable = true,
			icon = "Interface\\Icons\\INV_Scroll_03",
			tooltipTitle = "Logs",
			tooltipText = "GMS Logbuffer anzeigen",
			onClick = function()
				_G.GMS.UI:Navigate("LOGS")
			end,
		})
		
		GMS:LOG_Write("DEBUG", MODULE_NAME, "UI Logs tab registered", nil)
	end
	
	-- ---------------------------------------------------------------------------
	-- Wartet, bis UI geladen/initialisiert ist und registriert dann Tab+Page
	-- - Robust bei beliebiger Load-Reihenfolge
	--
	-- @return nil
	-- ---------------------------------------------------------------------------
	local function INTERNAL_RegisterLogsTabWhenUIIsReady()
		INTERNAL_TryRegisterLogsTabInUI()
		if (_G.GMS and _G.GMS.UI and _G.GMS.UI.RegisterPage) then
			return
		end
		
		local ev = _G.CreateFrame("Frame")
		ev:RegisterEvent("ADDON_LOADED")
		ev:RegisterEvent("PLAYER_LOGIN")
		ev:SetScript("OnEvent", function()
			INTERNAL_TryRegisterLogsTabInUI()
			if (_G.GMS and _G.GMS.UI and _G.GMS.UI.RegisterPage) then
				ev:UnregisterAllEvents()
			end
		end)
	end
	
	INTERNAL_RegisterLogsTabWhenUIIsReady()
