-- ============================================================================
--	GMS/Modules/CharInfo.lua
--	CharInfo-Module (Ace)
--	- Zugriff auf GMS über AceAddon Registry
--	- Registriert UI-Page + RightDock Icon (TOP)
--	- Style aligned with UI Extension (helpers/log/safecall/guards)
-- ============================================================================

	local _G = _G
	local LibStub = _G.LibStub
	if not LibStub then return end

	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end

	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end

	local AceGUI = LibStub("AceGUI-3.0", true)
	if not AceGUI then return end

	-- ###########################################################################
	-- #	MODULE
	-- ###########################################################################

	local MODULE_NAME  = "CHARINFO"
	local DISPLAY_NAME = "Charakterinformationen"

	local CharInfo = GMS:GetModule(MODULE_NAME, true)
	if not CharInfo then
		CharInfo = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
	end

	GMS[MODULE_NAME] = CharInfo

	CharInfo._pageRegistered = CharInfo._pageRegistered or false
	CharInfo._dockRegistered = CharInfo._dockRegistered or false
	CharInfo._integrated     = CharInfo._integrated or false
	CharInfo._ticker         = CharInfo._ticker or nil

	-- ###########################################################################
	-- #	INTERNAL HELPERS (style aligned)
	-- ###########################################################################

	local function Log(level, message, context)
		if level == "ERROR" then
			if type(GMS.LOG_Error) == "function" then GMS:LOG_Error(MODULE_NAME, message, context) end
		elseif level == "WARN" then
			if type(GMS.LOG_Warn) == "function" then GMS:LOG_Warn(MODULE_NAME, message, context) end
		elseif level == "DEBUG" then
			if type(GMS.LOG_Debug) == "function" then GMS:LOG_Debug(MODULE_NAME, message, context) end
		else
			if type(GMS.LOG_Info) == "function" then GMS:LOG_Info(MODULE_NAME, message, context) end
		end
	end

	local function SafeCall(fn, ...)
		if type(fn) ~= "function" then return false end
		local ok, err = pcall(fn, ...)
		if not ok then
			Log("ERROR", "CharInfo error", { err = tostring(err) })
			if type(GMS.Print) == "function" then
				GMS:Print("CharInfo Fehler: " .. tostring(err))
			end
		end
		return ok
	end

	local function UIRef()
		-- UI ist eine Extension (table an GMS), alternativ könnte es ein Module sein.
		return (GMS and (GMS.UI or GMS:GetModule("UI", true))) or nil
	end

	local function GetNavContext(consume)
		local ui = UIRef()
		if ui and type(ui.GetNavigationContext) == "function" then
			return ui:GetNavigationContext(consume == true)
		end
		return nil
	end

	-- ###########################################################################
	-- #	UI PAGE
	-- ###########################################################################

	function CharInfo:TryRegisterPage()
		if self._pageRegistered then
			return true
		end

		local ui = UIRef()
		if not ui or type(ui.RegisterPage) ~= "function" then
			return false
		end

		ui:RegisterPage("CHARINFO", 60, DISPLAY_NAME, function(root)
			local ctx = GetNavContext(true) or {}

			local guid = ctx.guid
			local name_full = ctx.name_full or ctx.name
			local realm = ctx.realm

			local function ctxLine()
				local nm = name_full or "-"
				if realm and realm ~= "" then nm = nm .. "-" .. tostring(realm) end
				return "GUID: " .. tostring(guid or "-") .. "\nName: " .. tostring(nm)
			end

			local wrapper = AceGUI:Create("SimpleGroup")
			wrapper:SetFullWidth(true)
			wrapper:SetFullHeight(true)
			wrapper:SetLayout("Flow")
			root:AddChild(wrapper)

			local title = AceGUI:Create("Label")
			title:SetFullWidth(true)
			title:SetText("|cff03A9F4CHARINFO|r")
			if title.label then
				title.label:SetFontObject(_G.GameFontNormalLarge)
			end
			wrapper:AddChild(title)

			local info = AceGUI:Create("Label")
			info:SetFullWidth(true)
			info:SetText(ctxLine())
			if info.label then
				info.label:SetFontObject(_G.GameFontNormalSmallOutline)
			end
			wrapper:AddChild(info)

			local btnRow = AceGUI:Create("SimpleGroup")
			btnRow:SetFullWidth(true)
			btnRow:SetLayout("Flow")
			wrapper:AddChild(btnRow)

			local btnRefresh = AceGUI:Create("Button")
			btnRefresh:SetText("Context erneut lesen")
			btnRefresh:SetWidth(200)
			btnRefresh:SetCallback("OnClick", function()
				-- Nicht-consume lesen (falls irgendwer ihn wieder gesetzt hat)
				local ctx2 = GetNavContext(false) or {}
				guid = ctx2.guid or guid
				name_full = ctx2.name_full or ctx2.name or name_full
				realm = ctx2.realm or realm
				info:SetText(ctxLine())
			end)
			btnRow:AddChild(btnRefresh)

			local btnDebug = AceGUI:Create("Button")
			btnDebug:SetText("Debug: Print")
			btnDebug:SetWidth(140)
			btnDebug:SetCallback("OnClick", function()
				if GMS and type(GMS.Print) == "function" then
					local nm = name_full or "-"
					if realm and realm ~= "" then nm = nm .. "-" .. tostring(realm) end
					GMS:Print("CHARINFO ctx guid=" .. tostring(guid or "-") .. " name_full=" .. tostring(nm))
				end
			end)
			btnRow:AddChild(btnDebug)
		end)

		self._pageRegistered = true
		return true
	end

	-- ###########################################################################
	-- #	RIGHT DOCK ICON
	-- ###########################################################################

	function CharInfo:TryRegisterDockIcon()
		if self._dockRegistered then
			return true
		end

		local ui = UIRef()
		if not ui or type(ui.AddRightDockIconTop) ~= "function" then
			return false
		end

		ui:AddRightDockIconTop({
			id = "CHARINFO",
			order = 60,
			selectable = true,
			icon = "Interface\\Icons\\inv_helm_armor_tatteredhoodmasked_b_01",
			tooltipTitle = DISPLAY_NAME,
			tooltipText = "Öffnet die Charakter-Info",
			onClick = function()
				local u = UIRef()
				if u and type(u.Open) == "function" then
					u:Open("CHARINFO")
				end
			end,
		})

		self._dockRegistered = true
		return true
	end

	-- ###########################################################################
	-- #	INTEGRATION / RETRY
	-- ###########################################################################

	function CharInfo:TryIntegrateWithUIIfAvailable()
		if self._integrated then
			return true
		end

		local okPage = self:TryRegisterPage()
		local okDock = self:TryRegisterDockIcon()

		if okPage and okDock then
			self._integrated = true
			Log("INFO", "Integrated with UI", nil)

			if self._ticker and self._ticker.Cancel then
				self._ticker:Cancel()
			end
			self._ticker = nil

			-- optional: Statusbar Hinweis
			local ui = UIRef()
			if ui and type(ui.SetStatusText) == "function" then
				ui:SetStatusText("|cff03A9F4CharInfo|r: bereit")
			end

			return true
		end

		return false
	end

	function CharInfo:StartIntegrationTicker()
		if self._integrated then return end
		if self._ticker then return end
		if not _G.C_Timer or type(_G.C_Timer.NewTicker) ~= "function" then return end

		local tries = 0
		self._ticker = _G.C_Timer.NewTicker(0.50, function()
			tries = tries + 1
			if CharInfo:TryIntegrateWithUIIfAvailable() then
				return
			end
			if tries >= 30 then
				-- ~15s max
				if CharInfo._ticker and CharInfo._ticker.Cancel then CharInfo._ticker:Cancel() end
				CharInfo._ticker = nil
				Log("WARN", "UI not available (gave up retries)", nil)
			end
		end)
	end

	-- ###########################################################################
	-- #	ACE LIFECYCLE
	-- ###########################################################################

	function CharInfo:OnEnable()
		-- Sofort versuchen (falls UI schon da ist)
		if self:TryIntegrateWithUIIfAvailable() then
			return
		end

		-- Retry: UI kann später in der TOC kommen
		self:StartIntegrationTicker()

		-- Zusätzlich: Bei PLAYER_LOGIN nochmal versuchen (manchmal kommen Abhängigkeiten spät)
		if type(self.RegisterEvent) == "function" then
			self:RegisterEvent("PLAYER_LOGIN", function()
				SafeCall(CharInfo.TryIntegrateWithUIIfAvailable, CharInfo)
			end)
		end
	end

	function CharInfo:OnDisable()
		-- Keine harte Deregistration: UI-Registry ist global; Module kann wieder enabled werden.
		if self._ticker and self._ticker.Cancel then
			self._ticker:Cancel()
		end
		self._ticker = nil
	end
