	
	-- ============================================================================
	--	GMS/Core/UI/Lifecycle.lua
	--	Ace lifecycle hooks
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
	--	Ace Lifecycle: OnInitialize
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:OnInitialize()
	if self.Init then
		self:Init()
	end
	end
	
	-- ---------------------------------------------------------------------------
	--	Ace Lifecycle: OnEnable
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:OnEnable()
	if self.LOG_Debug then
		self:LOG_Debug("UI OnEnable", nil)
	end
	if self.SLASH_RegisterUiSubCommandIfAvailable then
		self:SLASH_RegisterUiSubCommandIfAvailable()
	end
	end
	
	-- ---------------------------------------------------------------------------
	--	Ace Lifecycle: OnDisable
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:OnDisable()
	if self.LOG_Debug then
		self:LOG_Debug("UI OnDisable", nil)
	end
	if self.WINDOW_HideWindow then
		self:WINDOW_HideWindow()
	end
	end
