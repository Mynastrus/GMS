	
	-- ============================================================================
	--	GMS/Core/UI/UI.lua
	--	UI Bootstrap (creates Ace module + shared state)
	--	- No _G / no addonTable
	--	- Access GMS only via AceAddon registry
	-- ============================================================================
	
	local LibStub = LibStub
	if not LibStub then return end
	
	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end
	
	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end
	
	local UI = GMS:NewModule("UI", "AceConsole-3.0", "AceEvent-3.0")
	GMS.UI = UI

	local MODULE_NAME = "UI"
	
	-- ---------------------------------------------------------------------------
	--	Returns the UI module (creates if missing)
	--
	--	@return table UI
	-- ---------------------------------------------------------------------------
	local function INTERNAL_GetOrCreateUiModule()
	local UI = GMS:GetModule(MODULE_NAME, true)
	if not UI then
		UI = GMS:NewModule(MODULE_NAME, "AceConsole-3.0", "AceEvent-3.0")
	end
	return UI
	end
	
	local UI = INTERNAL_GetOrCreateUiModule()
	GMS.UI = UI
	
	-- ---------------------------------------------------------------------------
	--	Ensures base state tables exist (idempotent)
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:INTERNAL_EnsureUiStateTablesExist()
	self._inited = self._inited or false
	
	self._frame = self._frame or nil
	self._content = self._content or nil
	self._root = self._root or nil
	self._page = self._page or nil
	
	self._pages = self._pages or {}
	self._order = self._order or {}
	
	self._rightDockSeeded = self._rightDockSeeded or false
	self._rightDock = self._rightDock or {
		inited = false,
		parent = nil,
		top = { order = {}, entries = {} },
		bottom = { order = {}, entries = {} },
		all = {},
	}
	
	self.RightDockConfig = self.RightDockConfig or {
		offsetX = -10,
		topOffsetY = 26,
		bottomOffsetY = 1,
		slotWidth = 46,
		slotHeight = 38,
		slotGap = 2,
		buttonSize = 32,
		iconInset = 4,
		buttonOffsetX = 4,
		buttonOffsetY = 0,
		slotBackdrop = {
			bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		},
		normalTexture = "",
		pushedTexture = "Interface\\Buttons\\UI-Quickslot-Depress",
		hoverTexture = "Interface\\Buttons\\ButtonHilight-Square",
		selectedGlowTexture = "Interface\\Buttons\\UI-ActionButton-Border",
		selectedGlowColor = { 1, 0.82, 0.2, 1 },
		selectedGlowPad = 32,
		iconTexCoord = { 0.07, 0.93, 0.07, 0.93 },
	}
	end
	
	UI:INTERNAL_EnsureUiStateTablesExist()
