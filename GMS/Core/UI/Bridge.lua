	
	-- ============================================================================
	--	GMS/Core/UI/Bridge.lua
	--	GMS bridge API (GMS:UI_IsReady + GMS:UI_Open)
	-- ============================================================================
	
	local LibStub = LibStub
	if not LibStub then return end
	
	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end
	
	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end
	
	local UI = GMS:GetModule("UI", true)
	if not UI then return end
	
	-- ---------------------------------------------------------------------------
	--	Checks if the UI is ready (module exists + frame created)
	--
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function UI:BRIDGE_IsReady()
	return self._inited == true and self._frame ~= nil
	end
	
	-- ---------------------------------------------------------------------------
	--	GMS bridge: checks if UI is ready
	--
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function GMS:UI_IsReady()
	local mod = self:GetModule("UI", true)
	if not mod then return false end
	if type(mod.BRIDGE_IsReady) == "function" then
		return mod:BRIDGE_IsReady() == true
	end
	return mod._inited == true and mod._frame ~= nil
	end
	
	-- ---------------------------------------------------------------------------
	--	GMS bridge: opens UI and optionally navigates to pageName
	--
	--	@param pageName string|nil
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function GMS:UI_Open(pageName)
	local mod = self:GetModule("UI", true)
	if not mod then return false end
	
	if not self:UI_IsReady() then
		if mod.Init then
			mod:Init()
		end
	end
	
	if not self:UI_IsReady() then
		if mod.LOG_Warn then
			mod:LOG_Warn("GMS:UI_Open failed (UI not ready)", { pageName = pageName })
		end
		return false
	end
	
	if mod.WINDOW_OpenWindowAndNavigate then
		mod:WINDOW_OpenWindowAndNavigate(type(pageName) == "string" and pageName or nil)
	end
	return true
	end
