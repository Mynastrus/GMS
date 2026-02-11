-- ============================================================================
--	GMS/Core/UI_Pages.lua
--	UI_PAGES EXTENSION
--	- Handles page registration and navigation for GMS.UI
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

UI._pages = UI._pages or {}
UI._order = UI._order or {}

local function SortPages()
	if type(_G.wipe) == "function" then
		_G.wipe(UI._order)
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

function UI:RegisterPage(id, order, title, buildFn)
	id = tostring(id or "")
	if id == "" then return false end

	self._pages[id] = {
		order = tonumber(order) or 9999,
		title = tostring(title or id),
		build = buildFn,
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

	if not self._pages or not self._pages[id] then
		id = GetFirstPageId() or "DASHBOARD"
	end

	self._page = id
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

	if contentRoot and contentRoot.ReleaseChildren then
		contentRoot:ReleaseChildren()
	end

	local p = self._pages and self._pages[id] or nil
	if type(self.SetWindowTitle) == "function" then
		local mainTitle = self.DISPLAY_NAME or "GMS"
		local pageTitle = (p and p.title) or id
		self:SetWindowTitle(mainTitle .. "   |cffCCCCCC" .. tostring(pageTitle) .. "|r")
	end

	if p and type(p.build) == "function" then
		local ok, err = pcall(p.build, contentRoot, id)
		if not ok then
			LOCAL_LOG("ERROR", "Page build error", tostring(err))
		end
	elseif type(self.RenderFallbackContent) == "function" then
		self:RenderFallbackContent(contentRoot, "Page nicht gefunden: " .. tostring(id))
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
