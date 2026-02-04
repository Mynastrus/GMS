	-- ============================================================================
	--	GMS/Core/UI.lua
	--	UI Shell (ButtonFrameTemplate) + AceGUI Content (embedded) + RightDock Tabs
	--	- KEIN _G, KEIN addonTable
	--	- Zugriff auf GMS ausschließlich über AceAddon Registry
	--	- Fenster: Blizzard ButtonFrameTemplate (Move/Resize/ESC close)
	--	- Content: AceGUI Widgets in einem WoW-Container-Frame (Fill)
	--	- Persistenz: AceDB-3.0 (Position + Größe + aktive Page)
	--	- Clamp: immer mind. 15px vom Rand (SetClampRectInsets) + RightDock Platz
	--	- Pages: RegisterPage + Navigate (AceGUI Root Fill)
	--	- RightDock: Tabs/Icons oben + unten rechts (selectable) + korrekte FrameLevel
	--	- Bridge: GMS:UI_IsReady() + GMS:UI_Open(pageName)
	-- ============================================================================

	local LibStub = LibStub
	if not LibStub then return end

	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end

	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end

	local AceGUI = LibStub("AceGUI-3.0", true)
	local AceDB = LibStub("AceDB-3.0", true)

	local MODULE_NAME = "UI"
	local DISPLAY_NAME = "Guild Management System"
	local FRAME_NAME = "GMS_MainFrame"

	-- ---------------------------------------------------------------------------
	--	Log-Helfer (nutzt GMS Logging Buffer)
	--	@param level string
	--	@param message string
	--	@param context table|nil
	-- ---------------------------------------------------------------------------
	local function Log(level, message, context)
		if level == "ERROR" then
			if GMS.LOG_Error then GMS:LOG_Error(MODULE_NAME, message, context) end
		elseif level == "WARN" then
			if GMS.LOG_Warn then GMS:LOG_Warn(MODULE_NAME, message, context) end
		elseif level == "DEBUG" then
			if GMS.LOG_Debug then GMS:LOG_Debug(MODULE_NAME, message, context) end
		else
			if GMS.LOG_Info then GMS:LOG_Info(MODULE_NAME, message, context) end
		end
	end

	-- ###########################################################################
	-- #	ACE SUBMODULE
	-- ###########################################################################

	local UI = GMS:GetModule(MODULE_NAME, true)
	if not UI then
		UI = GMS:NewModule(
			MODULE_NAME,
			"AceConsole-3.0",
			"AceEvent-3.0"
		)
	end

	GMS.UI = UI

	-- ###########################################################################
	-- #	DEFAULTS / STATE
	-- ###########################################################################

	local DEFAULTS = {
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

	UI.db = UI.db or nil
	UI._inited = UI._inited or false
	UI._frame = UI._frame or nil
	UI._content = UI._content or nil
	UI._root = UI._root or nil
	UI._page = UI._page or nil

	UI._pages = UI._pages or {}
	UI._order = UI._order or {}

	UI._rightDockSeeded = UI._rightDockSeeded or false
	UI._rightDock = UI._rightDock or {
		inited = false,
		parent = nil,
		top = { order = {}, entries = {} },
		bottom = { order = {}, entries = {} },
		all = {},
	}

	-- ---------------------------------------------------------------------------
	--	RightDock Config
	-- ---------------------------------------------------------------------------
	UI.RightDockConfig = UI.RightDockConfig or {
		offsetX = -10,
		topOffsetY = 26,
		bottomOffsetY = 1,
		slotWidth = 46,
		slotHeight = 38,
		slotGap = 2,
		buttonSize = 32, --32
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
		normalTexture = "", --"Interface\\Buttons\\UI-Quickslot2",
		pushedTexture = "Interface\\Buttons\\UI-Quickslot-Depress",
		hoverTexture = "Interface\\Buttons\\ButtonHilight-Square",
		selectedGlowTexture = "Interface\\Buttons\\UI-ActionButton-Border",
		selectedGlowColor = { 1, 0.82, 0.2, 1 },
		selectedGlowPad = 32,
		iconTexCoord = { 0.07, 0.93, 0.07, 0.93 },
	}

	-- ###########################################################################
	-- #	INTERNAL HELPERS
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Führt eine Funktion sicher aus (pcall) und loggt Fehler
	--	@param fn function|nil
	--	@param ... any
	--	@return boolean ok
	-- ---------------------------------------------------------------------------
	local function SafeCall(fn, ...)
		if type(fn) ~= "function" then return false end
		local ok, err = pcall(fn, ...)
		if not ok then
			Log("ERROR", "UI Fehler", { err = tostring(err) })
			if GMS and GMS.Print then
				GMS:Print("UI Fehler: " .. tostring(err))
			end
		end
		return ok
	end

	-- ---------------------------------------------------------------------------
	--	Sortiert registrierte Pages nach order + id
	--	@return nil
	-- ---------------------------------------------------------------------------
	local function SortPages()
		if type(wipe) == "function" then
			wipe(UI._order)
		else
			for k in pairs(UI._order) do UI._order[k] = nil end
		end

		for id, p in pairs(UI._pages) do
			UI._order[#UI._order + 1] = { id = id, order = p.order or 9999 }
		end

		table.sort(UI._order, function(a, b)
			if a.order == b.order then
				return tostring(a.id) < tostring(b.id)
			end
			return a.order < b.order
		end)
	end

	-- ---------------------------------------------------------------------------
	--	Setzt einen Navigation-Context (z. B. guid), der von der Ziel-Page gelesen werden kann
	--
	--	@param ctx table|nil
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:SetNavigationContext(ctx)
		self._navContext = (type(ctx) == "table" and ctx) or nil
	end

	-- ---------------------------------------------------------------------------
	--	Gibt den letzten Navigation-Context zurück (oder nil)
	--
	--	@param consume boolean|nil
	--		- wenn true: Context wird nach dem Lesen gelöscht
	--	@return table|nil
	-- ---------------------------------------------------------------------------
	function UI:GetNavigationContext(consume)
		local ctx = self._navContext
		if consume == true then
			self._navContext = nil
		end
		return ctx
	end
	
	-- ---------------------------------------------------------------------------
	--	Gibt die Window-DB zurück (Profile)
	--	@return table
	-- ---------------------------------------------------------------------------
	local function GetWindowDB()
		if not UI.db then
			return DEFAULTS.profile.window
		end

		UI.db.profile.window = UI.db.profile.window or {}
		return UI.db.profile.window
	end

	-- ---------------------------------------------------------------------------
	--	Speichert aktive Page in DB
	--	@param pageName string
	-- ---------------------------------------------------------------------------
	local function SaveActivePage(pageName)
		if not UI.db then return end
		local wdb = GetWindowDB()
		wdb.activePage = tostring(pageName or "home")
	end

	-- ---------------------------------------------------------------------------
	--	Liest aktive Page aus DB (Fallback home)
	--	@return string
	-- ---------------------------------------------------------------------------
	local function GetActivePage()
		local wdb = GetWindowDB()
		return tostring(wdb.activePage or "home")
	end

	-- ###########################################################################
	-- #	TITLE / PORTRAIT
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Setzt den Fenstertitel (Custom FontString)
	--	@param text string|nil
	-- ---------------------------------------------------------------------------
	function UI:SetWindowTitle(text)
		if self._frame and self._frame.GMS_TitleText then
			self._frame.GMS_TitleText:SetText(tostring(text or ""))
		end
	end

	-- ---------------------------------------------------------------------------
	--	Setzt das Fenster-Icon (Portrait) sauber mit Fallback
	-- ---------------------------------------------------------------------------
	function UI:SetIconFallback()
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

	-- ###########################################################################
	-- #	ACEGUI EMBEDDING
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Released den AceGUI Root (falls vorhanden)
	-- ---------------------------------------------------------------------------
	function UI:ReleaseAceRoot()
		if self._root and AceGUI then
			AceGUI:Release(self._root)
		end
		self._root = nil
	end

	-- ---------------------------------------------------------------------------
	--	Erstellt den AceGUI Root (SimpleGroup Fill) im Content-Frame
	-- ---------------------------------------------------------------------------
	function UI:EnsureAceRoot()
		if not AceGUI or not self._content then return end

		self:ReleaseAceRoot()

		local root = AceGUI:Create("SimpleGroup")
		root:SetLayout("Fill")
		root.frame:SetParent(self._content)
		root.frame:ClearAllPoints()
		root.frame:SetAllPoints(self._content)
		root.frame:Show()

		self._root = root
	end

	-- ###########################################################################
	-- #	PERSISTENZ (POSITION / SIZE)
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Wendet gespeicherte Fenster-Position + Größe an
	-- ---------------------------------------------------------------------------
	function UI:ApplyWindowState()
		if not self._frame then return end

		local wdb = GetWindowDB()

		self._frame:ClearAllPoints()
		self._frame:SetPoint(
			wdb.point or "CENTER",
			UIParent,
			wdb.relPoint or "CENTER",
			wdb.x or 0,
			wdb.y or 0
		)

		self._frame:SetSize(
			wdb.w or DEFAULTS.profile.window.w,
			wdb.h or DEFAULTS.profile.window.h
		)
	end

	-- ---------------------------------------------------------------------------
	--	Speichert aktuelle Fenster-Position + Größe in DB
	-- ---------------------------------------------------------------------------
	function UI:SaveWindowState()
		if not self._frame or not self.db then return end

		local wdb = GetWindowDB()

		local w, h = self._frame:GetSize()
		wdb.w = math.floor(((w or DEFAULTS.profile.window.w) + 0.5))
		wdb.h = math.floor(((h or DEFAULTS.profile.window.h) + 0.5))

		local point, _, relPoint, xOfs, yOfs = self._frame:GetPoint(1)
		wdb.point = point or "CENTER"
		wdb.relPoint = relPoint or "CENTER"
		wdb.x = math.floor(((xOfs or 0) + 0.5))
		wdb.y = math.floor(((yOfs or 0) + 0.5))
	end

	-- ---------------------------------------------------------------------------
	--	Setzt Fenster-DB auf Defaults zurück und wendet sie an
	-- ---------------------------------------------------------------------------
	function UI:ResetWindowToDefaults()
		if not self.db then return end
		self.db.profile.window = CopyTable(DEFAULTS.profile.window)
		if self._frame then
			self:ApplyWindowState()
			self:Navigate(GetActivePage())
			self:ReflowRightDock()
		end
	end

	-- ###########################################################################
	-- #	RIGHT DOCK (TABS) + FRAMELEVEL FIX
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Initialisiert RightDock State und Parent
	--	@param parent Frame|nil
	-- ---------------------------------------------------------------------------
	function UI:RightDockEnsure(parent)
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
	--	Setzt Slot-Backdrop
	--	@param slot Frame
	-- ---------------------------------------------------------------------------
	function UI:RightDockApplySlotBackdrop(slot)
		local cfg = self.RightDockConfig
		if slot and slot.SetBackdrop and cfg and cfg.slotBackdrop then
			slot:SetBackdrop(cfg.slotBackdrop)
		end
	end

	-- ---------------------------------------------------------------------------
	--	Setzt Selection-Glow an/aus
	--	@param entry table
	--	@param selected boolean
	-- ---------------------------------------------------------------------------
	function UI:RightDockSetSelected(entry, selected)
		if entry and entry.button and entry.button._glow then
			entry.button._glow:SetShown(selected and true or false)
		end
		if entry and entry.button then
			entry.button._selected = selected and true or false
		end
	end

	-- ---------------------------------------------------------------------------
	--	Markiert einen Dock-Eintrag als selected (optional exklusiv)
	--	@param id string
	--	@param selected boolean
	--	@param exclusive boolean|nil
	-- ---------------------------------------------------------------------------
	function UI:SetRightDockSelected(id, selected, exclusive)
		self:RightDockEnsure()
		local entry = self._rightDock.all[id]
		if not entry then return end

		if exclusive ~= false then
			for otherId, otherEntry in pairs(self._rightDock.all) do
				if otherId ~= id then
					self:RightDockSetSelected(otherEntry, false)
				end
			end
		end

		self:RightDockSetSelected(entry, selected)
	end

	-- ---------------------------------------------------------------------------
	--	Reflow: Positioniert Slots oben/unten rechts
	-- ---------------------------------------------------------------------------
	function UI:ReflowRightDock()
		if not self._frame then return end

		self:RightDockEnsure(self._frame)
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
	--	Fügt ein RightDock Icon hinzu (lane top|bottom) + korrekte FrameLevel
	--	@param lane string
	--	@param opts table
	--	@return table|nil entry
	-- ---------------------------------------------------------------------------
	function UI:AddRightDockIcon(lane, opts)
		opts = opts or {}
		lane = (lane == "bottom") and "bottom" or "top"

		self:CreateFrame()
		self:RightDockEnsure(self._frame)

		local cfg = self.RightDockConfig
		local id = tostring(opts.id or "")
		if id == "" then return nil end

		if self._rightDock.all[id] then
			return self._rightDock.all[id]
		end

		local st = (lane == "bottom") and self._rightDock.bottom or self._rightDock.top

		local parent = self._rightDock.parent
		local parentStrata = parent and parent:GetFrameStrata() or "DIALOG"
		local parentLevel = parent and parent:GetFrameLevel() or 20

		local slot = CreateFrame("Frame", nil, parent, "BackdropTemplate")
		slot:SetSize(cfg.slotWidth, cfg.slotHeight)
		slot:SetFrameStrata(parentStrata)
		--GMS:Print(parentLevel)
		slot:SetFrameLevel(parentLevel - 10)

		self:RightDockApplySlotBackdrop(slot)

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
				self:SetRightDockSelected(id, true, (opts.exclusive ~= false))
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
			self:RightDockSetSelected(entry, true)
		end

		self:ReflowRightDock()
		return entry
	end

	-- ---------------------------------------------------------------------------
	--	Shortcut: AddRightDockIconTop
	--	@param opts table
	-- ---------------------------------------------------------------------------
	function UI:AddRightDockIconTop(opts)
		return self:AddRightDockIcon("top", opts)
	end

	-- ---------------------------------------------------------------------------
	--	Shortcut: AddRightDockIconBottom
	--	@param opts table
	-- ---------------------------------------------------------------------------
	function UI:AddRightDockIconBottom(opts)
		return self:AddRightDockIcon("bottom", opts)
	end

	-- ---------------------------------------------------------------------------
	--	Seed: Default Tabs (Start + Options) als Platzhalter
	-- ---------------------------------------------------------------------------
	function UI:SeedRightDockPlaceholders()
		self:AddRightDockIconTop({
			id = "home",
			order = 1,
			selectable = true,
			selected = true,
			icon = "Interface\\Icons\\INV_Misc_Note_05",
			tooltipTitle = "Dashboard",
			tooltipText = "Zeigt das Dashboard des Addons an",
			onClick = function()
				UI:Navigate("home")
			end,
		})

		self:AddRightDockIconBottom({
			id = "options",
			order = 1,
			selectable = true,
			icon = "Interface\\Icons\\Trade_Engineering",
			tooltipTitle = "Optionen",
			tooltipText = "Einstellungen",
			onClick = function()
				UI:Navigate("OPTIONS")
			end,
		})
	end

	-- ###########################################################################
	-- #	PAGES
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Registriert eine Page
	--	@param id string
	--	@param order number
	--	@param title string
	--	@param buildFn function(root:AceGUIWidget, id:string)
	-- ---------------------------------------------------------------------------
	function UI:RegisterPage(id, order, title, buildFn)
		if not id then return end
		self._pages[id] = {
			order = order or 9999,
			title = title or tostring(id),
			build = buildFn,
		}
		SortPages()
	end

	-- ---------------------------------------------------------------------------
	--	Navigiert zu einer Page und baut den AceGUI Content
	--	- Special: "OPTIONS" versucht GMS.Options:EmbedInto(root.frame)
	--	@param id string
	-- ---------------------------------------------------------------------------
	function UI:Navigate(id)
		if not self._inited then
			self:Init()
		end

		if not self._frame then
			return
		end

		id = tostring(id or "")
		if id == "" then
			id = GetActivePage()
		end

		if id ~= "OPTIONS" and not self._pages[id] then
			if self._order[1] then
				id = self._order[1].id
			else
				id = "home"
			end
		end

		self._page = id
		SaveActivePage(id)

		self:EnsureAceRoot()
		if not self._root then return end

		self._root:ReleaseChildren()

		if id == "OPTIONS" then
			self:SetWindowTitle(DISPLAY_NAME .. "   |cffCCCCCCOptionen|r")

			local holder = AceGUI:Create("SimpleGroup")
			holder:SetLayout("Fill")
			holder:SetFullWidth(true)
			holder:SetFullHeight(true)
			self._root:AddChild(holder)

			if GMS.Options and GMS.Options.EmbedInto then
				SafeCall(GMS.Options.EmbedInto, GMS.Options, holder.frame)
			else
				local lbl = AceGUI:Create("Label")
				lbl:SetFullWidth(true)
				lbl:SetText("Options sind nicht verfügbar.")
				self._root:AddChild(lbl)
			end

			self:SetRightDockSelected("options", true, true)
			return
		end

		local p = self._pages[id]
		self:SetWindowTitle(DISPLAY_NAME .. "   |cffCCCCCC" .. tostring((p and p.title) or id) .. "|r")

		if p and p.build then
			SafeCall(p.build, self._root, id)
		end

		self:SetRightDockSelected(id, true, true)
	end

		-- ---------------------------------------------------------------------------
	--	Erstellt eine Region (Frame) am MainFrame und embedded AceGUI Root (Fill)
	--	@param regionKey string ("HEADER"|"CONTENT"|"STATUS")
	--	@param parent Frame
	--	@param points table
	--	@return AceGUIWidget|nil root
	-- ---------------------------------------------------------------------------
	function UI:INTERNAL_CreateRegion(regionKey, parent, points)
		if not AceGUI or not parent then return nil end
		if not self._regions then return nil end
	
		local r = self._regions[regionKey]
		if r and r.frame and r.root then
			return r.root
		end
	
		local regionFrame = CreateFrame("Frame", nil, parent)
		regionFrame:ClearAllPoints()
		for i = 1, #points do
			local p = points[i]
			regionFrame:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end
	
		regionFrame:SetFrameStrata(parent:GetFrameStrata())
		regionFrame:SetFrameLevel(parent:GetFrameLevel() + 1)
	
		local root = AceGUI:Create("SimpleGroup")
		root:SetLayout("Fill")
		root:SetFullWidth(true)
		root:SetFullHeight(true)
	
		root.frame:SetParent(regionFrame)
		root.frame:ClearAllPoints()
		root.frame:SetAllPoints(regionFrame)
		root.frame:Show()
	
		self._regions[regionKey] = { frame = regionFrame, root = root }
		return root
	end
	
	-- ---------------------------------------------------------------------------
	--	Gibt Region Root zurück (AceGUI SimpleGroup)
	--	@param regionKey string
	--	@return AceGUIWidget|nil
	-- ---------------------------------------------------------------------------
	function UI:GetRegionRoot(regionKey)
		if not self._regions then return nil end
		local r = self._regions[regionKey]
		return r and r.root or nil
	end
	
	-- ---------------------------------------------------------------------------
	--	Gibt Region Frame zurück (Container Frame)
	--	@param regionKey string
	--	@return Frame|nil
	-- ---------------------------------------------------------------------------
	function UI:GetRegionFrame(regionKey)
		if not self._regions then return nil end
		local r = self._regions[regionKey]
		return r and r.frame or nil
	end
	
	-- ---------------------------------------------------------------------------
	--	Convenience Getter
	-- ---------------------------------------------------------------------------
	function UI:GetHeader()
		return self:GetRegionRoot("HEADER")
	end
	
	function UI:GetContent()
		return self:GetRegionRoot("CONTENT")
	end
	
	function UI:GetStatus()
		return self:GetRegionRoot("STATUS")
	end
	
	-- ---------------------------------------------------------------------------
	--	Leert nur CONTENT (Pagination hängt ausschließlich hier)
	-- ---------------------------------------------------------------------------
	function UI:ClearContentRegion()
		local root = self:GetContent()
		if root and root.ReleaseChildren then
			root:ReleaseChildren()
		end
	end
	
	-- ---------------------------------------------------------------------------
	--	Optional: Header/Status explizit leeren (nicht automatisch bei Navigate)
	-- ---------------------------------------------------------------------------
	function UI:ClearHeaderRegion()
		local root = self:GetHeader()
		if root and root.ReleaseChildren then
			root:ReleaseChildren()
		end
	end
	
	function UI:ClearStatusRegion()
		local root = self:GetStatus()
		if root and root.ReleaseChildren then
			root:ReleaseChildren()
		end
	end


	
	-- ###########################################################################
	-- #	FRAME (BUTTONFRAMETEMPLATE)
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Erstellt das Hauptfenster (einmalig)
	-- ---------------------------------------------------------------------------
	function UI:CreateFrame()
		if self._frame then return end

		local f = CreateFrame("Frame", FRAME_NAME, UIParent, "ButtonFrameTemplate")
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
			if not tContains(UISpecialFrames, FRAME_NAME) then
				tinsert(UISpecialFrames, FRAME_NAME)
			end
		end

		f:SetScript("OnDragStart", function(selfFrame)
			selfFrame:StartMoving()
		end)

		f:SetScript("OnDragStop", function(selfFrame)
			selfFrame:StopMovingOrSizing()
			UI:SaveWindowState()
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
			UI:SaveWindowState()
			UI:ReflowRightDock()
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
			-- Sicher nach oben & sichtbar
			f.CloseButton:ClearAllPoints()
			f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

			f.CloseButton:SetFrameStrata(f:GetFrameStrata())
			f.CloseButton:SetFrameLevel(f:GetFrameLevel() + 500)
			f.CloseButton:Show()

			-- WICHTIG: Texturen nach vorne holen (sonst "klickbar aber unsichtbar")
			local n = f.CloseButton:GetNormalTexture()
			if n then n:SetDrawLayer("OVERLAY", 7) end

			local p = f.CloseButton:GetPushedTexture()
			if p then p:SetDrawLayer("OVERLAY", 7) end

			local h = f.CloseButton:GetHighlightTexture()
			if h then h:SetDrawLayer("OVERLAY", 7) end

			f.CloseButton:SetScript("OnClick", function()
				UI:SaveWindowState()
				f:Hide()
			end)
		end

		f:SetScript("OnShow", function()
			UI:SetIconFallback()

			UI:RightDockEnsure(f)

			if not UI._rightDockSeeded then
				UI:SeedRightDockPlaceholders()
				UI._rightDockSeeded = true
			end

			UI:ReflowRightDock()

			local desired = UI._page or GetActivePage()
			UI:Navigate(desired)
		end)

		f:SetScript("OnHide", function()
			UI:SaveWindowState()
			UI:ReleaseAceRoot()
		end)

		f:Hide()

		self._frame = f
		self._content = content

		self:SetIconFallback()
		self:SetWindowTitle(DISPLAY_NAME)
	end

	-- ###########################################################################
	-- #	PUBLIC API (INIT / SHOW / HIDE / TOGGLE / OPEN)
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Initialisiert UI (DB, Frame, Default-Page)
	-- ---------------------------------------------------------------------------
	function UI:Init()
		if self._inited then return end
		self._inited = true

		if AceDB then
			self.db = AceDB:New("GMS_UIDB", DEFAULTS, true)
		end

		self:CreateFrame()
		self:ApplyWindowState()

		if not next(self._pages) then
			self:RegisterPage("home", 1, "Dashboard", function(root)
				if not AceGUI then
					return
				end

				local title = AceGUI:Create("Label")
				title:SetText("|cff03A9F4GMS|r – UI ist geladen.")
				title:SetFontObject(GameFontNormalLarge)
				title:SetFullWidth(true)
				root:AddChild(title)

				local hint = AceGUI:Create("Label")
				hint:SetText("Tabs rechts: Klick öffnet Pages. Pages registrieren: GMS.UI:RegisterPage(id, order, title, buildFn)")
				hint:SetFullWidth(true)
				root:AddChild(hint)

				local resetBtn = AceGUI:Create("Button")
				resetBtn:SetText("Fenster zurücksetzen (Position/Größe)")
				resetBtn:SetFullWidth(true)
				resetBtn:SetCallback("OnClick", function()
					UI:ResetWindowToDefaults()
				end)
				root:AddChild(resetBtn)
			end)

			SortPages()
		end

		Log("DEBUG", "UI Init complete", nil)
	end

	-- ---------------------------------------------------------------------------
	--	Zeigt das Fenster an (Init falls nötig)
	-- ---------------------------------------------------------------------------
	function UI:Show()
		if not self._inited then
			self:Init()
		end
		if self._frame then
			self:ApplyWindowState()
			self._frame:Show()
		end
	end

	-- ---------------------------------------------------------------------------
	--	Versteckt das Fenster
	-- ---------------------------------------------------------------------------
	function UI:Hide()
		if self._frame then
			self._frame:Hide()
		end
	end

	-- ---------------------------------------------------------------------------
	--	Toggle (Init falls nötig)
	-- ---------------------------------------------------------------------------
	function UI:Toggle(pageName)
		if not self._inited then
			self:Init()
		end
		if not self._frame then return end
		if self._frame:IsShown() then
			self:Hide()
		else
			self:Open(pageName)
		end
	end

	-- ---------------------------------------------------------------------------
	--	Öffnet UI und navigiert optional zu pageName
	--	- Idempotent: wenn offen, nur Page wechseln
	--	@param pageName string|nil
	-- ---------------------------------------------------------------------------
	function UI:Open(pageName)
		local wasShown = (self._frame and self._frame:IsShown()) and true or false
		self:Show()
		local desired = (type(pageName) == "string" and pageName ~= "" and pageName) or (self._page or GetActivePage())
		if wasShown then
			self:Navigate(desired)
		else
			self:Navigate(desired)
		end
	end

	-- ---------------------------------------------------------------------------
	--	Schließt UI (alias Hide)
	-- ---------------------------------------------------------------------------
	function UI:Close()
		self:Hide()
	end

	-- ---------------------------------------------------------------------------
	--	Prüft ob UI bereit ist
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function UI:IsReady()
		return self._inited == true and self._frame ~= nil
	end

	-- ============================================================================
	--	PATCH: UI registriert "/gms ui"
	--	- Ace-only Standard: Zugriff auf SlashCommands über GMS:GetModule(...)
	--	- Kein _G, kein addonTable
	-- ============================================================================

	-- ---------------------------------------------------------------------------
	--	Registriert den SubCommand "ui" bei SlashCommands (falls verfügbar)
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:RegisterUiSlashCommandIfAvailable()
		local SlashCommands = GMS:GetModule("SLASHCOMMANDS", true)
		if not SlashCommands or type(SlashCommands.API_RegisterSubCommand) ~= "function" then
			Log("WARN", "SlashCommands not available; cannot register /gms ui", nil)
			return
		end

		SlashCommands:API_RegisterSubCommand("ui", function(rest)
			UI:Open((type(rest) == "string" and rest ~= "" and rest) or nil)
		end, {
			help = "Öffnet die GMS UI (/gms ui [page])",
			alias = { "open" },
			owner = MODULE_NAME,
		})

		Log("INFO", "Registered subcommand: /gms ui", nil)
	end

	-- ###########################################################################
	-- #	GMS BRIDGE API
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Prüft, ob UI bereit ist
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function GMS:UI_IsReady()
		return type(GMS.UI) == "table" and type(GMS.UI.Open) == "function" and (GMS.UI.IsReady == nil or GMS.UI:IsReady() == true)
	end

	-- ---------------------------------------------------------------------------
	--	Öffnet UI über GMS
	--	@param pageName string|nil
	--	@return boolean
	-- ---------------------------------------------------------------------------
	function GMS:UI_Open(pageName)
		if not self:UI_IsReady() then
			if GMS.UI and GMS.UI.Init then
				GMS.UI:Init()
			end
		end

		if not self:UI_IsReady() then
			Log("WARN", "GMS:UI_Open failed (UI not ready)", { pageName = pageName })
			return false
		end

		GMS.UI:Open(type(pageName) == "string" and pageName or nil)
		return true
	end

	-- ###########################################################################
	-- #	LIFECYCLE
	-- ###########################################################################

	-- ---------------------------------------------------------------------------
	--	Ace Lifecycle: OnInitialize
	-- ---------------------------------------------------------------------------
	function UI:OnInitialize()
		self:Init()
	end

	-- ---------------------------------------------------------------------------
	--	Ace Lifecycle: OnEnable
	-- ---------------------------------------------------------------------------
	function UI:OnEnable()
		Log("DEBUG", "UI OnEnable", nil)
		self:RegisterUiSlashCommandIfAvailable()
	end

	-- ---------------------------------------------------------------------------
	--	Ace Lifecycle: OnDisable
	-- ---------------------------------------------------------------------------
	function UI:OnDisable()
		Log("DEBUG", "UI OnDisable", nil)
		self:Hide()
	end
