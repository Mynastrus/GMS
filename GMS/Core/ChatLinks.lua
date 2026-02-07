	-- ============================================================================
	--	GMS/Core/ChatLinks.lua
	--	ChatLinks EXTENSION
	--	- Registry: Action -> { title, label, hint, tooltip, flags }
	--	- Builder: GMS:ChatLink_Build(action, labelOverride, tooltipTitleOverride)
	--	- Hover: Tooltip auf ChatFrame OnHyperlinkEnter/Leave (robust close)
	--	- Click: SetItemRef dispatch (optional)
	--
	--	FEATURE: Tooltip-Inhalte pro Action wahlweise ein/ausblendbar:
	--		flags = {
	--			showLabel = true/false,
	--			showHint = true/false,
	--			showTooltipLines = true/false,
	--			showActionFallback = true/false,
	--		}
	--
	--	Tooltip-Titel:
	--	- Default: entry.title
	--	- Override: im Link als 3. Segment: |HGMS:ACTION:TITLE|h...|h
	-- ============================================================================

	local LibStub = _G.LibStub
	if not LibStub then return end

	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end

	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end

	-- ###########################################################################
	-- #	REGISTRY
	-- ###########################################################################

	GMS.ChatLinks = GMS.ChatLinks or {}
	local ChatLinks = GMS.ChatLinks

	ChatLinks.REGISTRY = ChatLinks.REGISTRY or {}

	-- LinkType bewusst uppercase wie du willst
	ChatLinks.LINK_TYPE = ChatLinks.LINK_TYPE or "GMS"

	-- Default Farben (optional)
	ChatLinks.COLOR = ChatLinks.COLOR or "FFFFCC00" -- gold
	ChatLinks.COLOR_TOOLTIP_TITLE = ChatLinks.COLOR_TOOLTIP_TITLE or { 1, 1, 1 }
	ChatLinks.COLOR_TOOLTIP_TEXT = ChatLinks.COLOR_TOOLTIP_TEXT or { 0.8, 0.8, 0.8 }

	-- Default Tooltip-Flags (pro entry überschreibbar)
	ChatLinks.DEFAULT_FLAGS = ChatLinks.DEFAULT_FLAGS or {
		showLabel = true,
		showHint = true,
		showTooltipLines = true,
		showActionFallback = true,
	}

	local function UPPER(s)
		return string.upper(tostring(s or ""))
	end

	local function TRIM(s)
		s = tostring(s or "")
		s = string.gsub(s, "^%s+", "")
		s = string.gsub(s, "%s+$", "")
		return s
	end

	local function MergeFlags(dst, src)
		dst = dst or {}
		src = src or {}
		for k, v in pairs(src) do
			dst[k] = v
		end
		return dst
	end

	local function ResolveFlags(entry)
		local out = {}
		-- defaults
		out = MergeFlags(out, ChatLinks.DEFAULT_FLAGS)
		-- entry overrides
		if entry and type(entry.flags) == "table" then
			out = MergeFlags(out, entry.flags)
		end
		return out
	end

	local function ParseLink(link)
		-- Supports:
		-- |HGMS:ACTION|h...|h
		-- |HGMS:ACTION:TITLE|h...|h
		local linkType, action, title = strsplit(":", tostring(link or ""))
		linkType = UPPER(linkType)
		action = UPPER(action)

		if linkType ~= ChatLinks.LINK_TYPE then
			return nil, nil
		end

		if action == "" then
			return nil, nil
		end

		title = TRIM(title)
		if title == "" then title = nil end

		return action, title
	end

	-- ###########################################################################
	-- #	PUBLIC API
	-- ###########################################################################

	-- Definiert eine Action (Hover-Text + optional Hint + Tooltip-Titel + Flags)
	-- spec = {
	--		title = "|cff03A9F4[GMS]|r",				-- Tooltip-Titel (Default, optional)
	--		label = "GMS öffnen",					-- Default Link-Label im Chat (optional)
	--		hint = "/gms ui",						-- optional: kurzer Hinweis
	--		tooltip = { "Zeile1", "Zeile2" },		-- optional: Tooltip-Zeilen
	--		flags = { showLabel=false, ... },		-- optional: Anzeige steuern
	-- }
	function GMS:ChatLink_Define(action, spec)
		action = UPPER(action)
		if action == "" then return false end

		spec = spec or {}
		local entry = {
			action = action,
			title = tostring(spec.title or "|cff03A9F4[GMS]|r"),
			label = tostring(spec.label or action),
			hint = tostring(spec.hint or ""),
			tooltip = spec.tooltip,
			flags = spec.flags,
		}

		ChatLinks.REGISTRY[action] = entry
		return true
	end

	-- Baut den tatsächlichen Chat-Link-String
	function GMS:ChatLink_Build(action, labelOverride, tooltipTitleOverride)
		action = UPPER(action)

		local entry = ChatLinks.REGISTRY[action]
		if not entry then
			entry = { title = "|cff03A9F4[GMS]|r", label = action, action = action, hint = "", tooltip = nil, flags = nil }
		end

		local label = tostring(labelOverride or entry.label or action)
		local color = tostring(ChatLinks.COLOR or "FFFFFFFF")

		local title = TRIM(tooltipTitleOverride)
		if title == "" then
			return string.format("|c%s|H%s:%s|h%s|h|r", color, ChatLinks.LINK_TYPE, action, label)
		end

		-- ":" trennt Segmente -> im Titel bitte keine ":" verwenden
		return string.format("|c%s|H%s:%s:%s|h%s|h|r", color, ChatLinks.LINK_TYPE, action, title, label)
	end

	-- Optional: Klick-Handler registrieren
	ChatLinks.CLICK_HANDLERS = ChatLinks.CLICK_HANDLERS or {}

	function GMS:ChatLink_OnClick(action, handlerFn)
		action = UPPER(action)
		if action == "" then return false end
		if type(handlerFn) ~= "function" then return false end
		ChatLinks.CLICK_HANDLERS[action] = handlerFn
		return true
	end

	-- ###########################################################################
	-- #	HOVER TOOLTIP (robust close)
	-- ###########################################################################

	local function Tooltip_AddLine(tt, text)
		local c = ChatLinks.COLOR_TOOLTIP_TEXT
		tt:AddLine(tostring(text), c[1], c[2], c[3], true)
	end

	local function Tooltip_Show(frame, action, linkText, titleOverride)
		local entry = ChatLinks.REGISTRY[action]
		local flags = ResolveFlags(entry)

		GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")

		-- Title: override > entry.title > default
		local title = tostring(titleOverride or (entry and entry.title) or "|cff03A9F4[GMS]|r")
		GameTooltip:SetText(title)

		if entry then
			if flags.showLabel and entry.label and entry.label ~= "" then
				Tooltip_AddLine(GameTooltip, entry.label)
			end

			if flags.showHint and entry.hint and entry.hint ~= "" then
				Tooltip_AddLine(GameTooltip, "Befehl: |cFFFFCC00" .. entry.hint .. "|r")
			end

			if flags.showTooltipLines then
				if type(entry.tooltip) == "table" then
					for _, line in ipairs(entry.tooltip) do
						if line and line ~= "" then
							Tooltip_AddLine(GameTooltip, line)
						end
					end
				end
			end

			if flags.showActionFallback then
				-- Wenn nix angezeigt wurde (z.B. alles deaktiviert), gib wenigstens die Aktion aus
				local hadAny = false
				if flags.showLabel and entry.label and entry.label ~= "" then hadAny = true end
				if flags.showHint and entry.hint and entry.hint ~= "" then hadAny = true end
				if flags.showTooltipLines and type(entry.tooltip) == "table" and #entry.tooltip > 0 then hadAny = true end

				if not hadAny then
					Tooltip_AddLine(GameTooltip, "Aktion: " .. action)
				end
			end
		else
			if flags.showActionFallback then
				Tooltip_AddLine(GameTooltip, "Aktion: " .. action)
			end
		end

		GameTooltip:Show()

		-- Tag: dieser Tooltip wurde von GMS ChatLinks geöffnet
		GameTooltip.GMS_CHATLINK_ACTIVE = true
		GameTooltip.GMS_CHATLINK_OWNER = frame
	end

	local function Tooltip_HideIfOurs(frame)
		if not GameTooltip.GMS_CHATLINK_ACTIVE then
			return
		end

		if GameTooltip.GMS_CHATLINK_OWNER and GameTooltip.GMS_CHATLINK_OWNER ~= frame then
			return
		end

		GameTooltip:Hide()
		GameTooltip.GMS_CHATLINK_ACTIVE = nil
		GameTooltip.GMS_CHATLINK_OWNER = nil
	end

	local function OnHyperlinkEnter(frame, link, text)
		local action, titleOverride = ParseLink(link)
		if not action then return end
		Tooltip_Show(frame, action, text, titleOverride)
	end

	local function OnHyperlinkLeave(frame, link, text)
		Tooltip_HideIfOurs(frame)
	end

	-- ###########################################################################
	-- #	CLICK DISPATCH
	-- ###########################################################################

	local function OnClick(link, text, button)
		local action = select(1, ParseLink(link))
		if not action then return end

		local fn = ChatLinks.CLICK_HANDLERS[action]
		if type(fn) == "function" then
			local ok, err = pcall(fn, action, link, text, button)
			if not ok then
				if type(GMS.LOG) == "function" then
					GMS:LOG("ERROR", "CHATLINKS", "Click handler error: %s", tostring(err))
				end
			end
		end
	end

	-- ###########################################################################
	-- #	BOOTSTRAP HOOKS (einmalig)
	-- ###########################################################################

	if not ChatLinks._hooked then
		ChatLinks._hooked = true

		for i = 1, NUM_CHAT_WINDOWS do
			local chat = _G["ChatFrame" .. i]
			if chat then
				GMS:HookScript(chat, "OnHyperlinkEnter", OnHyperlinkEnter)
				GMS:HookScript(chat, "OnHyperlinkLeave", OnHyperlinkLeave)
			end
		end

		GMS:SecureHook("SetItemRef", function(link, text, button)
			OnClick(link, text, button)
		end)
	end

	-- ###########################################################################
	-- #	DEFAULT DEFINITIONS (Example)
	-- ###########################################################################

	if not ChatLinks._defaultsLoaded then
		ChatLinks._defaultsLoaded = true

		-- Beispiel: Prefix-Link, aber im Tooltip nur den Hint anzeigen, sonst nix
		GMS:ChatLink_Define("GMS", {
			title = "|cff03A9F4GMS|r",
			label = "|cff03A9F4[GMS]|r",
			hint = "/gms",
			tooltip = {
				"Öffnet das GMS Menü.",
			},
			flags = {
				showLabel = false,			-- label NICHT anzeigen
				showHint = true,			-- hint anzeigen
				showTooltipLines = false,	-- tooltip lines NICHT anzeigen
				showActionFallback = false,	-- fallback NICHT anzeigen
			},
		})

		GMS:ChatLink_OnClick("GMS", function()
			GMS:SlashCommand("?")
		end)

		local link = GMS:ChatLink_Build("GMS")
		GMS.CHAT_PREFIX = link

		GMS:Print("Klick hier: " .. link)

		-- Beispiel: gleiche Action, aber Tooltip-Titel pro Link überschreiben:
		local link2 = GMS:ChatLink_Build("GMS", "/gms")
		GMS:Print("Hover Title Override: " .. link2)
	end

-- Notify that ChatLinks core finished loading
pcall(function()
    if GMS and type(GMS.Print) == "function" then
        GMS:Print("ChatLinks wurde geladen")
    end
end)
