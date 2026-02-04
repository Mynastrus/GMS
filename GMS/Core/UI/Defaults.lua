	
	-- ============================================================================
	--	GMS/Core/UI/Defaults.lua
	--	Defaults + DB helpers (AceDB)
	-- ============================================================================
	
	local LibStub = LibStub
	if not LibStub then return end
	
	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end
	
	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end
	
	local UI = GMS:GetModule("UI", true)
	if not UI then return end
	
	local AceDB = LibStub("AceDB-3.0", true)
	if not AceDB then return end
	
	UI.DEFAULTS = UI.DEFAULTS or {
	profile = {
		window = {
			w = 900,
			h = 560,
			point = "CENTER",
			relPoint = "CENTER",
			x = 0,
			y = 0,
			activePage = "home",
		},
	},
	}
	
	-- ---------------------------------------------------------------------------
	--	Initializes the UI database if missing
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:DB_EnsureDatabaseIsInitialized()
	if self.db then return end
	self.db = AceDB:New("GMS_UIDB", self.DEFAULTS, true)
	end
	
	-- ---------------------------------------------------------------------------
	--	Returns the window profile table (creates missing tables)
	--
	--	@return table
	-- ---------------------------------------------------------------------------
	function UI:DB_GetWindowProfile()
	if not self.db then
		return self.DEFAULTS.profile.window
	end
	self.db.profile.window = self.db.profile.window or {}
	return self.db.profile.window
	end
	
	-- ---------------------------------------------------------------------------
	--	Saves the active page name into the database
	--
	--	@param pageName string
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:DB_SaveActivePage(pageName)
	if not self.db then return end
	local wdb = self:DB_GetWindowProfile()
	wdb.activePage = tostring(pageName or "home")
	end
	
	-- ---------------------------------------------------------------------------
	--	Loads the active page name from the database (fallback home)
	--
	--	@return string
	-- ---------------------------------------------------------------------------
	function UI:DB_GetActivePageOrDefault()
	local wdb = self:DB_GetWindowProfile()
	return tostring(wdb.activePage or "home")
	end
