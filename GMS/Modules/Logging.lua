	-- ============================================================================
	--	GMS/Modules/Logging.lua
	--	GMS INTERNAL MODULE: LOGGING
	-- ============================================================================
	--	- Anzeige/Verarbeitung von Logs aus _G.GMS_LOGGING (BUFFER + Live)
	--	- Persistenz pro Charakter: letzte 1000 Einträge in "GMS_Logging_DB"
	--	- UI Panel (wenn GMS.UI vorhanden) + Chat-Ausgabe (nur via GMS:Print/Printf)
	--	- Filter: Level pro Toggle, Module abwählbar, Textsuche (substring)
	--	- Performance: UI baut Einträge chunked (nach und nach)
	--	- Globaler Buffer wird nach dem Abholen geleert (Drain + Clear)
	-- ============================================================================

	local _G = _G
	local GMS = _G.GMS
	if not GMS or not GMS.Addon then return end

	local LibStub = _G.LibStub
	if not LibStub then return end

	local Addon = GMS.Addon

	-- ###########################################################################
	-- #	CONSTANTS
	-- ###########################################################################

	local MODULE_NAME = "LOGGING"
	local DISPLAY_NAME = "Logging"

	local DB_NAME = "GMS_Logging_DB"
	local MAX_CHAR_ENTRIES = 1000

	local UI_PANEL_NAME = MODULE_NAME

	-- ###########################################################################
	-- #	LOGGING (GLOBAL BUFFER STANDARD) - NUR FÜR MODUL-INTERNES LOGGING
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Loggt einen internen Eintrag in den globalen GMS-Log-Buffer (kein Output)
	--
	--	@param level string
	--	@param message string
	--	@param context table|nil
	-- ---------------------------------------------------------------------------
	local function LOG(level, message, context)
		_G.GMS_LOGGING = _G.GMS_LOGGING or {}
		_G.GMS_LOGGING.BUFFER = _G.GMS_LOGGING.BUFFER or {}

		_G.GMS_LOGGING.BUFFER[#_G.GMS_LOGGING.BUFFER + 1] = {
			time = time(),
			level = tostring(level),
			addon = "GMS",
			module = MODULE_NAME,
			message = tostring(message),
			context = context
		}

		-- WICHTIG: Hier bewusst KEIN Forwarding erzwingen.
		-- Das Forwarding übernimmt das System über _G.GMS_LOGGING.Log, sobald gesetzt.
	end

	-- ###########################################################################
	-- #	ACE MODULE
	-- ###########################################################################

	local Module = Addon:NewModule(
		MODULE_NAME,
		"AceEvent-3.0",
		"AceConsole-3.0",
		"AceTimer-3.0"
	)

	GMS[MODULE_NAME] = Module
	GMS.LOGGING = Module

	-- ###########################################################################
	-- #	DEFAULTS / DB
	-- ###########################################################################

	local DEFAULTS = {
		profile = {
			chatEnabled = true,

			-- Level-Toggles (kein Threshold)
			levelEnabled = {
				DEBUG = true,
				INFO = true,
				WARN = true,
				ERROR = true
			},

			-- Dynamisch: bekannte Module/Addons werden ergänzt
			moduleEnabled = {},

			-- Suche (substring)
			searchEnabled = true,
			searchText = ""
		},

		-- Persistenz pro Charakter
		char = {
			entries = {}
		}
	}

	-- ###########################################################################
	-- #	INTERNAL STATE
	-- ###########################################################################

	Module.DISPLAY_NAME = DISPLAY_NAME
	Module._db = nil

	Module._previousGlobalLogFn = nil
	Module._isGlobalHookInstalled = false

	Module._drainTimerHandle = nil

	Module._seenModules = {}
	Module._seenAddons = {}

	Module._ui = {
		content = nil,
		scroll = nil,
		rowsContainer = nil,
		builderQueue = nil,
		builderTimerHandle = nil
	}

	-- ###########################################################################
	-- #	INTERNAL HELPERS
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Formatiert epoch-seconds zu "YYYY-MM-DD HH:MM:SS"
	--
	--	@param epoch number
	--	@return string
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_FormatTimestamp(epoch)
		return date("%Y-%m-%d %H:%M:%S", tonumber(epoch or time()))
	end

	-- ---------------------------------------------------------------------------
	--	Sichert DB-Bindung (pro Charakter + Profile)
	--
	--	@return table|nil
	-- ---------------------------------------------------------------------------
	function Module:DB_GetModuleDatabaseNamespace()
		if self._db then
			return self._db
		end

		if GMS.DB and GMS.DB.GetModuleDB then
			self._db = GMS.DB:GetModuleDB(MODULE_NAME)
			return self._db
		end

		return nil
	end

	-- ---------------------------------------------------------------------------
	--	Stellt sicher, dass dynamische Filter-Tabellen Einträge besitzen
	--
	--	@param addonName string
	--	@param moduleName string
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_EnsureDynamicFilters(addonName, moduleName)
		local db = self:DB_GetModuleDatabaseNamespace()
		if not db or not db.profile then return end

		db.profile.moduleEnabled = db.profile.moduleEnabled or {}

		local key = tostring(addonName or "?") .. "::" .. tostring(moduleName or "?")
		if db.profile.moduleEnabled[key] == nil then
			db.profile.moduleEnabled[key] = true
		end
	end

	-- ---------------------------------------------------------------------------
	--	Prüft, ob ein Log-Eintrag nach aktuellen Filtern angezeigt werden soll
	--
	--	@param entry table
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_ShouldDisplayEntry(entry)
		local db = self:DB_GetModuleDatabaseNamespace()
		if not db or not db.profile then
			return true
		end

		local level = tostring(entry.level or "")
		local addonName = tostring(entry.addon or "")
		local moduleName = tostring(entry.module or "")

		db.profile.levelEnabled = db.profile.levelEnabled or {}
		db.profile.moduleEnabled = db.profile.moduleEnabled or {}

		if db.profile.levelEnabled[level] == false then
			return false
		end

		local moduleKey = addonName .. "::" .. moduleName
		if db.profile.moduleEnabled[moduleKey] == false then
			return false
		end

		if db.profile.searchEnabled then
			local needle = tostring(db.profile.searchText or "")
			if needle ~= "" then
				local hay = (tostring(entry.message or "") .. " " .. tostring(entry.addon or "") .. " " .. tostring(entry.module or "") .. " " .. tostring(entry.level or "")):lower()
				if not hay:find(needle:lower(), 1, true) then
					return false
				end
			end
		end

		return true
	end

	-- ---------------------------------------------------------------------------
	--	Fügt einen Eintrag in die Charakter-Persistenz ein (Cap: MAX_CHAR_ENTRIES)
	--
	--	@param entry table
	-- ---------------------------------------------------------------------------
	function Module:DB_AppendCharEntry(entry)
		local db = self:DB_GetModuleDatabaseNamespace()
		if not db or not db.char then return end

		db.char.entries = db.char.entries or {}
		db.char.entries[#db.char.entries + 1] = entry

		while #db.char.entries > MAX_CHAR_ENTRIES do
			table.remove(db.char.entries, 1)
		end
	end

	-- ---------------------------------------------------------------------------
	--	Gibt die persistierten Charakter-Entries zurück
	--
	--	@return table
	-- ---------------------------------------------------------------------------
	function Module:DB_GetCharEntries()
		local db = self:DB_GetModuleDatabaseNamespace()
		if not db or not db.char then return {} end

		db.char.entries = db.char.entries or {}
		return db.char.entries
	end

	-- ###########################################################################
	-- #	GLOBAL HOOK / LIVE INGEST
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Verarbeitet einen eingehenden Log-Eintrag (Live-Stream)
	--
	--	@param level string
	--	@param addonName string
	--	@param moduleName string
	--	@param message string
	--	@param context table|nil
	-- ---------------------------------------------------------------------------
	function Module:API_OnIncomingLiveLog(level, addonName, moduleName, message, context)
		local entry = {
			time = time(),
			level = tostring(level),
			addon = tostring(addonName),
			module = tostring(moduleName),
			message = tostring(message),
			context = context
		}

		self._seenModules[tostring(moduleName or "?")] = true
		self._seenAddons[tostring(addonName or "?")] = true

		self:INTERNAL_EnsureDynamicFilters(addonName, moduleName)
		self:DB_AppendCharEntry(entry)

		self:INTERNAL_EmitChatIfEnabled(entry)
		self:INTERNAL_QueueUiRebuildIfOpen()
	end

	-- ---------------------------------------------------------------------------
	--	Installiert den globalen _G.GMS_LOGGING.Log Hook (Live)
	--	- ruft vorherige Log-Funktion weiterhin auf (Kompatibilität)
	--
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_InstallGlobalLogHook()
		_G.GMS_LOGGING = _G.GMS_LOGGING or {}
		_G.GMS_LOGGING.BUFFER = _G.GMS_LOGGING.BUFFER or {}

		if self._isGlobalHookInstalled then
			return true
		end

		local previous = _G.GMS_LOGGING.Log
		self._previousGlobalLogFn = previous

		_G.GMS_LOGGING.Log = function(level, addonName, moduleName, message, context)
			-- Erst unser Ingest
			if Module and Module.API_OnIncomingLiveLog then
				Module:API_OnIncomingLiveLog(level, addonName, moduleName, message, context)
			end

			-- Dann die vorherige Funktion (falls vorhanden und nicht identisch)
			if previous and previous ~= _G.GMS_LOGGING.Log then
				local ok, err = pcall(previous, level, addonName, moduleName, message, context)
				if not ok then
					LOG("ERROR", "Vorherige _G.GMS_LOGGING.Log hat Fehler geworfen.", { error = err })
				end
			end
		end

		self._isGlobalHookInstalled = true
		return true
	end

	-- ###########################################################################
	-- #	BUFFER DRAINING (PULL + CLEAR)
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Holt alle Einträge aus _G.GMS_LOGGING.BUFFER ab und leert den Buffer danach
	--
	--	@param reason string
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_DrainGlobalBufferAndClear(reason)
		_G.GMS_LOGGING = _G.GMS_LOGGING or {}
		_G.GMS_LOGGING.BUFFER = _G.GMS_LOGGING.BUFFER or {}

		local buffer = _G.GMS_LOGGING.BUFFER
		if type(buffer) ~= "table" or #buffer == 0 then
			return
		end

		for i = 1, #buffer do
			local src = buffer[i]
			if type(src) == "table" then
				local entry = {
					time = tonumber(src.time or time()),
					level = tostring(src.level or ""),
					addon = tostring(src.addon or ""),
					module = tostring(src.module or ""),
					message = tostring(src.message or ""),
					context = src.context
				}

				self._seenModules[entry.module] = true
				self._seenAddons[entry.addon] = true

				self:INTERNAL_EnsureDynamicFilters(entry.addon, entry.module)
				self:DB_AppendCharEntry(entry)

				self:INTERNAL_EmitChatIfEnabled(entry)
			end
		end

		-- Buffer leeren (Anforderung #10)
		_G.GMS_LOGGING.BUFFER = {}

		self:INTERNAL_QueueUiRebuildIfOpen()

		LOG("DEBUG", "Globalen Log-Buffer gedraint und geleert.", { reason = reason, drained = #buffer })
	end

	-- ---------------------------------------------------------------------------
	--	Startet einen periodischen Buffer-Drain (für Producer ohne Live-Forwarding)
	--
	--	@param intervalSeconds number
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_StartPeriodicDrain(intervalSeconds)
		if self._drainTimerHandle then
			self:CancelTimer(self._drainTimerHandle)
			self._drainTimerHandle = nil
		end

		self._drainTimerHandle = self:ScheduleRepeatingTimer(function()
			self:INTERNAL_DrainGlobalBufferAndClear("timer")
		end, tonumber(intervalSeconds or 0.5))
	end

	-- ###########################################################################
	-- #	CHAT OUTPUT
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Gibt einen Eintrag im Chat aus (nur via GMS:Print/Printf), wenn aktiviert
	--
	--	@param entry table
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_EmitChatIfEnabled(entry)
		local db = self:DB_GetModuleDatabaseNamespace()
		if not db or not db.profile then return end
		if not db.profile.chatEnabled then return end

		if not self:INTERNAL_ShouldDisplayEntry(entry) then
			return
		end

		local ts = self:INTERNAL_FormatTimestamp(entry.time)
		local ctx = ""

		if entry.context ~= nil then
			local ok, dumped = pcall(function()
				if type(entry.context) == "table" then
					return _G.tostring(entry.context)
				end
				return tostring(entry.context)
			end)
			ctx = ok and (" | context=" .. tostring(dumped)) or " | context=<unprintable>"
		end

		if GMS and GMS.Printf then
			GMS:Printf("[%s] [%s] %s/%s: %s%s", ts, entry.level, entry.addon, entry.module, entry.message, ctx)
		elseif GMS and GMS.Print then
			GMS:Print(string.format("[%s] [%s] %s/%s: %s%s", ts, entry.level, entry.addon, entry.module, entry.message, ctx))
		end
	end

	-- ###########################################################################
	-- #	OPTIONS (ACE CONFIG)
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Baut Options-Tabelle für AceConfig (zentral eingesammelt)
	--
	--	@return table
	-- ---------------------------------------------------------------------------
	function Module:GetOptions()
		return {
			type = "group",
			name = DISPLAY_NAME,
			args = {
				chatEnabled = {
					type = "toggle",
					name = "Chat-Ausgabe",
					desc = "Gibt gefilterte Logs zusätzlich im Chat aus (nur via GMS:Print/Printf).",
					order = 10,
					get = function()
						local db = self:DB_GetModuleDatabaseNamespace()
						return db and db.profile and db.profile.chatEnabled or false
					end,
					set = function(_, val)
						local db = self:DB_GetModuleDatabaseNamespace()
						if db and db.profile then
							db.profile.chatEnabled = val and true or false
						end
					end
				},

				searchEnabled = {
					type = "toggle",
					name = "Suche aktiv",
					desc = "Aktiviert die Textsuche (substring).",
					order = 20,
					get = function()
						local db = self:DB_GetModuleDatabaseNamespace()
						return db and db.profile and db.profile.searchEnabled or false
					end,
					set = function(_, val)
						local db = self:DB_GetModuleDatabaseNamespace()
						if db and db.profile then
							db.profile.searchEnabled = val and true or false
						end
					end
				},

				searchText = {
					type = "input",
					name = "Suchtext",
					desc = "Substring-Suche über Level/AddOn/Modul/Message.",
					order = 30,
					get = function()
						local db = self:DB_GetModuleDatabaseNamespace()
						return db and db.profile and tostring(db.profile.searchText or "") or ""
					end,
					set = function(_, val)
						local db = self:DB_GetModuleDatabaseNamespace()
						if db and db.profile then
							db.profile.searchText = tostring(val or "")
						end
						self:INTERNAL_QueueUiRebuildIfOpen()
					end
				},

				levels = {
					type = "group",
					name = "Level",
					order = 40,
					inline = true,
					args = {
						DEBUG = {
							type = "toggle",
							name = "DEBUG",
							order = 10,
							get = function()
								local db = self:DB_GetModuleDatabaseNamespace()
								return db and db.profile and db.profile.levelEnabled and db.profile.levelEnabled.DEBUG ~= false
							end,
							set = function(_, val)
								local db = self:DB_GetModuleDatabaseNamespace()
								if db and db.profile then
									db.profile.levelEnabled = db.profile.levelEnabled or {}
									db.profile.levelEnabled.DEBUG = val and true or false
								end
								self:INTERNAL_QueueUiRebuildIfOpen()
							end
						},
						INFO = {
							type = "toggle",
							name = "INFO",
							order = 20,
							get = function()
								local db = self:DB_GetModuleDatabaseNamespace()
								return db and db.profile and db.profile.levelEnabled and db.profile.levelEnabled.INFO ~= false
							end,
							set = function(_, val)
								local db = self:DB_GetModuleDatabaseNamespace()
								if db and db.profile then
									db.profile.levelEnabled = db.profile.levelEnabled or {}
									db.profile.levelEnabled.INFO = val and true or false
								end
								self:INTERNAL_QueueUiRebuildIfOpen()
							end
						},
						WARN = {
							type = "toggle",
							name = "WARN",
							order = 30,
							get = function()
								local db = self:DB_GetModuleDatabaseNamespace()
								return db and db.profile and db.profile.levelEnabled and db.profile.levelEnabled.WARN ~= false
							end,
							set = function(_, val)
								local db = self:DB_GetModuleDatabaseNamespace()
								if db and db.profile then
									db.profile.levelEnabled = db.profile.levelEnabled or {}
									db.profile.levelEnabled.WARN = val and true or false
								end
								self:INTERNAL_QueueUiRebuildIfOpen()
							end
						},
						ERROR = {
							type = "toggle",
							name = "ERROR",
							order = 40,
							get = function()
								local db = self:DB_GetModuleDatabaseNamespace()
								return db and db.profile and db.profile.levelEnabled and db.profile.levelEnabled.ERROR ~= false
							end,
							set = function(_, val)
								local db = self:DB_GetModuleDatabaseNamespace()
								if db and db.profile then
									db.profile.levelEnabled = db.profile.levelEnabled or {}
									db.profile.levelEnabled.ERROR = val and true or false
								end
								self:INTERNAL_QueueUiRebuildIfOpen()
							end
						}
					}
				}
			}
		}
	end

	-- ###########################################################################
	-- #	UI (PANEL + CHUNKED BUILDER)
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Queue't ein UI-Rebuild, wenn das Panel aktuell offen ist
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_QueueUiRebuildIfOpen()
		if not self._ui or not self._ui.content or not self._ui.rowsContainer then
			return
		end

		self:INTERNAL_StartUiBuildFromEntries(self:DB_GetCharEntries())
	end

	-- ---------------------------------------------------------------------------
	--	Startet den chunked UI-Aufbau aus einer Entry-Liste
	--
	--	@param entries table
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_StartUiBuildFromEntries(entries)
		local AceGUI = LibStub("AceGUI-3.0", true)
		if not AceGUI then return end
		if not self._ui or not self._ui.rowsContainer then return end

		if self._ui.builderTimerHandle then
			self:CancelTimer(self._ui.builderTimerHandle)
			self._ui.builderTimerHandle = nil
		end

		self._ui.rowsContainer:ReleaseChildren()

		local queue = {}
		for i = 1, #entries do
			local entry = entries[i]
			if type(entry) == "table" and self:INTERNAL_ShouldDisplayEntry(entry) then
				queue[#queue + 1] = entry
			end
		end

		self._ui.builderQueue = queue

		self._ui.builderTimerHandle = self:ScheduleRepeatingTimer(function()
			self:INTERNAL_BuildNextUiChunk()
		end, 0.01)
	end

	-- ---------------------------------------------------------------------------
	--	Baut den nächsten Chunk an UI-Logzeilen
	-- ---------------------------------------------------------------------------
	function Module:INTERNAL_BuildNextUiChunk()
		local AceGUI = LibStub("AceGUI-3.0", true)
		if not AceGUI then return end
		if not self._ui or not self._ui.rowsContainer then return end

		local queue = self._ui.builderQueue
		if type(queue) ~= "table" then
			if self._ui.builderTimerHandle then
				self:CancelTimer(self._ui.builderTimerHandle)
				self._ui.builderTimerHandle = nil
			end
			return
		end

		local CHUNK_SIZE = 50
		local built = 0

		while built < CHUNK_SIZE and #queue > 0 do
			local entry = table.remove(queue, 1)
			if entry then
				local ts = self:INTERNAL_FormatTimestamp(entry.time)

				local header = AceGUI:Create("Label")
				header:SetFullWidth(true)
				header:SetText(string.format("[%s] [%s] %s/%s", ts, entry.level, entry.addon, entry.module))

				local msg = AceGUI:Create("Label")
				msg:SetFullWidth(true)
				msg:SetText(tostring(entry.message or ""))

				local ctx = AceGUI:Create("Label")
				ctx:SetFullWidth(true)
				ctx:SetText("context: " .. tostring(entry.context))

				self._ui.rowsContainer:AddChild(header)
				self._ui.rowsContainer:AddChild(msg)
				self._ui.rowsContainer:AddChild(ctx)

				built = built + 1
			end
		end

		if #queue == 0 then
			if self._ui.builderTimerHandle then
				self:CancelTimer(self._ui.builderTimerHandle)
				self._ui.builderTimerHandle = nil
			end
		end
	end

	-- ---------------------------------------------------------------------------
	--	BuildUI: Panel-Builder für GMS.UI (CONTENT)
	--
	--	@param content table
	--	@param panelName string
	--	@param ctx table|nil
	-- ---------------------------------------------------------------------------
	function Module:BuildUI(content, panelName, ctx)
		local AceGUI = LibStub("AceGUI-3.0", true)
		if not AceGUI or not content then
			LOG("WARN", "BuildUI abgebrochen (AceGUI oder content fehlt).", { panelName = panelName })
			return
		end

		self._ui.content = content

		local title = AceGUI:Create("Heading")
		title:SetFullWidth(true)
		title:SetText(DISPLAY_NAME)

		local hint = AceGUI:Create("Label")
		hint:SetFullWidth(true)
		hint:SetText("Persistiert pro Charakter die letzten 1000 Logs. UI lädt Einträge nach und nach (chunked).")

		local scroll = AceGUI:Create("ScrollFrame")
		scroll:SetFullWidth(true)
		scroll:SetFullHeight(true)
		scroll:SetLayout("Flow")

		local rows = AceGUI:Create("SimpleGroup")
		rows:SetFullWidth(true)
		rows:SetLayout("Flow")

		scroll:AddChild(rows)

		content:AddChild(title)
		content:AddChild(hint)
		content:AddChild(scroll)

		self._ui.scroll = scroll
		self._ui.rowsContainer = rows

		self:INTERNAL_StartUiBuildFromEntries(self:DB_GetCharEntries())

		LOG("DEBUG", "BuildUI ausgeführt.", { panelName = panelName })
	end

	-- ###########################################################################
	-- #	SLASH COMMAND
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Handler für /gms log ...
	--
	--	@param rest string
	--	@param input string
	--	@param sub string
	-- ---------------------------------------------------------------------------
	function Module:API_HandleLoggingSlashCommand(rest, input, sub)
		if GMS.UI and GMS.UI.Open then
			GMS.UI:Open(UI_PANEL_NAME)
			LOG("INFO", "UI Panel geöffnet via SlashCommand.", { panel = UI_PANEL_NAME })
		else
			if GMS and GMS.Print then
				GMS:Print("GMS UI ist nicht verfügbar.")
			end
			LOG("WARN", "UI nicht verfügbar für SlashCommand.", { panel = UI_PANEL_NAME })
		end
	end

	-- ###########################################################################
	-- #	ACE LIFECYCLE
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	OnInitialize: DB/Options/UI/Slash registrieren + Live Hook + Drain starten
	-- ---------------------------------------------------------------------------
	function Module:OnInitialize()
		LOG("DEBUG", "OnInitialize gestartet.")

		if GMS.DB and GMS.DB.RegisterModule then
			GMS.DB:RegisterModule(MODULE_NAME, DEFAULTS, function()
				return self:GetOptions()
			end)
			LOG("INFO", "DB:RegisterModule erfolgreich.", { module = MODULE_NAME, db = DB_NAME })
		else
			LOG("WARN", "DB:RegisterModule nicht verfügbar (GMS.DB fehlt).", { module = MODULE_NAME })
		end

		self:DB_GetModuleDatabaseNamespace()

		self:INTERNAL_InstallGlobalLogHook()
		self:INTERNAL_DrainGlobalBufferAndClear("initialize")
		self:INTERNAL_StartPeriodicDrain(0.5)

		if GMS.UI and GMS.UI.RegisterPanel then
			GMS.UI:RegisterPanel(UI_PANEL_NAME, self, "BuildUI")
			LOG("INFO", "UI:RegisterPanel erfolgreich.", { panel = UI_PANEL_NAME })
		else
			LOG("INFO", "UI nicht vorhanden, Panel-Registrierung übersprungen.", { panel = UI_PANEL_NAME })
		end

		if GMS.SlashCommands and GMS.SlashCommands.RegisterSubCommand then
			GMS.SlashCommands:RegisterSubCommand(
				"log",
				function(rest, input, sub)
					self:API_HandleLoggingSlashCommand(rest, input, sub)
				end,
				{
					help = "Öffnet das Logging-Panel (wenn UI verfügbar ist).",
					order = 100,
					alias = { "logs", "logging" },
					owner = MODULE_NAME
				}
			)
			LOG("INFO", "SlashCommands:RegisterSubCommand erfolgreich.", { key = "log" })
		else
			LOG("WARN", "SlashCommands:RegisterSubCommand nicht verfügbar (GMS.SlashCommands fehlt).", { key = "log" })
		end

		LOG("DEBUG", "OnInitialize beendet.")
	end

	-- ---------------------------------------------------------------------------
	--	OnEnable: Initialer Drain (Sicherheit)
	-- ---------------------------------------------------------------------------
	function Module:OnEnable()
		self:INTERNAL_DrainGlobalBufferAndClear("enable")
		LOG("INFO", "OnEnable: Modul aktiviert.")
	end

	-- ---------------------------------------------------------------------------
	--	OnDisable: Timer stoppen
	-- ---------------------------------------------------------------------------
	function Module:OnDisable()
		if self._drainTimerHandle then
			self:CancelTimer(self._drainTimerHandle)
			self._drainTimerHandle = nil
		end

		if self._ui and self._ui.builderTimerHandle then
			self:CancelTimer(self._ui.builderTimerHandle)
			self._ui.builderTimerHandle = nil
		end

		LOG("WARN", "OnDisable: Modul deaktiviert.")
	end
