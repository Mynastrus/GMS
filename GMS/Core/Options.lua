	-- ============================================================================
	-- Core Module: OPTIONS
	-- Skeleton implementation (no load errors)
	-- ============================================================================
	
	local _G = _G
	local GMS = _G.GMS
	if not GMS or not GMS.Addon then
		if _G.LOG then _G.LOG("DEBUG", "GMS", "OPTIONS", "Skipped (GMS.Addon missing)") end
		return
	end
	
	local Addon = GMS.Addon
	
	-- ---------------------------------------------------------------------------
	-- Placeholder module body
	-- ---------------------------------------------------------------------------
	-- (Intentionally minimal)
	-- ============================================================================
	--	GMS/Core/Options.lua
	--	CORE MODULE: OPTIONS
	--	- Zentrale Options-Registrierung (AceConfig)
	--	- Sammelt optionale GetOptions() Tabellen aus allen Modulen
	--	- Kann Options im UI einbetten (AceConfigDialog:Open(appName, hostContainer))
	--	- Keine LoadErrors (harte Guards)
	-- ============================================================================
	
	local _G = _G
	local GMS = _G.GMS
	if not GMS or not GMS.Addon then return end
	
	local Addon = GMS.Addon
	
	local LibStub = _G.LibStub
	if not LibStub then return end
	
	local AceConfig = LibStub("AceConfig-3.0", true)
	local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
	if not AceConfig or not AceConfigDialog then
		if type(_G.LOG) == "function" then
			_G.LOG("WARN", "GMS", "OPTIONS", "AceConfig-3.0 oder AceConfigDialog-3.0 fehlt – Options werden nicht initialisiert.", nil)
		end
		return
	end
	
	-- ###########################################################################
	-- #	CONSTANTS / META
	-- ###########################################################################
	
	local MODULE_NAME = "OPTIONS"
	local DISPLAY_NAME = "Options"
	
	local APP_NAME = "GMS"
	
	-- ###########################################################################
	-- #	LOGGING
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
	
	-- ###########################################################################
	-- #	ACE MODULE
	-- ###########################################################################
	
	local Options = Addon:NewModule(
		MODULE_NAME,
		"AceConsole-3.0",
		"AceEvent-3.0"
	)
	
	GMS[MODULE_NAME] = Options
	GMS.OPTIONS = Options
	
	Options.MODULE_NAME = MODULE_NAME
	Options.DISPLAY_NAME = DISPLAY_NAME
	
	-- ###########################################################################
	-- #	STATE
	-- ###########################################################################
	
	Options.INTERNAL_REGISTERED = false
	Options.INTERNAL_LAST_OPTIONS_TABLE = nil
	
	-- ###########################################################################
	-- #	OPTIONS BUILD
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Sammelt Options-Tabellen aus Modulen (GetOptions)
	--
	--	@return table
	-- ---------------------------------------------------------------------------
	function Options:INTERNAL_CollectModuleOptions()
		local groups = {}
	
		-- DB registrierte optionFns bevorzugen (projektweiter Standard)
		if GMS.DB and type(GMS.DB.API_GetRegisteredOptionsFunction) == "function" then
			for moduleName, _ in pairs(GMS.DB.INTERNAL_OPTIONS_FNS_BY_MODULE or {}) do
				local fn = GMS.DB:API_GetRegisteredOptionsFunction(moduleName)
				if type(fn) == "function" then
					local ok, opts = pcall(fn)
					if ok and type(opts) == "table" then
						groups[#groups + 1] = { name = tostring(moduleName), options = opts }
					end
				end
			end
		end
	
		-- Fallback: Module:GetOptions()
		if GMS.MODULES and type(GMS.MODULES.API_ListModules) == "function" then
			local list = GMS.MODULES:API_ListModules()
			for i = 1, #list do
				local entry = list[i]
				local obj = entry and entry.object
				if type(obj) == "table" and type(obj.GetOptions) == "function" then
					local ok, opts = pcall(obj.GetOptions, obj)
					if ok and type(opts) == "table" then
						groups[#groups + 1] = { name = tostring(entry.name or "MODULE"), options = opts }
					end
				end
			end
		end
	
		table.sort(groups, function(a, b)
			return tostring(a.name) < tostring(b.name)
		end)
	
		local args = {}
		for i = 1, #groups do
			local g = groups[i]
			args[g.name] = g.options
		end
	
		-- Root-Options
		local root = {
			type = "group",
			name = "GMS",
			args = args,
		}
	
		return root
	end
	
	-- ---------------------------------------------------------------------------
	--	Registriert die Options bei AceConfig (idempotent)
	--
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function Options:INTERNAL_RegisterOptionsIfNeeded()
		if self.INTERNAL_REGISTERED then
			return true
		end
	
		local root = self:INTERNAL_CollectModuleOptions()
		self.INTERNAL_LAST_OPTIONS_TABLE = root
	
		local ok, err = pcall(AceConfig.RegisterOptionsTable, AceConfig, APP_NAME, root)
		if not ok then
			LOG("ERROR", "AceConfig.RegisterOptionsTable fehlgeschlagen.", { error = err })
			return false
		end
	
		self.INTERNAL_REGISTERED = true
		LOG("INFO", "Options registriert.", { app = APP_NAME })
		return true
	end
	
	-- ###########################################################################
	-- #	UI EMBEDDING
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Öffnet die Options eingebettet in einen AceGUI Container
	--	(WICHTIG: AceConfigDialog:Open(appName, hostContainer))
	--
	--	@param hostContainer table (AceGUI container)
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function Options:API_OpenEmbedded(hostContainer)
		if type(hostContainer) ~= "table" or type(hostContainer.AddChild) ~= "function" then
			LOG("ERROR", "API_OpenEmbedded: hostContainer ungültig.", nil)
			return false
		end
	
		local ok = self:INTERNAL_RegisterOptionsIfNeeded()
		if not ok then
			return false
		end
	
		local okOpen, errOpen = pcall(AceConfigDialog.Open, AceConfigDialog, APP_NAME, hostContainer)
		if not okOpen then
			LOG("ERROR", "AceConfigDialog:Open(app, host) fehlgeschlagen.", { error = errOpen })
			return false
		end
	
		return true
	end
	
	-- ###########################################################################
	-- #	DEFAULT PANEL (optional)
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Standard BuildUI für OPTIONS Panel (für UI:RegisterPanel)
	--
	--	@param content table (AceGUI container)
	--	@param panelName string
	--	@param ctx table|nil
	--	@param ... any
	--	@return nil
	-- ---------------------------------------------------------------------------
	function Options:BuildUI(content, panelName, ctx, ...)
		self:API_OpenEmbedded(content)
	end
	
	-- ###########################################################################
	-- #	ACE LIFECYCLE
	-- ###########################################################################
	
	-- ---------------------------------------------------------------------------
	--	Ace Lifecycle: OnInitialize
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function Options:OnInitialize()
		if GMS.MODULES and type(GMS.MODULES.API_RegisterInternalModule) == "function" then
			GMS.MODULES:API_RegisterInternalModule(MODULE_NAME, self, DISPLAY_NAME, true)
		end
	
		-- Panel registrieren, wenn UI verfügbar ist
		if GMS.UI and type(GMS.UI.RegisterPanel) == "function" then
			GMS.UI:RegisterPanel("OPTIONS", self, "BuildUI")
		end
	
		-- RightDock Icon (unten) optional
		if GMS.UI and type(GMS.UI.AddRightDockIconBottom) == "function" then
			GMS.UI:AddRightDockIconBottom({
				key = "options",
				icon = "Interface\\Icons\\INV_Misc_Gear_01",
				tooltip = "Options",
				order = 1000,
				onClick = function()
					if GMS.UI and type(GMS.UI.Open) == "function" then
						GMS.UI:Open("OPTIONS")
					end
				end,
			})
		end
	
		LOG("INFO", "OPTIONS initialisiert.", nil)
	end
	
	-- ---------------------------------------------------------------------------
	--	Ace Lifecycle: OnEnable
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function Options:OnEnable()
		if GMS.MODULES and type(GMS.MODULES.API_SetModuleEnabledState) == "function" then
			GMS.MODULES:API_SetModuleEnabledState(MODULE_NAME, true)
		end
		LOG("DEBUG", "OPTIONS enabled.", nil)
	end
	
	-- ---------------------------------------------------------------------------
	--	Ace Lifecycle: OnDisable
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function Options:OnDisable()
		if GMS.MODULES and type(GMS.MODULES.API_SetModuleEnabledState) == "function" then
			GMS.MODULES:API_SetModuleEnabledState(MODULE_NAME, false)
		end
		LOG("DEBUG", "OPTIONS disabled.", nil)
	end
