	
	-- ============================================================================
	--	GMS/Core/UI/Logging.lua
	--	UI logging wrapper (routes into GMS LOG_* if available)
	-- ============================================================================
	
	local LibStub = LibStub
	if not LibStub then return end
	
	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end
	
	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end
	
	local UI = GMS:GetModule("UI", true)
	if not UI then return end
	
	local MODULE_NAME = "UI"
	
	-- ---------------------------------------------------------------------------
	--	Logs a debug message (if GMS logging is available)
	--
	--	@param message string
	--	@param context table|nil
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:LOG_Debug(message, context)
	if GMS.LOG_Debug then
		GMS:LOG_Debug(MODULE_NAME, tostring(message or ""), context)
	end
	end
	
	-- ---------------------------------------------------------------------------
	--	Logs an info message (if GMS logging is available)
	--
	--	@param message string
	--	@param context table|nil
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:LOG_Info(message, context)
	if GMS.LOG_Info then
		GMS:LOG_Info(MODULE_NAME, tostring(message or ""), context)
	end
	end
	
	-- ---------------------------------------------------------------------------
	--	Logs a warning message (if GMS logging is available)
	--
	--	@param message string
	--	@param context table|nil
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:LOG_Warn(message, context)
	if GMS.LOG_Warn then
		GMS:LOG_Warn(MODULE_NAME, tostring(message or ""), context)
	end
	end
	
	-- ---------------------------------------------------------------------------
	--	Logs an error message (if GMS logging is available)
	--
	--	@param message string
	--	@param context table|nil
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:LOG_Error(message, context)
	if GMS.LOG_Error then
		GMS:LOG_Error(MODULE_NAME, tostring(message or ""), context)
	end
	end
