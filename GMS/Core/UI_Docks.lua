-- ============================================================================
--	GMS/Core/UI_Docks.lua
--	UI_DOCKS EXTENSION
--	- Handles RightDock icon management for GMS.UI
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

local UI = GMS.UI
if not UI then return end

-- ###########################################################################
-- #	METADATA
-- ###########################################################################

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "UI_DOCKS",
	SHORT_NAME   = "UI_Docks",
	DISPLAY_NAME = "UI Sidedocks",
	VERSION      = "1.0.0",
}

-- ###########################################################################
-- #	LOG BUFFER + LOCAL LOGGER
-- ###########################################################################

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function now()
	return type(GetTime) == "function" and GetTime() or nil
end

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		time   = now(),
		level  = tostring(level or "INFO"),
		type   = METADATA.TYPE,
		source = METADATA.SHORT_NAME,
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
-- #	EXTENSION REGISTRATION
-- ###########################################################################

GMS:RegisterExtension({
	key = METADATA.INTERN_NAME,
	name = METADATA.SHORT_NAME,
	displayName = METADATA.DISPLAY_NAME,
	version = METADATA.VERSION,
	desc = "Handles UI RightDock icon management",
})

-- ###########################################################################
-- #	DOCK CONFIG & STATE
-- ###########################################################################

UI.RightDockConfig = UI.RightDockConfig or {
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

UI._rightDockSeeded = UI._rightDockSeeded or false
UI._rightDock = UI._rightDock or {
	inited = false,
	parent = nil,
	top = { order = {}, entries = {} },
	bottom = { order = {}, entries = {} },
	all = {},
}

-- ###########################################################################
-- #	DOCK LOGIC
-- ###########################################################################

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

function UI:RightDockApplySlotBackdrop(slot)
	local cfg = self.RightDockConfig
	if slot and cfg and cfg.slotBackdrop then
		if not slot.SetBackdrop and _G.Mixin and _G.BackdropTemplateMixin then
			_G.Mixin(slot, _G.BackdropTemplateMixin)
		end
		if slot.SetBackdrop then
			slot:SetBackdrop(cfg.slotBackdrop)
		end
	end
end

function UI:RightDockSetSelected(entry, selected)
	if entry and entry.button and entry.button._glow then
		entry.button._glow:SetShown(selected and true or false)
	end
	if entry and entry.button then
		entry.button._selected = selected and true or false
	end
end

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

function UI:AddRightDockIcon(lane, opts)
	opts = opts or {}
	lane = (lane == "bottom") and "bottom" or "top"

	if type(self.CreateFrame) == "function" then self:CreateFrame() end
	self:RightDockEnsure(self._frame)

	local cfg = self.RightDockConfig
	local id = tostring(opts.id or "")
	if id == "" then return nil end

	if self._rightDock.all[id] then
		return self._rightDock.all[id]
	end

	local st = (lane == "bottom") and self._rightDock.bottom or self._rightDock.top

	local parent       = self._rightDock.parent
	local parentStrata = parent and parent:GetFrameStrata() or "DIALOG"
	local parentLevel  = parent and parent:GetFrameLevel() or 200

	local slot = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	slot:SetSize(cfg.slotWidth, cfg.slotHeight)
	slot:SetFrameStrata(parentStrata)
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
			_G.GameTooltip:SetOwner(slot, "ANCHOR_LEFT")
			if opts.tooltipTitle and opts.tooltipTitle ~= "" then
				_G.GameTooltip:AddLine(opts.tooltipTitle, 1, 1, 1)
			end
			if opts.tooltipText and opts.tooltipText ~= "" then
				_G.GameTooltip:AddLine(opts.tooltipText, 0.9, 0.9, 0.9, true)
			end
			_G.GameTooltip:Show()
		end
	end)

	btn:SetScript("OnLeave", function()
		_G.GameTooltip:Hide()
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

function UI:AddRightDockIconTop(opts) return self:AddRightDockIcon("top", opts) end

function UI:AddRightDockIconBottom(opts) return self:AddRightDockIcon("bottom", opts) end

function UI:SeedRightDockPlaceholders()
	local dashName = (
		GMS.REGISTRY and GMS.REGISTRY.EXT and GMS.REGISTRY.EXT["DASHBOARD"] and GMS.REGISTRY.EXT["DASHBOARD"].displayName) or
		"Dashboard"
	local optsName = (
		GMS.REGISTRY and GMS.REGISTRY.EXT and GMS.REGISTRY.EXT["SETTINGS"] and GMS.REGISTRY.EXT["SETTINGS"].displayName) or
		"Optionen"

	self:AddRightDockIconTop({
		id = "DASHBOARD",
		order = 1,
		selectable = true,
		selected = true,
		icon = "Interface\\Icons\\INV_Misc_Note_05",
		tooltipTitle = dashName,
		tooltipText = "Zeigt das Dashboard des Addons an",
		onClick = function()
			if type(UI.Navigate) == "function" then
				UI:Navigate("DASHBOARD")
			end
		end,
	})

	self:AddRightDockIconBottom({
		id = "SETTINGS",
		order = 1,
		selectable = true,
		icon = "Interface\\Icons\\Trade_Engineering",
		tooltipTitle = optsName,
		tooltipText = "Einstellungen",
		onClick = function()
			if type(UI.Open) == "function" then
				UI:Open("SETTINGS")
			end
		end,
	})
end

-- ###########################################################################
-- #	READY
-- ###########################################################################

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)
LOCAL_LOG("INFO", "UI_Docks logic loaded")
