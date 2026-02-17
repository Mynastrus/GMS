-- ============================================================================
--	GMS/Core/UI_Pages.lua
--	UI_PAGES EXTENSION
--	- Handles page registration and navigation for GMS.UI
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local AceGUI = LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G = _G
local wipe = wipe
---@diagnostic enable: undefined-global

local UI = GMS.UI
if not UI then return end

-- ###########################################################################
-- #	METADATA
-- ###########################################################################

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "UI_PAGES",
	SHORT_NAME   = "UI_Pages",
	DISPLAY_NAME = "UI Pagination",
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
	desc = "Handles Page registration and Navigation",
})

-- ###########################################################################
-- #	PAGES LOGIC
-- ###########################################################################

UI._pages          = UI._pages or {}
UI._order          = UI._order or {}
UI._pageContainers = UI._pageContainers or {}

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

function UI:RegisterPage(id, order, title, buildFn, titleKey)
	id = tostring(id or "")
	if id == "" then return false end

	self._pages[id] = {
		order = tonumber(order) or 9999,
		title = tostring(title or id),
		build = buildFn,
		titleKey = (type(titleKey) == "string" and titleKey ~= "") and titleKey or nil,
	}

	SortPages()
	return true
end

local function GetFirstPageId()
	if UI._order and UI._order[1] and UI._order[1].id then
		return UI._order[1].id
	end
	return nil
end

local function GetActivePage()
	if type(UI.GetActivePage) == "function" then
		return UI:GetActivePage()
	end
	return "DASHBOARD"
end

local function ResolvePageTitle(id, page)
	local fallback = (type(page) == "table" and page.title) or tostring(id or "")

	if type(page) == "table" and type(page.titleKey) == "string" and page.titleKey ~= "" and type(GMS.T) == "function" then
		local localized = tostring(GMS:T(page.titleKey))
		if localized ~= "" and localized ~= page.titleKey then
			return localized
		end
	end

	if GMS and GMS.REGISTRY then
		local ext = GMS.REGISTRY.EXT and GMS.REGISTRY.EXT[tostring(id or ""):upper()] or nil
		if type(ext) == "table" then
			if type(GMS.ResolveRegistryDisplayName) == "function" then
				return GMS:ResolveRegistryDisplayName(ext, fallback)
			end
			return tostring(ext.displayName or ext.name or fallback)
		end

		local uid = tostring(id or ""):upper()
		local mods = GMS.REGISTRY.MOD
		if type(mods) == "table" then
			for _, meta in pairs(mods) do
				local k = tostring(meta.key or ""):upper()
				local n = tostring(meta.name or ""):upper()
				local s = tostring(meta.shortName or ""):upper()
				if uid == k or uid == n or uid == s then
					if type(GMS.ResolveRegistryDisplayName) == "function" then
						return GMS:ResolveRegistryDisplayName(meta, fallback)
					end
					return tostring(meta.displayName or meta.name or fallback)
				end
			end
		end
	end

	return tostring(fallback)
end

function UI:Navigate(id)
	if not self._inited then
		self:Init()
	end

	id = tostring(id or "")
	if id == "" then
		id = GetActivePage()
	end

	if not self._pages or not self._pages[id] then
		id = GetFirstPageId() or "DASHBOARD"
	end

	-- THROTTLE: Prevent spamming navigation to the same page
	local now = GetTime()
	if self._page == id and self._lastNavTime and (now - self._lastNavTime) < 0.5 then
		return
	end
	self._lastNavTime = now

	self._page = id
	self._navToken = (self._navToken or 0) + 1

	if type(self.SaveActivePage) == "function" then
		self:SaveActivePage(id)
	end

	local contentRoot = self:GetContent()
	if not contentRoot then
		if type(self.EnsureFallbackContentRoot) == "function" then
			self:EnsureFallbackContentRoot()
		end
		contentRoot = self._fallbackRoot
	end

	-- 1. HIDE all existing page containers
	if self._pageContainers then
		for _, container in pairs(self._pageContainers) do
			if container and container.frame then
				container.frame:Hide()
			end
		end
	end

	-- 2. Clear common regions
	if type(self.Header_Clear) == "function" then self:Header_Clear() end
	if type(self.Footer_Clear) == "function" then self:Footer_Clear() end

	local p = self._pages and self._pages[id] or nil
	if type(self.SetWindowTitle) == "function" then
		local mainTitle = self.DISPLAY_NAME or "GMS"
		local pageTitle = ResolvePageTitle(id, p)
		self:SetWindowTitle(mainTitle .. "   |cffCCCCCC" .. tostring(pageTitle) .. "|r")
	end

	-- 3. Check for cached container or create NEW
	local pageContainer = self._pageContainers[id]
	local isCached = false

	if pageContainer then
		pageContainer.frame:Show()
		isCached = true
	else
		-- Create a dedicated container for this page
		pageContainer = AceGUI:Create("SimpleGroup")
		pageContainer:SetLayout("Fill")
		pageContainer:SetFullWidth(true)
		pageContainer:SetFullHeight(true)
		contentRoot:AddChild(pageContainer)
		self._pageContainers[id] = pageContainer
	end

	-- ACEGUI FIX: Fill-Layout only layouts children[1].
	-- Move the active container to the first position so it gets layouted.
	if contentRoot.children and #contentRoot.children > 0 then
		local foundIdx = -1
		for i, child in ipairs(contentRoot.children) do
			if child == pageContainer then
				foundIdx = i
			else
				-- EXTRA SAFETY: Hide all other children frames
				if child.frame then child.frame:Hide() end
			end
		end
		if foundIdx > 1 then
			table.remove(contentRoot.children, foundIdx)
			table.insert(contentRoot.children, 1, pageContainer)
		end
	end

	-- Force layout recalculation BEFORE build to ensure container is visible for progressive builds
	if contentRoot and contentRoot.DoLayout then
		contentRoot:DoLayout()
	end

	-- 4. Call build function
	if p and type(p.build) == "function" then
		local ok, err = pcall(p.build, pageContainer, id, isCached)
		if not ok then
			LOCAL_LOG("ERROR", "Page build error", tostring(err))
		end
	elseif type(self.RenderFallbackContent) == "function" then
		self:RenderFallbackContent(pageContainer, "Page nicht gefunden: " .. tostring(id))
	end

	if type(self.SetRightDockSelected) == "function" then
		self:SetRightDockSelected(id, true, true)
	end
end

-- ###########################################################################
-- #	READY
-- ###########################################################################

GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)
LOCAL_LOG("INFO", "UI_Pages logic loaded")
