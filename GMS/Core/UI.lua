-- ============================================================================
--	GMS/Core/UI.lua
--	UI EXTENSION (no GMS:NewModule)
--	- Zugriff auf GMS über AceAddon Registry
--	- Style aligned with ChatLinks / SlashCommands Extensions
--	- ButtonFrameTemplate shell + embedded AceGUI regions
--	- RightDock Tabs (top/bottom) with safe FrameLevel/Strata
--	- DB: AceDB-3.0 optional (window pos/size + activePage)
--
--	IMPORTANT:
--	- "PAGES" is a self-contained section.
--	  If you remove that whole section, UI still loads/opens and shows fallback content.
--
--	Header/Footer:
--	- Header/Footer sind bewusst am MainFrame (f) verankert (nicht im Content/Inlay).
--	- UI._headerContent / UI._footerContent liefern die SimpleGroups zurück (nicht die Labels).
--
--	Bridge:
--	- GMS:UI_IsReady()
--	- GMS:UI_Open(pageName)
-- ============================================================================

local _G = _G
local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G                         = _G
local UIParent                   = UIParent
local CreateFrame                = CreateFrame
local GetTime                    = GetTime
local CopyTable                  = CopyTable
local tinsert                    = tinsert
local tContains                  = tContains
local UISpecialFrames            = UISpecialFrames
local GameFontNormalOutline      = GameFontNormalOutline
local GameFontNormalLarge        = GameFontNormalLarge
local GameFontNormalSmallOutline = GameFontNormalSmallOutline
---@diagnostic enable: undefined-global

-- ###########################################################################
-- #	METADATA (PROJECT STANDARD)
-- ###########################################################################

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "UI",
	SHORT_NAME   = "UI",
	DISPLAY_NAME = "Guild Management System",
	VERSION      = "1.0.4",
}

-- ###########################################################################
-- #	GLOBAL LOG BUFFER + LOCAL LOGGER (PROJECT STANDARD)
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return type(GetTime) == "function" and GetTime() or nil
end

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time   = now(),
		level  = tostring(level or "INFO"),
		type   = tostring(METADATA.TYPE or "UNKNOWN"),
		source = tostring(METADATA.SHORT_NAME or "UNKNOWN"),
		msg    = tostring(msg or ""),
	}

	local n = select("#", ...)
	if n > 0 then
		entry.data = {}
		for i = 1, n do
			entry.data[i] = select(i, ...)
		end
	end

	local buf = GMS._LOG_BUFFER
	local idx = #buf + 1
	buf[idx] = entry

	if type(GMS._LOG_NOTIFY) == "function" then
		pcall(GMS._LOG_NOTIFY, entry, idx)
	end
end

-- ###########################################################################

GMS:RegisterExtension({
	key = "UI",
	name = "UI",
	displayName = "UI",
	version = METADATA.VERSION,
	desc = "UI Shell & Page Handling",
})

local AceGUI = LibStub("AceGUI-3.0", true)
local AceDB  = LibStub("AceDB-3.0", true)

local EXT_NAME     = "UI"
local DISPLAY_NAME = "Guild Management System"
local FRAME_NAME   = "GMS_MainFrame"

-- ###########################################################################
-- #	EXT STATE (table on GMS)
-- ###########################################################################

GMS.UI = GMS.UI or {}
local UI = GMS.UI

UI.DISPLAY_NAME = METADATA.DISPLAY_NAME
UI._inited      = UI._inited or false
UI._navToken    = UI._navToken or 0
UI.db           = UI.db or nil

UI._frame        = UI._frame or nil
UI._content      = UI._content or nil
UI._regions      = UI._regions or {}
UI._fallbackRoot = UI._fallbackRoot or nil

UI._page       = UI._page or nil
UI._navContext = UI._navContext or nil

-- Header/Footer: Frames + Content-Groups (SimpleGroup) bewusst separat vom Content
UI._headerFrame       = UI._headerFrame or nil
UI._footerFrame       = UI._footerFrame or nil
UI._headerContent     = UI._headerContent or nil -- SimpleGroup (wird von außen befüllt)
UI._footerContent     = UI._footerContent or nil -- SimpleGroup (wird von außen befüllt)
UI._statusLabelWidget = UI._statusLabelWidget or nil -- AceGUI Label widget (optional)
UI._statusLabelFS     = UI._statusLabelFS or nil -- FontString für farbige Codes (optional)

local DEFAULTS = {
	profile = {
		window = {
			w = 900,
			h = 560,
			point = "CENTER",
			relPoint = "CENTER",
			x = 0,
			y = 0,
			activePage = "DASHBOARD",
		},
	},
}

-- ###########################################################################
-- #	INTERNAL HELPERS
-- ###########################################################################

local function TRIM(s)
	s = tostring(s or "")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, err = pcall(fn, ...)
	if not ok then
		LOCAL_LOG("ERROR", "UI error", tostring(err))
	end
	return ok
end

local function CopyTableSafe(src)
	if type(CopyTable) == "function" then
		return CopyTable(src)
	end
	local out = {}
	for k, v in pairs(src or {}) do
		if type(v) == "table" then
			local t = {}
			for kk, vv in pairs(v) do t[kk] = vv end
			out[k] = t
		else
			out[k] = v
		end
	end
	return out
end

-- UI options (migrated to RegisterModuleOptions API)
UI._options = UI._options or nil

local OPTIONS_DEFAULTS = {
	window = {
		w = 900,
		h = 560,
		point = "CENTER",
		relPoint = "CENTER",
		x = 0,
		y = 0,
		activePage = "home",
	},
}

function UI:InitializeOptions()
	-- Register profile-scoped UI options
	if GMS and type(GMS.RegisterModuleOptions) == "function" then
		pcall(function()
			GMS:RegisterModuleOptions("UI", OPTIONS_DEFAULTS, "PROFILE")
		end)
	end

	-- Retrieve options table
	if GMS and type(GMS.GetModuleOptions) == "function" then
		local ok, opts = pcall(GMS.GetModuleOptions, GMS, "UI")
		if ok and opts then
			self._options = opts
			LOCAL_LOG("INFO", "UI options initialized (PROFILE scope)")
		else
			LOCAL_LOG("WARN", "Failed to retrieve UI options")
		end
	end
end

local function GetWindowDB()
	if not UI._options then
		return DEFAULTS.profile.window
	end
	UI._options.window = UI._options.window or {}
	return UI._options.window
end

local function SaveActivePage(pageName)
	if not UI.db then return end
	local wdb = GetWindowDB()
	wdb.activePage = tostring(pageName or "DASHBOARD")
end

local function GetActivePage()
	local wdb = GetWindowDB()
	return tostring(wdb.activePage or "DASHBOARD")
end

-- ###########################################################################
-- #	NAV CONTEXT (public)
-- ###########################################################################

function UI:SetNavigationContext(ctx)
	self._navContext = (type(ctx) == "table" and ctx) or nil
end

function UI:GetNavigationContext(consume)
	local ctx = self._navContext
	if consume == true then
		self._navContext = nil
	end
	return ctx
end

-- ###########################################################################
-- #	HEADER / FOOTER API (frames + content groups)
-- ###########################################################################

function UI:GetHeaderFrame() return self._headerFrame end

function UI:GetFooterFrame() return self._footerFrame end

function UI:GetContentFrame() return self._content end

-- Diese beiden sind die "eigentlichen" Content-Container (SimpleGroup), die Pages/Extensions befüllen
function UI:GetHeaderContent() return self._headerContent end

function UI:GetFooterContent() return self._footerContent end

function UI:Header_Clear()
	local g = self._headerContent
	if g and g.ReleaseChildren then
		g:ReleaseChildren()
	end
end

function UI:Footer_Clear()
	local g = self._footerContent
	if g and g.ReleaseChildren then
		g:ReleaseChildren()
	end
	self._statusLabelWidget = nil
	self._statusLabelFS = nil
end

-- Status-Text: nutzt FontString (für Farbcodes), aber hängt als Label im FooterContent
function UI:SetStatusText(msg)
	msg = tostring(msg or "")
	if not AceGUI then return end

	local g = self._footerContent
	if not g then return end

	if not self._statusLabelWidget then
		local lbl = AceGUI:Create("Label")
		lbl:SetFullWidth(true)

		if lbl.label then
			lbl.label:SetFontObject(GameFontNormalSmallOutline)
			lbl.label:SetJustifyH("LEFT")
			lbl.label:SetJustifyV("MIDDLE")
		end

		g:AddChild(lbl)

		self._statusLabelWidget = lbl
		self._statusLabelFS = lbl.label
	end

	if self._statusLabelFS and self._statusLabelFS.SetText then
		self._statusLabelFS:SetText(msg) -- Farbcodes ok
	elseif self._statusLabelWidget and self._statusLabelWidget.SetText then
		self._statusLabelWidget:SetText(msg)
	end
end

-- ###########################################################################
-- #	HEADER BUILDERS (3 Varianten) + Default
-- ###########################################################################

local function Header_EnsureLayout()
	if UI._headerContent and UI._headerContent.SetLayout then
		-- Header ist kein "Fill", weil mehrere Widgets horizontal rein sollen
		UI._headerContent:SetLayout("Flow")
	end
end

-- 1) Icon + Text (typischer Header)
function UI:Header_BuildIconText(opts)
	opts = opts or {}
	if not AceGUI then return false end
	if not self._headerContent then return false end

	self:Header_Clear()
	Header_EnsureLayout()

	local iconPath = tostring(opts.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	local text = tostring(opts.text or "")
	local sub = tostring(opts.subtext or "")

	local icon = AceGUI:Create("Icon")
	icon:SetImage(iconPath)
	icon:SetImageSize(18, 18)
	icon:SetWidth(30)
	icon:SetHeight(10)
	self._headerContent:AddChild(icon)

	local label = AceGUI:Create("Label")
	label:SetText(text)
	label:SetFullWidth(false)
	label:SetWidth(380)
	if label.label then
		label.label:SetFontObject(GameFontNormalOutline)
		label.label:SetJustifyH("LEFT")
		label.label:SetJustifyV("MIDDLE")
	end
	self._headerContent:AddChild(label)

	if sub ~= "" then
		local label2 = AceGUI:Create("Label")
		label2:SetText(sub)
		label2:SetFullWidth(false)
		label2:SetWidth(520)
		if label2.label then
			label2.label:SetFontObject(GameFontNormalSmallOutline)
			label2.label:SetJustifyH("LEFT")
			label2.label:SetJustifyV("MIDDLE")
		end
		self._headerContent:AddChild(label2)
	end

	return true
end

-- 2) Eingabefeld (Suche)
function UI:Header_BuildSearch(opts)
	opts = opts or {}
	if not AceGUI then return false end
	if not self._headerContent then return false end

	self:Header_Clear()
	Header_EnsureLayout()

	local iconPath = tostring(opts.icon or "Interface\\Icons\\INV_Misc_Search_01")
	local placeholder = tostring(opts.placeholder or "Suche…")
	local onChanged = opts.onChanged
	local onEnter = opts.onEnter

	local icon = AceGUI:Create("Icon")
	icon:SetImage(iconPath)
	icon:SetImageSize(16, 16)
	icon:SetWidth(22)
	icon:SetHeight(16)
	self._headerContent:AddChild(icon)

	local edit = AceGUI:Create("EditBox")
	edit:SetLabel("") -- kein AceGUI-Label über dem Feld
	edit:SetText("")
	edit:SetWidth(360)
	edit:DisableButton(true) -- kein "OK" Button
	self._headerContent:AddChild(edit)

	-- Hinweis (placeholder-like): wenn leer, zeig Text in Label daneben (robust, da AceGUI EditBox keinen echten placeholder hat)
	local hint = AceGUI:Create("Label")
	hint:SetText("|cffAAAAAA" .. placeholder .. "|r")
	hint:SetFullWidth(false)
	hint:SetWidth(260)
	if hint.label then
		hint.label:SetFontObject(GameFontNormalSmallOutline)
		hint.label:SetJustifyH("LEFT")
		hint.label:SetJustifyV("MIDDLE")
	end
	self._headerContent:AddChild(hint)

	local function UpdateHint()
		if not hint or not hint.label then return end
		local t = ""
		if edit and edit.GetText then t = tostring(edit:GetText() or "") end
		if TRIM(t) == "" then
			hint.label:SetText("|cffAAAAAA" .. placeholder .. "|r")
		else
			hint.label:SetText("")
		end
	end

	edit:SetCallback("OnTextChanged", function(_, _, val)
		UpdateHint()
		if type(onChanged) == "function" then
			pcall(onChanged, tostring(val or ""), edit)
		end
	end)

	edit:SetCallback("OnEnterPressed", function(_, _, val)
		UpdateHint()
		if type(onEnter) == "function" then
			pcall(onEnter, tostring(val or ""), edit)
		end
	end)

	UpdateHint()

	-- speicher für späteren Zugriff (optional)
	self._headerSearchBox = edit
	return true
end

-- 3) Controls (3-4 Checkboxen / Buttons)
function UI:Header_BuildControls(opts)
	opts = opts or {}
	if not AceGUI then return false end
	if not self._headerContent then return false end

	self:Header_Clear()
	Header_EnsureLayout()

	local title = tostring(opts.title or "Filter / Aktionen")
	local onToggleA = opts.onToggleA
	local onToggleB = opts.onToggleB
	local onToggleC = opts.onToggleC
	local onClickMain = opts.onClickMain

	local label = AceGUI:Create("Label")
	label:SetText(title)
	label:SetFullWidth(false)
	label:SetWidth(220)
	if label.label then
		label.label:SetFontObject(GameFontNormalOutline)
		label.label:SetJustifyH("LEFT")
		label.label:SetJustifyV("MIDDLE")
	end
	self._headerContent:AddChild(label)

	local cbA = AceGUI:Create("CheckBox")
	cbA:SetLabel(tostring(opts.labelA or "Online"))
	cbA:SetValue(opts.valueA and true or false)
	cbA:SetWidth(110)
	cbA:SetCallback("OnValueChanged", function(_, _, val)
		if type(onToggleA) == "function" then pcall(onToggleA, val and true or false) end
	end)
	self._headerContent:AddChild(cbA)

	local cbB = AceGUI:Create("CheckBox")
	cbB:SetLabel(tostring(opts.labelB or "Twinks"))
	cbB:SetValue(opts.valueB and true or false)
	cbB:SetWidth(110)
	cbB:SetCallback("OnValueChanged", function(_, _, val)
		if type(onToggleB) == "function" then pcall(onToggleB, val and true or false) end
	end)
	self._headerContent:AddChild(cbB)

	local cbC = AceGUI:Create("CheckBox")
	cbC:SetLabel(tostring(opts.labelC or "Sort A-Z"))
	cbC:SetValue(opts.valueC and true or false)
	cbC:SetWidth(120)
	cbC:SetCallback("OnValueChanged", function(_, _, val)
		if type(onToggleC) == "function" then pcall(onToggleC, val and true or false) end
	end)
	self._headerContent:AddChild(cbC)

	local btn = AceGUI:Create("Button")
	btn:SetText(tostring(opts.buttonText or "Aktualisieren"))
	btn:SetWidth(140)
	btn:SetCallback("OnClick", function()
		if type(onClickMain) == "function" then pcall(onClickMain) end
	end)
	self._headerContent:AddChild(btn)

	return true
end

-- Default Header: Addon Info
function UI:Header_BuildDefault()
	local version = (GMS and GMS.VERSION) and tostring(GMS.VERSION) or ""
	local sub = (version ~= "" and ("Version: |cffCCCCCC" .. version .. "|r")) or "UI Extension aktiv"
	return self:Header_BuildIconText({
		icon = "Interface\\Icons\\INV_Misc_Note_05",
		text = "|cff03A9F4[GMS]|r " .. DISPLAY_NAME,
		subtext = sub,
	})
end

-- ###########################################################################
-- #	TITLE / PORTRAIT
-- ###########################################################################

function UI:SetWindowTitle(text)
	if self._frame and self._frame.GMS_TitleText then
		self._frame.GMS_TitleText:SetText(tostring(text or ""))
	end
end

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
-- #	REGIONS (AceGUI embedding)
-- ###########################################################################

function UI:INTERNAL_CreateRegion(regionKey, parent, points)
	if not AceGUI or not parent then return nil end
	self._regions = self._regions or {}

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

function UI:GetRegionRoot(regionKey)
	if not self._regions then return nil end
	local r = self._regions[regionKey]
	return r and r.root or nil
end

function UI:GetHeader() return self:GetRegionRoot("HEADER") end

function UI:GetContent() return self:GetRegionRoot("CONTENT") end

function UI:GetStatus() return self:GetRegionRoot("STATUS") end

function UI:ClearContentRegion()
	local root = self:GetContent()
	if root and root.ReleaseChildren then root:ReleaseChildren() end
end

-- ###########################################################################
-- #	FALLBACK CONTENT (works even without PAGES section)
-- ###########################################################################

function UI:EnsureFallbackContentRoot()
	if self._fallbackRoot then return end
	if not AceGUI or not self._content then return end

	local root = AceGUI:Create("SimpleGroup")
	root:SetLayout("Fill")
	root.frame:SetParent(self._content)
	root.frame:ClearAllPoints()
	root.frame:SetAllPoints(self._content)
	root.frame:Show()

	self._fallbackRoot = root
end

function UI:RenderFallbackContent(root, hintText)
	if not AceGUI or not root then return end

	local title = AceGUI:Create("Label")
	title:SetText("|cff03A9F4GMS|r – UI ist geladen.")
	title:SetFontObject(GameFontNormalLarge)
	title:SetFullWidth(true)
	root:AddChild(title)

	local hint = AceGUI:Create("Label")
	hint:SetText(tostring(hintText or "Pages-System ist nicht aktiv (oder entfernt)."))
	hint:SetFullWidth(true)
	root:AddChild(hint)

	local resetBtn = AceGUI:Create("Button")
	resetBtn:SetText("Fenster zurücksetzen (Position/Größe)")
	resetBtn:SetFullWidth(true)
	resetBtn:SetCallback("OnClick", function()
		UI:ResetWindowToDefaults()
	end)
	root:AddChild(resetBtn)
end

if type(UI.Navigate) ~= "function" then
	function UI:Navigate(_)
		self:EnsureFallbackContentRoot()
		if self._fallbackRoot and self._fallbackRoot.ReleaseChildren then
			self._fallbackRoot:ReleaseChildren()
			self:RenderFallbackContent(self._fallbackRoot, "Navigate() aktiv, aber PAGES-Section fehlt.")
		end
	end
end

-- Notify that UI core finished loading
LOCAL_LOG("INFO", "UI file loaded")

-- ###########################################################################
-- #	PERSISTENZ (POSITION / SIZE)
-- ###########################################################################

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

function UI:ResetWindowToDefaults()
	if not self.db then return end
	self.db.profile.window = CopyTableSafe(DEFAULTS.profile.window)

	if self._frame then
		self:ApplyWindowState()
		if type(self.ReflowRightDock) == "function" then self:ReflowRightDock() end
		if type(self.Navigate) == "function" then
			self:Navigate(self._page or GetActivePage())
		end
	end
end

-- Fallback logic for Navigate if UI_Pages is not loaded
if type(UI.Navigate) ~= "function" then
	function UI:Navigate(_)
		self:EnsureFallbackContentRoot()
		if self._fallbackRoot and self._fallbackRoot.ReleaseChildren then
			self._fallbackRoot:ReleaseChildren()
			self:RenderFallbackContent(self._fallbackRoot, "UI_Pages Extension fehlt.")
		end
	end
end

-- ###########################################################################
-- #	FRAME (ButtonFrameTemplate)
-- ###########################################################################

local function CreateAceGroupInFrame(parent, layout)
	if not AceGUI or not parent then return nil end
	layout = layout or "Fill"

	local group = AceGUI:Create("SimpleGroup")
	group:SetLayout(layout)
	group:SetFullWidth(true)
	group:SetFullHeight(true)

	group.frame:SetParent(parent)
	group.frame:ClearAllPoints()
	group.frame:SetAllPoints(parent)
	group.frame:Show()

	return group
end

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

	f:SetScript("OnDragStart", function(selfFrame) selfFrame:StartMoving() end)
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
	resize:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	resize:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		UI:SaveWindowState()
		UI:ReflowRightDock()
	end)

	-- Content (Inset-gebunden) bleibt wie gehabt
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

	-- Header/Footer (am Frame f, bewusst entkoppelt vom Content)
	local content_header = CreateFrame("Frame", nil, f)
	content_header:SetHeight(30)
	content_header:SetFrameStrata(f:GetFrameStrata())
	content_header:SetFrameLevel(f:GetFrameLevel() + 1)
	content_header:SetPoint("TOPLEFT", f, "TOPLEFT", 60, -28)
	content_header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -28)

	local content_footer = CreateFrame("Frame", nil, f)
	content_footer:SetHeight(20)
	content_footer:SetFrameStrata(f:GetFrameStrata())
	content_footer:SetFrameLevel(f:GetFrameLevel() + 1)
	content_footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 0)
	content_footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 0)

	-- Register frames in UI state
	UI._headerFrame = content_header
	UI._footerFrame = content_footer
	UI._content = content

	-- Header/Footer content groups (SimpleGroup) -> das ist der "zurückgegebene Content"
	local headerGroup = CreateAceGroupInFrame(content_header, "List")
	local footerGroup = CreateAceGroupInFrame(content_footer, "Fill")

	UI._headerContent = headerGroup
	UI._footerContent = footerGroup

	-- Default Header + Default Footer Status
	if UI._headerContent then
		UI:Header_BuildDefault()
	end
	if UI._footerContent then
		UI:SetStatusText("Status: bereit")
	end

	-- Background fürs Content (wie gehabt)
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
	end)

	f:Hide()

	UI._frame = f

	-- CONTENT Region (AceGUI) bleibt am Inset-Content hängen
	UI._regions = UI._regions or {}
	if AceGUI then
		UI:INTERNAL_CreateRegion("CONTENT", content, {
			{ "TOPLEFT", content, "TOPLEFT", 0, 0 },
			{ "BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0 },
		})
	end

	UI:SetIconFallback()
	UI:SetWindowTitle(DISPLAY_NAME)
end

-- ###########################################################################
-- #	PUBLIC API (INIT / SHOW / HIDE / TOGGLE / OPEN)
-- ###########################################################################

function UI:Init()
	if self._inited then return end
	self._inited = true

	-- Prefer centralized module DB via GMS.DB; fallback to AceDB if not available
	if GMS and GMS.DB and type(GMS.DB.RegisterModule) == "function" then
		local ok, ns = pcall(function()
			return GMS.DB:RegisterModule("UI", DEFAULTS, nil)
		end)
		if ok and ns then
			self.db = ns
		elseif AceDB then
			self.db = AceDB:New("GMS_UIDB", DEFAULTS, true)
		end
	else
		if AceDB then
			self.db = AceDB:New("GMS_UIDB", DEFAULTS, true)
		end
	end

	self:CreateFrame()
	self:ApplyWindowState()

	if type(self.RegisterPage) == "function" then
		-- Home-Page wurde in DASHBOARD ausgelagert
	end

	LOCAL_LOG("DEBUG", "UI Init complete")
end

function UI:Show()
	if not self._inited then self:Init() end
	if self._frame then
		self:ApplyWindowState()
		self._frame:Show()
	end
end

function UI:Hide()
	if self._frame then self._frame:Hide() end
end

function UI:Toggle(pageName)
	if not self._inited then self:Init() end
	if not self._frame then return end

	if self._frame:IsShown() then
		self:Hide()
	else
		self:Open(pageName)
	end
end

function UI:Open(pageName)
	local desired = (type(pageName) == "string" and pageName ~= "" and pageName) or (self._page or GetActivePage())
	self:Show()
	self:Navigate(desired)
end

function UI:Close()
	self:Hide()
end

function UI:IsReady()
	return self._inited == true and self._frame ~= nil
end

-- ###########################################################################
-- #	SLASH COMMAND INTEGRATION (your SlashCommands EXTENSION)
-- ###########################################################################

function UI:RegisterUiSlashCommandIfAvailable()
	-- Initialize UI options first
	if not self._options then
		self:InitializeOptions()
	end

	if type(GMS.Slash_RegisterSubCommand) ~= "function" then
		LOCAL_LOG("WARN", "SlashCommands not available; cannot register /gms ui")
		return
	end

	GMS:Slash_RegisterSubCommand("ui", function(rest)
		rest = TRIM(rest)
		UI:Open((rest ~= "" and rest) or nil)
	end, {
		help = "Öffnet die GMS UI (/gms ui [page])",
		alias = { "open" },
		owner = EXT_NAME,
	})

	LOCAL_LOG("INFO", "Registered subcommand: /gms ui")
	GMS:SetReady("EXT:UI")
end

-- ###########################################################################
-- #	GMS BRIDGE API
-- ###########################################################################

function GMS:UI_IsReady()
	return type(GMS.UI) == "table"
		and type(GMS.UI.Open) == "function"
		and (GMS.UI.IsReady == nil or GMS.UI:IsReady() == true)
end

function GMS:UI_Open(pageName)
	if not self:UI_IsReady() then
		if GMS.UI and type(GMS.UI.Init) == "function" then
			GMS.UI:Init()
		end
	end

	if not self:UI_IsReady() then
		LOCAL_LOG("WARN", "GMS:UI_Open failed (UI not ready)", { pageName = pageName })
		return false
	end

	GMS.UI:Open(type(pageName) == "string" and pageName or nil)
	return true
end

-- ###########################################################################
-- #	BOOTSTRAP (extension style)
-- ###########################################################################

if not UI._bootstrapped then
	UI._bootstrapped = true
	UI:RegisterUiSlashCommandIfAvailable()
end

-- ###########################################################################
-- #	DEV: AUTO OPEN AFTER RELOAD (test only)
-- ###########################################################################

UI._devAutoOpen = UI._devAutoOpen or true

if not UI._devAutoOpenHooked then
	UI._devAutoOpenHooked = true

	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function()
		if not UI._devAutoOpen then return end
		UI:Open(GetActivePage())
	end)
end

LOCAL_LOG("INFO", "EXT:UI READY")
GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)
