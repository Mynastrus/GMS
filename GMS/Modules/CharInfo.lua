-- ============================================================================
--	GMS/Modules/CharInfo.lua
--	CharInfo-Module (Ace-only)
--	- KEIN _G, KEIN addonTable
--	- Klinkt sich per AceAddon Registry an GMS
--	- Registriert eine UI-Page
--	- Registriert ein RightDock Icon (rechts)
--	- Baut auf der Page genau EINEN Button
-- ============================================================================

	local LibStub = LibStub
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

	local MODULE_NAME = "CHARINFO"
	local DISPLAY_NAME = "Char Info"

	local CharInfo = GMS:GetModule(MODULE_NAME, true)
	if not CharInfo then
		CharInfo = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
	end

	GMS[MODULE_NAME] = CharInfo

	CharInfo._pageRegistered = CharInfo._pageRegistered or false
	CharInfo._dockRegistered = CharInfo._dockRegistered or false

	-- ###########################################################################
	-- #	UI PAGE
	-- ###########################################################################

	function CharInfo:TryRegisterPage()
		if self._pageRegistered then
			return true
		end

		if not GMS.UI or type(GMS.UI.RegisterPage) ~= "function" then
			return false
		end

		GMS.UI:RegisterPage("CHARINFO", 60, DISPLAY_NAME, function(root)
            local ui = (GMS and (GMS.UI or GMS:GetModule("UI", true))) or nil
            local ctx = (ui and type(ui.GetNavigationContext) == "function") and ui:GetNavigationContext(true) or nil

            local guid = ctx and ctx.guid or nil
            local name_full = ctx and ctx.name_full or nil

            local wrapper = AceGUI:Create("SimpleGroup")
            wrapper:SetFullWidth(true)
            wrapper:SetFullHeight(true)
            wrapper:SetLayout("Flow")
            root:AddChild(wrapper)

            local title = AceGUI:Create("Label")
            title:SetFullWidth(true)
            title:SetText("|cff03A9F4CHARINFO|r")
            title.label:SetFontObject(GameFontNormalLarge)
            wrapper:AddChild(title)

            local info = AceGUI:Create("Label")
            info:SetFullWidth(true)
            info:SetText("GUID: " .. tostring(guid or "-") .. "\nName: " .. tostring(name_full or "-"))
            info.label:SetFontObject(GameFontNormalSmallOutline)
            wrapper:AddChild(info)

            local btn = AceGUI:Create("Button")
            btn:SetText("Debug: Context nochmal ausgeben")
            btn:SetWidth(260)
            btn:SetCallback("OnClick", function()
                if GMS and GMS.Print then
                    GMS:Print("CHARINFO ctx guid=" .. tostring(guid) .. " name_full=" .. tostring(name_full))
                end
            end)
            wrapper:AddChild(btn)
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

		if not GMS.UI or type(GMS.UI.AddRightDockIconTop) ~= "function" then
			return false
		end

		GMS.UI:AddRightDockIconTop({
			id = "CHARINFO",
			order = 60,
			selectable = true,
			icon = "Interface\\Icons\\INV_Misc_IDCard_01",
			tooltipTitle = DISPLAY_NAME,
			tooltipText = "Öffnet die Charakter-Info",
			onClick = function()
				GMS.UI:Open("CHARINFO")
			end,
		})

		self._dockRegistered = true
		return true
	end

	-- ###########################################################################
	-- #	INTEGRATION
	-- ###########################################################################

	function CharInfo:TryIntegrateWithUIIfAvailable()
		local okPage = self:TryRegisterPage()
		local okDock = self:TryRegisterDockIcon()

		if okPage and okDock then
			return
		end
	end

	-- ###########################################################################
	-- #	ACE LIFECYCLE
	-- ###########################################################################

	function CharInfo:OnEnable()
		self:TryIntegrateWithUIIfAvailable()

		if self._pageRegistered and self._dockRegistered then
			return
		end

		if self._waitFrame then
			return
		end

		self._waitFrame = CreateFrame("Frame")
		self._waitFrame:RegisterEvent("ADDON_LOADED")

		self._waitFrame:SetScript("OnEvent", function(frame, _, addonName)
			if addonName ~= "GMS" then return end

			CharInfo:TryIntegrateWithUIIfAvailable()

			if CharInfo._pageRegistered and CharInfo._dockRegistered then
				frame:UnregisterEvent("ADDON_LOADED")
				frame:SetScript("OnEvent", nil)
				CharInfo._waitFrame = nil
			end
		end)
	end
