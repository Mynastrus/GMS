	
	-- ============================================================================
	--	GMS/Core/UI/Pages.lua
	--	Page registry + navigation
	-- ============================================================================
	
	local LibStub = LibStub
	if not LibStub then return end
	
	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end
	
	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end
	
	local UI = GMS:GetModule("UI", true)
	if not UI then return end
	
	local AceGUI = LibStub("AceGUI-3.0", true)
	
	UI.DISPLAY_NAME = UI.DISPLAY_NAME or "Guild Management System"
	
	-- ---------------------------------------------------------------------------
	--	SafeCall: executes a function via pcall and logs on error
	--
	--	@param fn function|nil
	--	@param ... any
	--	@return boolean ok
	-- ---------------------------------------------------------------------------
	function UI:INTERNAL_SafeCall(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, err = pcall(fn, ...)
	if not ok then
		if self.LOG_Error then
			self:LOG_Error("UI Fehler", { err = tostring(err) })
		end
		if GMS and GMS.Print then
			GMS:Print("UI Fehler: " .. tostring(err))
		end
	end
	return ok
	end
	
	-- ---------------------------------------------------------------------------
	--	Sorts pages into UI._order by (order, id)
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:PAGES_SortRegisteredPages()
	if type(wipe) == "function" then
		wipe(self._order)
	else
		for k in pairs(self._order) do self._order[k] = nil end
	end
	
	for id, p in pairs(self._pages) do
		self._order[#self._order + 1] = { id = id, order = p.order or 9999 }
	end
	
	table.sort(self._order, function(a, b)
		if a.order == b.order then
			return tostring(a.id) < tostring(b.id)
		end
		return a.order < b.order
	end)
	end
	
	-- ---------------------------------------------------------------------------
	--	Registers a page builder
	--
	--	@param id string
	--	@param order number
	--	@param title string
	--	@param buildFn function(root:AceGUIWidget, id:string)
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:PAGES_RegisterPage(id, order, title, buildFn)
	if not id then return end
	self._pages[id] = {
		order = order or 9999,
		title = title or tostring(id),
		build = buildFn,
	}
	self:PAGES_SortRegisteredPages()
	end
	
	-- ---------------------------------------------------------------------------
	--	Seeds the default "home" page if no pages are registered
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:PAGES_SeedDefaultPageIfMissing()
	if next(self._pages) then return end
	
	self:PAGES_RegisterPage("home", 1, "Dashboard", function(root)
		if not AceGUI then return end
	
		local title = AceGUI:Create("Label")
		title:SetText("|cff03A9F4GMS|r – UI ist geladen.")
		title:SetFontObject(GameFontNormalLarge)
		title:SetFullWidth(true)
		root:AddChild(title)
	
		local hint = AceGUI:Create("Label")
		hint:SetText("Tabs rechts: Klick öffnet Pages. Pages registrieren: GMS.UI:PAGES_RegisterPage(id, order, title, buildFn)")
		hint:SetFullWidth(true)
		root:AddChild(hint)
	
		local resetBtn = AceGUI:Create("Button")
		resetBtn:SetText("Fenster zurücksetzen (Position/Größe)")
		resetBtn:SetFullWidth(true)
		resetBtn:SetCallback("OnClick", function()
			if UI.WINDOW_ResetWindowToDefaults then
				UI:WINDOW_ResetWindowToDefaults()
			end
		end)
		root:AddChild(resetBtn)
	end)
	
	self:PAGES_SortRegisteredPages()
	end
	
	-- ---------------------------------------------------------------------------
	--	Navigates to a page and rebuilds AceGUI content
	--	- Special: id "OPTIONS" tries to embed GMS.Options into root
	--
	--	@param id string
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:PAGES_NavigateToPage(id)
	if not self._inited then
		if self.Init then
			self:Init()
		end
	end
	
	if not self._frame then
		return
	end
	
	id = tostring(id or "")
	if id == "" then
		if self.DB_GetActivePageOrDefault then
			id = self:DB_GetActivePageOrDefault()
		else
			id = "home"
		end
	end
	
	if id ~= "OPTIONS" and not self._pages[id] then
		if self._order[1] then
			id = self._order[1].id
		else
			id = "home"
		end
	end
	
	self._page = id
	if self.DB_SaveActivePage then
		self:DB_SaveActivePage(id)
	end
	
	if self.ACE_EnsureAceRootExists then
		self:ACE_EnsureAceRootExists()
	end
	if not self._root then return end
	
	if self.ACE_ReleaseChildrenFromRoot then
		self:ACE_ReleaseChildrenFromRoot()
	end
	
	if id == "OPTIONS" then
		if self.WINDOW_SetWindowTitle then
			self:WINDOW_SetWindowTitle(self.DISPLAY_NAME .. "   |cffCCCCCCOptionen|r")
		end
	
		if AceGUI then
			local holder = AceGUI:Create("SimpleGroup")
			holder:SetLayout("Fill")
			holder:SetFullWidth(true)
			holder:SetFullHeight(true)
			self._root:AddChild(holder)
	
			if GMS.Options and GMS.Options.EmbedInto then
				self:INTERNAL_SafeCall(GMS.Options.EmbedInto, GMS.Options, holder.frame)
			else
				local lbl = AceGUI:Create("Label")
				lbl:SetFullWidth(true)
				lbl:SetText("Options sind nicht verfügbar.")
				self._root:AddChild(lbl)
			end
		end
	
		if self.RIGHTDOCK_SetRightDockSelected then
			self:RIGHTDOCK_SetRightDockSelected("options", true, true)
		end
		return
	end
	
	local p = self._pages[id]
	if self.WINDOW_SetWindowTitle then
		self:WINDOW_SetWindowTitle(self.DISPLAY_NAME .. "   |cffCCCCCC" .. tostring((p and p.title) or id) .. "|r")
	end
	
	if p and p.build then
		self:INTERNAL_SafeCall(p.build, self._root, id)
	end
	
	if self.RIGHTDOCK_SetRightDockSelected then
		self:RIGHTDOCK_SetRightDockSelected(id, true, true)
	end
	end
