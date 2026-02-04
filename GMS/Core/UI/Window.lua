	
	-- ============================================================================
	--	GMS/Core/UI/Window.lua
	--	ButtonFrameTemplate shell + content frame + persistence (position/size)
	-- ============================================================================
	
	local LibStub = LibStub
	if not LibStub then return end
	
	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end
	
	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end
	
	local UI = GMS:GetModule("UI", true)
	if not UI then return end
	
	UI.FRAME_NAME = UI.FRAME_NAME or "GMS_MainFrame"
	UI.DISPLAY_NAME = UI.DISPLAY_NAME or "Guild Management System"
	
	-- ---------------------------------------------------------------------------
	--	Sets the window title (custom FontString)
	--
	--	@param text string|nil
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:WINDOW_SetWindowTitle(text)
	if self._frame and self._frame.GMS_TitleText then
		self._frame.GMS_TitleText:SetText(tostring(text or ""))
	end
	end
	
	-- ---------------------------------------------------------------------------
	--	Sets the portrait icon with a stable fallback
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:WINDOW_SetIconFallback()
	if not self._frame then return end
	
	local portrait =
		self._frame.portrait or
		self._frame.Portrait or
		(self._frame.PortraitContainer and self._frame.PortraitContainer.portrait)
	
	if not portrait or not portrait.SetTexture then
		return
	end
	
	portrait:ClearAllPoints()
	portrait:SetPoint("CENTER", portrait:GetParent(), "CENTER", 25, -22)
	portrait:SetTexCoord(0, 1, 0, 1)
	portrait:SetTexture("Interface\\AddOns\\GMS\\Media\\GMS_Portrait_Icon")
	end
	
	-- ---------------------------------------------------------------------------
	--	Applies stored position + size from DB to the frame
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:WINDOW_ApplyWindowStateFromDatabase()
	if not self._frame then return end
	if not self.DB_GetWindowProfile then return end
	
	local wdb = self:DB_GetWindowProfile()
	
	self._frame:ClearAllPoints()
	self._frame:SetPoint(
		wdb.point or "CENTER",
		UIParent,
		wdb.relPoint or "CENTER",
		wdb.x or 0,
		wdb.y or 0
	)
	
	self._frame:SetSize(
		wdb.w or 900,
		wdb.h or 560
	)
	end
	
	-- ---------------------------------------------------------------------------
	--	Saves current position + size to DB
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:WINDOW_SaveWindowStateToDatabase()
	if not self._frame or not self.db then return end
	if not self.DB_GetWindowProfile then return end
	
	local wdb = self:DB_GetWindowProfile()
	
	local w, h = self._frame:GetSize()
	wdb.w = math.floor(((w or 900) + 0.5))
	wdb.h = math.floor(((h or 560) + 0.5))
	
	local point, _, relPoint, xOfs, yOfs = self._frame:GetPoint(1)
	wdb.point = point or "CENTER"
	wdb.relPoint = relPoint or "CENTER"
	wdb.x = math.floor(((xOfs or 0) + 0.5))
	wdb.y = math.floor(((yOfs or 0) + 0.5))
	end
	
	-- ---------------------------------------------------------------------------
	--	Resets window DB to defaults and reapplies state
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:WINDOW_ResetWindowToDefaults()
	if not self.db then return end
	if not self.DEFAULTS then return end
	
	self.db.profile.window = CopyTable(self.DEFAULTS.profile.window)
	
	if self._frame then
		self:WINDOW_ApplyWindowStateFromDatabase()
		if self.PAGES_NavigateToPage and self.DB_GetActivePageOrDefault then
			self:PAGES_NavigateToPage(self:DB_GetActivePageOrDefault())
		end
		if self.RIGHTDOCK_ReflowDock then
			self:RIGHTDOCK_ReflowDock()
		end
	end
	end
	
	-- ---------------------------------------------------------------------------
	--	Creates the main UI frame if missing (ButtonFrameTemplate)
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:WINDOW_CreateFrameIfMissing()
	if self._frame then return end
	
	local f = CreateFrame("Frame", self.FRAME_NAME, UIParent, "ButtonFrameTemplate")
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(200)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true)
	f:SetResizable(true)
	
	local titleParent = f.TitleContainer or f.Header or f.TopTileStreaks or f
	local titleFS = titleParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmallOutline")
	titleFS:SetJustifyH("LEFT")
	titleFS:SetDrawLayer("OVERLAY", 7)
	titleFS:ClearAllPoints()
	titleFS:SetPoint("LEFT", titleParent, "LEFT", 6, -2)
	titleFS:SetPoint("RIGHT", titleParent, "RIGHT", -40, 2)
	f.GMS_TitleText = titleFS
	
	if f.TitleText and f.TitleText.SetText then
		f.TitleText:SetText("")
		f.TitleText:Hide()
	end
	
	if f.SetClampRectInsets then
		f:SetClampRectInsets(-15, 45, 15, -15)
	end
	
	if UISpecialFrames and type(tContains) == "function" and type(tinsert) == "function" then
		if not tContains(UISpecialFrames, self.FRAME_NAME) then
			tinsert(UISpecialFrames, self.FRAME_NAME)
		end
	end
	
	f:SetScript("OnDragStart", function(selfFrame)
		selfFrame:StartMoving()
	end)
	
	f:SetScript("OnDragStop", function(selfFrame)
		selfFrame:StopMovingOrSizing()
		UI:WINDOW_SaveWindowStateToDatabase()
	end)
	
	if f.SetResizeBounds then
		f:SetResizeBounds(680, 420)
	elseif f.SetMinResize then
		f:SetMinResize(680, 420)
	end
	
	local resize = CreateFrame("Button", nil, f)
	resize:SetSize(16, 16)
	resize:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
	resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resize:SetFrameStrata(f:GetFrameStrata())
	resize:SetFrameLevel(f:GetFrameLevel() + 20)
	resize:SetScript("OnMouseDown", function()
		f:StartSizing("BOTTOMRIGHT")
	end)
	resize:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		UI:WINDOW_SaveWindowStateToDatabase()
		if UI.RIGHTDOCK_ReflowDock then
			UI:RIGHTDOCK_ReflowDock()
		end
	end)
	
	local inset = f.Inset or f.inset
	local content = CreateFrame("Frame", nil, f)
	content:SetFrameStrata(f:GetFrameStrata())
	content:SetFrameLevel(f:GetFrameLevel() + 1)
	
	if inset then
		content:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -6)
		content:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -6, 6)
	else
		content:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -46)
		content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
	end
	
	local bg = content:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(content)
	bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	bg:SetBlendMode("BLEND")
	bg:SetVertexColor(0, 0, 0, 0.30)
	
	if f.CloseButton then
		f.CloseButton:ClearAllPoints()
		f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	
		f.CloseButton:SetFrameStrata(f:GetFrameStrata())
		f.CloseButton:SetFrameLevel(f:GetFrameLevel() + 500)
		f.CloseButton:Show()
	
		local n = f.CloseButton:GetNormalTexture()
		if n then n:SetDrawLayer("OVERLAY", 7) end
		local p = f.CloseButton:GetPushedTexture()
		if p then p:SetDrawLayer("OVERLAY", 7) end
		local h = f.CloseButton:GetHighlightTexture()
		if h then h:SetDrawLayer("OVERLAY", 7) end
	
		f.CloseButton:SetScript("OnClick", function()
			UI:WINDOW_SaveWindowStateToDatabase()
			f:Hide()
		end)
	end
	
	f:SetScript("OnShow", function()
		UI:WINDOW_SetIconFallback()
	
		if UI.RIGHTDOCK_EnsureDockStateIsInitialized then
			UI:RIGHTDOCK_EnsureDockStateIsInitialized(f)
		end
	
		if UI.RIGHTDOCK_SeedRightDockPlaceholdersIfMissing then
			UI:RIGHTDOCK_SeedRightDockPlaceholdersIfMissing()
		end
	
		if UI.RIGHTDOCK_ReflowDock then
			UI:RIGHTDOCK_ReflowDock()
		end
	
		local desired = UI._page
		if (not desired or desired == "") and UI.DB_GetActivePageOrDefault then
			desired = UI:DB_GetActivePageOrDefault()
		end
		if UI.PAGES_NavigateToPage then
			UI:PAGES_NavigateToPage(desired)
		end
	end)
	
	f:SetScript("OnHide", function()
		UI:WINDOW_SaveWindowStateToDatabase()
		if UI.ACE_ReleaseAceRootIfPresent then
			UI:ACE_ReleaseAceRootIfPresent()
		end
	end)
	
	f:Hide()
	
	self._frame = f
	self._content = content
	
	self:WINDOW_SetIconFallback()
	self:WINDOW_SetWindowTitle(self.DISPLAY_NAME)
	end
	
	-- ---------------------------------------------------------------------------
	--	Shows the window (initializes if needed)
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:WINDOW_ShowWindow()
	if not self._inited and self.Init then
		self:Init()
	end
	if self._frame then
		self:WINDOW_ApplyWindowStateFromDatabase()
		self._frame:Show()
	end
	end
	
	-- ---------------------------------------------------------------------------
	--	Hides the window
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:WINDOW_HideWindow()
	if self._frame then
		self._frame:Hide()
	end
	end
	
	-- ---------------------------------------------------------------------------
	--	Opens the window and navigates to a page (idempotent)
	--
	--	@param pageName string|nil
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:WINDOW_OpenWindowAndNavigate(pageName)
	local wasShown = (self._frame and self._frame:IsShown()) and true or false
	self:WINDOW_ShowWindow()
	
	local desired = (type(pageName) == "string" and pageName ~= "" and pageName) or self._page
	if (not desired or desired == "") and self.DB_GetActivePageOrDefault then
		desired = self:DB_GetActivePageOrDefault()
	end
	
	if self.PAGES_NavigateToPage then
		self:PAGES_NavigateToPage(desired)
	end
	
	if wasShown then
		return
	end
	end
