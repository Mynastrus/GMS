	-- ============================================================================
	--	GMS/GMS.lua
	--	GMS Core Entry (AceAddon)
	--
	--	PROJECT STANDARD (aktuell):
	--	- _G ist erlaubt (inkl. _G.GMS Export für /run)
	--	- Shared Access primär über _G.GMS und/oder AceAddon Registry
	--	- KEIN addonTable
	--	- Eigene Print / Printf (nicht zwingend AceConsole)
	--	- Möglichst viele Ace-Mixins aktiv (wenn verfügbar)
	--	- TAB-Indent only (jede Zeile mind. 1 führender Tab)
	-- ============================================================================

	local ADDON_NAME = ...
	local _G = _G

	-- ---------------------------------------------------------------------------
	--	Guard: LibStub erforderlich
	-- ---------------------------------------------------------------------------

	local LibStub = _G.LibStub
	if not LibStub then return end

	-- ---------------------------------------------------------------------------
	--	AceAddon erforderlich
	-- ---------------------------------------------------------------------------

	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end

	-- ---------------------------------------------------------------------------
	--	Ace Mixins (optional)
	-- ---------------------------------------------------------------------------

	local AceConsole	= LibStub("AceConsole-3.0", true)
	local AceEvent		= LibStub("AceEvent-3.0", true)
	local AceTimer		= LibStub("AceTimer-3.0", true)
	local AceComm		= LibStub("AceComm-3.0", true)
	local AceSerializer	= LibStub("AceSerializer-3.0", true)
	local AceHook		= LibStub("AceHook-3.0", true)
	local AceBucket		= LibStub("AceBucket-3.0", true)
	local AceDB			= LibStub("AceDB-3.0", true)

	-- ---------------------------------------------------------------------------
	--	table.unpack Fallback
	-- ---------------------------------------------------------------------------

	local Unpack = (table and table.unpack) or _G.unpack

	-- ---------------------------------------------------------------------------
	--	GMS AceAddon erstellen ODER aus Registry holen
	-- ---------------------------------------------------------------------------

	local GMS = AceAddon:GetAddon("GMS", true)

	if not GMS then
		local mixins = {}

		if AceConsole		then mixins[#mixins + 1] = "AceConsole-3.0" end
		if AceEvent			then mixins[#mixins + 1] = "AceEvent-3.0" end
		if AceTimer			then mixins[#mixins + 1] = "AceTimer-3.0" end
		if AceComm			then mixins[#mixins + 1] = "AceComm-3.0" end
		if AceSerializer	then mixins[#mixins + 1] = "AceSerializer-3.0" end
		if AceHook			then mixins[#mixins + 1] = "AceHook-3.0" end
		if AceBucket		then mixins[#mixins + 1] = "AceBucket-3.0" end

		GMS = AceAddon:NewAddon("GMS", Unpack(mixins))
	end

	-- ---------------------------------------------------------------------------
	--	Global Export (bewusst erlaubt) für /run & Debugging
	--	=> _G.GMS muss das AceAddon-Objekt sein (für /run GMS:XY()).
	-- ---------------------------------------------------------------------------

	_G.GMS = GMS

	-- Falls STATES existiert (z.B. aus ModulStates.lua), sicherstellen, dass es dranhängt
	if not GMS.STATES then
		GMS.STATES = {}
	end

	-- ---------------------------------------------------------------------------
	--	Konstanten / Meta
	-- ---------------------------------------------------------------------------

	GMS.ADDON_NAME			= ADDON_NAME
	GMS.INTERNAL_ADDON_NAME	= tostring(ADDON_NAME or "GMS")
	GMS.CHAT_PREFIX			= "|cff03A9F4[GMS]|r"
	GMS.LOG_BUFFER_MAX		= 5000

	-- ============================================================================
	--	CHAT OUTPUT (ohne AceConsole)
	-- ============================================================================

	-- ---------------------------------------------------------------------------
	--	GMS:Print
	-- ---------------------------------------------------------------------------

	function GMS:Print(msg)
		if msg == nil then return end
		print(string.format("%s  %s", tostring(self.CHAT_PREFIX), tostring(msg)))
	end

	-- ---------------------------------------------------------------------------
	--	GMS:Printf
	-- ---------------------------------------------------------------------------

	function GMS:Printf(fmt, ...)
		if fmt == nil then return end

		local ok, rendered = pcall(string.format, tostring(fmt), ...)
		if not ok then
			self:Print(fmt)
			return
		end

		self:Print(rendered)
	end

	-- ============================================================================
	--	LOG BUFFER (keine direkte Ausgabe)
	-- ============================================================================

	GMS.LOG_BUFFER	= GMS.LOG_BUFFER or {}
	GMS.LOG_SEQ		= GMS.LOG_SEQ or 0

	function GMS:LOG_Push(level, module, message, context)
		self.LOG_SEQ = (self.LOG_SEQ or 0) + 1

		local now = 0
		if _G.GetTime then
			now = _G.GetTime()
		end

		self.LOG_BUFFER[#self.LOG_BUFFER + 1] = {
			seq		= self.LOG_SEQ,
			time	= now,
			level	= tostring(level or "INFO"),
			addon	= tostring(self.ADDON_NAME or "GMS"),
			module	= tostring(module or "CORE"),
			message	= tostring(message or ""),
			context	= context,
		}

		local maxCount = tonumber(self.LOG_BUFFER_MAX) or 5000
		while #self.LOG_BUFFER > maxCount do
			table.remove(self.LOG_BUFFER, 1)
		end
	end

	function GMS:LOG_Debug(module, message, context)	self:LOG_Push("DEBUG", module, message, context) end
	function GMS:LOG_Info(module, message, context)	self:LOG_Push("INFO",  module, message, context) end
	function GMS:LOG_Warn(module, message, context)	self:LOG_Push("WARN",  module, message, context) end
	function GMS:LOG_Error(module, message, context)	self:LOG_Push("ERROR", module, message, context) end

	-- ============================================================================
	--	DB (optional)
	-- ============================================================================

	GMS.DEFAULTS = GMS.DEFAULTS or {
		profile = {
			debug = false,
		},
		global = {
			version = 1,
		},
	}

	function GMS:InitializeDatabaseIfAvailable(force)
		if not AceDB then
			self:LOG_Warn("CORE", "AceDB-3.0 not available", nil)
			return false
		end

		if self.db and not force then
			return true
		end

		-- Prefer a centralized initializer if provided by Core/Database.lua
		if type(self.InitializeStandardDatabases) == "function" then
			local ok, res = pcall(self.InitializeStandardDatabases, self, force)
			if ok and res then
				self:LOG_Info("CORE", "InitializeStandardDatabases used", nil)
				return true
			end
		end

		-- Fallback: create the main DB using Core defaults
		self.db = AceDB:New("GMS_DB", self.DEFAULTS, true)
		self:LOG_Info("CORE", "AceDB initialized (fallback)", nil)
		return true
	end

	-- ============================================================================
	--	STATE: Dateiload (so früh wie möglich markieren)
	-- ============================================================================

	if GMS.STATES and type(GMS.STATES.UPDATE) == "function" then
		GMS.STATES:UPDATE("GMS", "LOADED")
	end

	-- ============================================================================
	--	LIFECYCLE
	-- ============================================================================

	function GMS:OnInitialize()
		self:InitializeDatabaseIfAvailable(false)

		self:LOG_Info("CORE", "OnInitialize", {
			internalAddonName = self.INTERNAL_ADDON_NAME,
			addonName = self.ADDON_NAME,
		})

		if self.STATES and type(self.STATES.UPDATE) == "function" then
			self.STATES:UPDATE("GMS", "INITIALIZED")
		end
	end

	function GMS:OnEnable()
		self:LOG_Info("CORE", "OnEnable", nil)

		if self.STATES and type(self.STATES.UPDATE) == "function" then
			self.STATES:UPDATE("GMS", "ENABLED")
			self.STATES:UPDATE("GMS", "READY")
		end
	end

	function GMS:OnDisable()
		self:LOG_Info("CORE", "OnDisable", nil)

		if self.STATES and type(self.STATES.UPDATE) == "function" then
			self.STATES:UPDATE("GMS", "DISABLED")
		end
	end

	-- ============================================================================
	--	MINI DEBUG API (optional /run helpers)
	-- ============================================================================

	GMS.API = GMS.API or {}

	function GMS:API_GetLogBuffer()
		return self.LOG_BUFFER or {}
	end

	function GMS:DEBUG_DumpLogsToChat(count)
		local n = tonumber(count) or 20
		if n < 1 then n = 1 end

		local buffer = self.LOG_BUFFER or {}
		local total = #buffer

		self:Print(string.format("Dumping last %d logs (total=%d)", n, total))

		local startIndex = total - n + 1
		if startIndex < 1 then startIndex = 1 end

		for i = startIndex, total do
			local e = buffer[i]
			if e then
				INTERNAL_PrintToChat(string.format(
					"%s [%s] %s: %s",
					self.CHAT_PREFIX,
					tostring(e.level),
					tostring(e.module),
					tostring(e.message)
				))
			end
		end
	end

	-- ============================================================================
	--	Example Listener (optional): log every state update
	-- ============================================================================

	if GMS.STATES and type(GMS.STATES.ONUPDATE) == "function" then
		GMS.STATES:ONUPDATE(function(name, s)
			if GMS and type(GMS.Print) == "function" then
				GMS:Print(string.format("[STATES] %s -> %s (READY=%s DISABLED=%s)", tostring(name), tostring(s.STATE), tostring(s.READY), tostring(s.DISABLED)))
			end
		end)
	end

	-- Notify that Core finished loading
	pcall(function()
	    if GMS and type(GMS.Print) == "function" then
	        GMS:Print("CORE wurde geladen")
	    end
	end)
