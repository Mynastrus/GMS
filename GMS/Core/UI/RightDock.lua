	
	-- ============================================================================
	--	GMS/Core/UI/RightDock.lua
	--	RightDock tabs/icons on the right side (top + bottom lanes)
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
	--	Ensures RightDock tables exist and binds parent if provided
	--
	--	@param parent Frame|nil
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:RIGHTDOCK_EnsureDockStateIsInitialized(parent)
	self._rightDock = self._rightDock or { inited = false, parent = nil, top = {}, bottom = {}, all = {} }
	self._rightDock.top = self._rightDock.top or { order = {}, entries = {} }
	self._rightDock.bottom = self._rightDock.bottom or { order = {}, entries = {} }
	self._rightDock.all = self._rightDock.all or {}
	
	if parent and not self._rightDock.parent then
		self._rightDock.parent = parent
	end
	
	self._rightDock.inited = true
	end
	
	-- ---------------------------------------------------------------------------
	--	Applies the slot backdrop settings
	--
	--	@param slot Frame
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:RIGHTDOCK_ApplySlotBackdrop(slot)
	local cfg = self.RightDockConfig
	if slot and slot.SetBackdrop and cfg and cfg.slotBackdrop then
		slot:SetBackdrop(cfg.slotBackdrop)
	end
	end
	
	-- ---------------------------------------------------------------------------
	--	Sets selected glow state on an entry
	--
	--	@param entry table
	--	@param selected boolean
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:RIGHTDOCK_SetSelectedState(entry, selected)
	if entry and entry.button and entry.button._glow then
		entry.button._glow:SetShown(selected and true or false)
	end
	if entry and entry.button then
		entry.button._selected = selected and true or false
	end
	end
	
	-- ---------------------------------------------------------------------------
	--	Marks an entry selected (optionally exclusive)
	--
	--	@param id string
	--	@param selected boolean
	--	@param exclusive boolean|nil
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:RIGHTDOCK_SetRightDockSelected(id, selected, exclusive)
	self:RIGHTDOCK_EnsureDockStateIsInitialized()
	local entry = self._rightDock.all[id]
	if not entry then return end
	
	if exclusive ~= false then
		for otherId, otherEntry in pairs(self._rightDock.all) do
			if otherId ~= id then
				self:RIGHTDOCK_SetSelectedState(otherEntry, false)
			end
		end
	end
	
	self:RIGHTDOCK_SetSelectedState(entry, selected)
	end
	
	-- ---------------------------------------------------------------------------
	--	Reflows the dock (positions slots top + bottom on the right)
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:RIGHTDOCK_ReflowDock()
	if not self._frame then return end
	
	self:RIGHTDOCK_EnsureDockStateIsInitialized(self._frame)
	local cfg = self.RightDockConfig
	
	local function sortLane(st)
		table.sort(st.order, function(a, b)
			return (a.order or 9999) < (b.order or 9999)
		end)
	end
	
	local function placeTop()
		local st = self._rightDock.top
		sortLane(st)
		for i, item in ipairs(st.order) do
			local entry = st.entries[item.id]
			if entry and entry.slot then
				entry.slot:ClearAllPoints()
				entry.slot:SetPoint(
					"TOPLEFT",
					self._rightDock.parent,
					"TOPRIGHT",
					cfg.offsetX,
					-(cfg.topOffsetY + (i - 1) * (cfg.slotHeight + cfg.slotGap))
				)
			end
		end
	end
	
	local function placeBottom()
		local st = self._rightDock.bottom
		sortLane(st)
		for i, item in ipairs(st.order) do
			local entry = st.entries[item.id]
			if entry and entry.slot then
				entry.slot:ClearAllPoints()
				entry.slot:SetPoint(
					"BOTTOMLEFT",
					self._rightDock.parent,
					"BOTTOMRIGHT",
					cfg.offsetX,
					(cfg.bottomOffsetY + (i - 1) * (cfg.slotHeight + cfg.slotGap))
				)
			end
		end
	end
	
	placeTop()
	placeBottom()
	end
	
	-- ---------------------------------------------------------------------------
	--	Adds a RightDock icon (lane: "top" or "bottom")
	--
	--	@param lane string
	--	@param opts table
	--	@return table|nil entry
	-- ---------------------------------------------------------------------------
	function UI:RIGHTDOCK_AddRightDockIcon(lane, opts)
	opts = opts or {}
	lane = (lane == "bottom") and "bottom" or "top"
	
	if self.WINDOW_CreateFrameIfMissing then
		self:WINDOW_CreateFrameIfMissing()
	end
	
	self:RIGHTDOCK_EnsureDockStateIsInitialized(self._frame)
	
	local cfg = self.RightDockConfig
	local id = tostring(opts.id or "")
	if id == "" then return nil end
	
	if self._rightDock.all[id] then
		return self._rightDock.all[id]
	end
	
	local st = (lane == "bottom") and self._rightDock.bottom or self._rightDock.top
	local parent = self._rightDock.parent
	local parentStrata = parent and parent:GetFrameStrata() or "DIALOG"
	local parentLevel = parent and parent:GetFrameLevel() or 200
	
	local slot = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	slot:SetSize(cfg.slotWidth, cfg.slotHeight)
	slot:SetFrameStrata(parentStrata)
	slot:SetFrameLevel(parentLevel - 10)
	
	self:RIGHTDOCK_ApplySlotBackdrop(slot)
	
	local btn = CreateFrame("Button", nil, slot, "BackdropTemplate")
	btn:SetSize(cfg.buttonSize, cfg.buttonSize)
	btn:SetPoint("CENTER", slot, "CENTER", cfg.buttonOffsetX or 0, cfg.buttonOffsetY or 0)
	btn:SetFrameStrata(parentStrata)
	btn:SetFrameLevel(slot:GetFrameLevel() + 1)
	
	btn:SetNormalTexture(cfg.normalTexture)
	btn:SetPushedTexture(cfg.pushedTexture)
	btn:SetHighlightTexture(cfg.hoverTexture, "ADD")
	
	do
		local nt = btn:GetNormalTexture()
		if nt then nt:ClearAllPoints(); nt:SetAllPoints(btn) end
		local pt = btn:GetPushedTexture()
		if pt then pt:ClearAllPoints(); pt:SetAllPoints(btn) end
		local ht = btn:GetHighlightTexture()
		if ht then ht:ClearAllPoints(); ht:SetAllPoints(btn) end
	end
	
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", btn, "TOPLEFT", cfg.iconInset, -cfg.iconInset)
	icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -cfg.iconInset, cfg.iconInset)
	icon:SetTexture(opts.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	local tc = cfg.iconTexCoord
	icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
	btn._icon = icon
	
	local glow = btn:CreateTexture(nil, "OVERLAY")
	glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
	glow:SetSize(cfg.buttonSize + cfg.selectedGlowPad, cfg.buttonSize + cfg.selectedGlowPad)
	glow:SetTexture(cfg.selectedGlowTexture)
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(unpack(cfg.selectedGlowColor))
	glow:Hide()
	btn._glow = glow
	
	btn:SetScript("OnEnter", function()
		if opts.tooltipTitle or opts.tooltipText then
			GameTooltip:SetOwner(slot, "ANCHOR_LEFT")
			if opts.tooltipTitle and opts.tooltipTitle ~= "" then
				GameTooltip:AddLine(opts.tooltipTitle, 1, 1, 1)
			end
			if opts.tooltipText and opts.tooltipText ~= "" then
				GameTooltip:AddLine(opts.tooltipText, 0.9, 0.9, 0.9, true)
			end
			GameTooltip:Show()
		end
	end)
	
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	
	btn:SetScript("OnClick", function(_, mouseButton)
		if opts.selectable then
			self:RIGHTDOCK_SetRightDockSelected(id, true, (opts.exclusive ~= false))
		end
		if type(opts.onClick) == "function" then
			pcall(opts.onClick, id, btn, mouseButton)
		end
	end)
	
	local entry = { id = id, lane = lane, slot = slot, button = btn }
	self._rightDock.all[id] = entry
	st.entries[id] = entry
	
	table.insert(st.order, { id = id, order = tonumber(opts.order) or (#st.order + 1) })
	
	if opts.selected then
		self:RIGHTDOCK_SetSelectedState(entry, true)
	end
	
	self:RIGHTDOCK_ReflowDock()
	return entry
	end
	
	-- ---------------------------------------------------------------------------
	--	Convenience wrapper: add icon to the top lane
	--
	--	@param opts table
	--	@return table|nil entry
	-- ---------------------------------------------------------------------------
	function UI:RIGHTDOCK_AddRightDockIconTop(opts)
	return self:RIGHTDOCK_AddRightDockIcon("top", opts)
	end
	
	-- ---------------------------------------------------------------------------
	--	Convenience wrapper: add icon to the bottom lane
	--
	--	@param opts table
	--	@return table|nil entry
	-- ---------------------------------------------------------------------------
	function UI:RIGHTDOCK_AddRightDockIconBottom(opts)
	return self:RIGHTDOCK_AddRightDockIcon("bottom", opts)
	end
	
	-- ---------------------------------------------------------------------------
	--	Seeds placeholder icons (home + options)
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:RIGHTDOCK_SeedRightDockPlaceholdersIfMissing()
	if self._rightDockSeeded then return end
	
	self:RIGHTDOCK_AddRightDockIconTop({
		id = "home",
		order = 1,
		selectable = true,
		selected = true,
		icon = "Interface\\Icons\\INV_Misc_Note_05",
		tooltipTitle = "Dashboard",
		tooltipText = "Zeigt das Dashboard des Addons an",
		onClick = function()
			if UI.PAGES_NavigateToPage then
				UI:PAGES_NavigateToPage("home")
			end
		end,
	})
	
	self:RIGHTDOCK_AddRightDockIconBottom({
		id = "options",
		order = 1,
		selectable = true,
		icon = "Interface\\Icons\\Trade_Engineering",
		tooltipTitle = "Optionen",
		tooltipText = "Einstellungen",
		onClick = function()
			if UI.PAGES_NavigateToPage then
				UI:PAGES_NavigateToPage("OPTIONS")
			end
		end,
	})
	
	self._rightDockSeeded = true
	end
