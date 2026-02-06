-- ============================================================================
--	GMS/Modules/CharInfo.lua
--	CharInfo MODULE (Ace)
--	- Zugriff auf GMS über AceAddon Registry
--	- UI-Page + RightDock Icon
--	- Zeigt Player-Snapshot + ctx (optional) + Auswahl-Buttons
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

	local MODULE_NAME	= "CHARINFO"
	local DISPLAY_NAME	= "Charakterinformationen"

	local CHARINFO = GMS:GetModule(MODULE_NAME, true)
	if not CHARINFO then
		CHARINFO = GMS:NewModule(MODULE_NAME, "AceEvent-3.0")
	end

	GMS[MODULE_NAME] = CHARINFO

	CHARINFO._pageRegistered = CHARINFO._pageRegistered or false
	CHARINFO._dockRegistered = CHARINFO._dockRegistered or false
	CHARINFO._integrated     = CHARINFO._integrated or false
	CHARINFO._ticker         = CHARINFO._ticker or nil

	-- DB for account-wide character logging
	CHARINFO._db = CHARINFO._db or nil

	local DB_DEFAULTS = {
		profile = {},
		global = {
			characters = {}, -- table: { name_full = { name, realm, guid, timestamp } }
		}
	}

	-- Icon: nimm einen, der bei dir existiert (du kannst ihn per /run testen)
	local ICON = "Interface\\Icons\\INV_Misc_Head_Human_01"

	-- ###########################################################################
	-- #	HELPERS (style aligned)
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
		return (GMS and (GMS.UI or GMS:GetModule("UI", true))) or nil
	end

	local function GetNavContext(consume)
		local ui = UIRef()
		if ui and type(ui.GetNavigationContext) == "function" then
			return ui:GetNavigationContext(consume == true)
		end
		return nil
	end

	local function SetNavContext(ctx)
		local ui = UIRef()
		if ui and type(ui.SetNavigationContext) == "function" then
			ui:SetNavigationContext(ctx)
			return true
		end
		return false
	end

	local function OpenSelf()
		local ui = UIRef()
		if ui and type(ui.Open) == "function" then
			ui:Open("CHARINFO")
			return true
		end
		return false
	end

	local function FormatNameRealm(name, realm)
		name = tostring(name or "")
		realm = tostring(realm or "")
		if name == "" then return "-" end
		if realm ~= "" then
			return name .. "-" .. realm
		end
		return name
	end

	local function GetPlayerSnapshot()
		local name, realm = _G.UnitFullName("player")
		local className = _G.UnitClass("player") -- localized
		local raceName = _G.UnitRace("player") -- localized
		local level = _G.UnitLevel("player")

		local guildName = _G.GetGuildInfo and _G.GetGuildInfo("player") or nil

		local specName = "-"
		if type(_G.GetSpecialization) == "function" and type(_G.GetSpecializationInfo) == "function" then
			local specIndex = _G.GetSpecialization()
			if specIndex then
				local _, sName = _G.GetSpecializationInfo(specIndex)
				if sName and sName ~= "" then specName = sName end
			end
		end

		local ilvlEquipped = nil
		local ilvlOverall = nil
		if type(_G.GetAverageItemLevel) == "function" then
			local overall, equipped = _G.GetAverageItemLevel()
			ilvlOverall = overall
			ilvlEquipped = equipped
		end

		return {
			name = name,
			realm = realm,
			name_full = FormatNameRealm(name, realm),
			class = className or "-",
			spec = specName,
			race = raceName or "-",
			level = level or "-",
			guild = guildName or "-",
			ilvl = (ilvlEquipped and string.format("%.1f", ilvlEquipped)) or "-",
			ilvl_overall = (ilvlOverall and string.format("%.1f", ilvlOverall)) or "-",
			guid = (_G.UnitGUID and _G.UnitGUID("player")) or nil,
		}
	end

	local function GetTargetSnapshot()
		if not (_G.UnitExists and _G.UnitExists("target")) then return nil end
		if not (_G.UnitIsPlayer and _G.UnitIsPlayer("target")) then return nil end

		local name, realm = _G.UnitFullName("target")
		local className = _G.UnitClass("target")
		local raceName = _G.UnitRace("target")
		local level = _G.UnitLevel("target")
		local guid = (_G.UnitGUID and _G.UnitGUID("target")) or nil

		-- Spec / ilvl für target sind ohne Inspect nicht zuverlässig -> bewusst "-"
		return {
			name = name,
			realm = realm,
			name_full = FormatNameRealm(name, realm),
			class = className or "-",
			spec = "-",
			race = raceName or "-",
			level = level or "-",
			guild = "-",
			ilvl = "-",
			ilvl_overall = "-",
			guid = guid,
		}
	end

	local function RenderBlock(titleText, lines)
		local out = {}
		out[#out + 1] = "|cff03A9F4" .. tostring(titleText or "") .. "|r"
		for _, l in ipairs(lines or {}) do
			out[#out + 1] = tostring(l)
		end
		return table.concat(out, "\n")
	end

	-- ###########################################################################
	-- #	UI PAGE
	-- ###########################################################################

	function CHARINFO:TryRegisterPage()
		if self._pageRegistered then return true end

		local ui = UIRef()
		if not ui or type(ui.RegisterPage) ~= "function" then
			return false
		end

		ui:RegisterPage("CHARINFO", 60, DISPLAY_NAME, function(root)
			local ui2 = UIRef()
			local ctx = GetNavContext(true) or nil
			local player = GetPlayerSnapshot()

			-- optional: wenn ctx leer -> "selbst auswählbar" (Button). Wir setzen NICHT automatisch.
			local ctxName = ctx and ctx.name_full or nil
			local ctxGuid = ctx and ctx.guid or nil
			local ctxFrom = ctx and (ctx.from or ctx.source) or nil

			-- Header/Footer
			if ui2 and type(ui2.Header_BuildIconText) == "function" then
				ui2:Header_BuildIconText({
					icon = ICON,
					text = "|cff03A9F4" .. DISPLAY_NAME .. "|r",
					subtext = ctxName and ("Context: |cffCCCCCC" .. tostring(ctxName) .. "|r") or "Kein Context gesetzt",
				})
			end
			if ui2 and type(ui2.SetStatusText) == "function" then
				ui2:SetStatusText(ctxName and "CHARINFO: ctx aktiv" or "CHARINFO: nur player")
			end

			local wrapper = AceGUI:Create("SimpleGroup")
			wrapper:SetFullWidth(true)
			wrapper:SetFullHeight(true)
			wrapper:SetLayout("Flow")
			root:AddChild(wrapper)

			-- Player Block
			local lblPlayer = AceGUI:Create("Label")
			lblPlayer:SetFullWidth(true)
			lblPlayer:SetText(RenderBlock("Player", {
				"Name: " .. tostring(player.name_full or "-"),
				"Level: " .. tostring(player.level or "-"),
				"Race: " .. tostring(player.race or "-"),
				"Class: " .. tostring(player.class or "-"),
				"Spec: " .. tostring(player.spec or "-"),
				"iLvL: " .. tostring(player.ilvl or "-") .. " (overall " .. tostring(player.ilvl_overall or "-") .. ")",
				"Guild: " .. tostring(player.guild or "-"),
				"GUID: " .. tostring(player.guid or "-"),
			}))
			if lblPlayer.label then
				lblPlayer.label:SetFontObject(_G.GameFontNormalSmallOutline)
			end
			wrapper:AddChild(lblPlayer)

			-- Buttons row
			local row = AceGUI:Create("SimpleGroup")
			row:SetFullWidth(true)
			row:SetLayout("Flow")
			wrapper:AddChild(row)

			local btnSelf = AceGUI:Create("Button")
			btnSelf:SetText("Spieler selbst auswählen")
			btnSelf:SetWidth(200)
			btnSelf:SetCallback("OnClick", function()
				SetNavContext({
					from = "charinfo",
					name_full = player.name_full,
					guid = player.guid,
					unit = "player",
				})
				if ui2 and type(ui2.SetStatusText) == "function" then
					ui2:SetStatusText("CHARINFO: ctx = player gesetzt")
				end
				OpenSelf()
			end)
			row:AddChild(btnSelf)

			local btnTarget = AceGUI:Create("Button")
			btnTarget:SetText("Target auswählen")
			btnTarget:SetWidth(160)
			btnTarget:SetCallback("OnClick", function()
				local t = GetTargetSnapshot()
				if not t then
					if ui2 and type(ui2.SetStatusText) == "function" then
						ui2:SetStatusText("CHARINFO: kein Spieler-Target")
					end
					return
				end
				SetNavContext({
					from = "charinfo",
					name_full = t.name_full,
					guid = t.guid,
					unit = "target",
				})
				if ui2 and type(ui2.SetStatusText) == "function" then
					ui2:SetStatusText("CHARINFO: ctx = target gesetzt")
				end
				OpenSelf()
			end)
			row:AddChild(btnTarget)

			local btnClear = AceGUI:Create("Button")
			btnClear:SetText("Context löschen")
			btnClear:SetWidth(140)
			btnClear:SetCallback("OnClick", function()
				SetNavContext(nil)
				if ui2 and type(ui2.SetStatusText) == "function" then
					ui2:SetStatusText("CHARINFO: ctx gelöscht")
				end
				OpenSelf()
			end)
			row:AddChild(btnClear)

			-- ctx Block (falls vorhanden)
			local lblCtx = AceGUI:Create("Label")
			lblCtx:SetFullWidth(true)
			lblCtx:SetText(RenderBlock("Context", {
				"From: " .. tostring(ctxFrom or "-"),
				"Name: " .. tostring(ctxName or "-"),
				"GUID: " .. tostring(ctxGuid or "-"),
			}))
			if lblCtx.label then
				lblCtx.label:SetFontObject(_G.GameFontNormalSmallOutline)
			end
			wrapper:AddChild(lblCtx)

			-- Debug Button
			local btnDbg = AceGUI:Create("Button")
			btnDbg:SetText("Debug: Print Player + Ctx")
			btnDbg:SetWidth(220)
			btnDbg:SetCallback("OnClick", function()
				if GMS and type(GMS.Print) == "function" then
					GMS:Print("CHARINFO player=" .. tostring(player.name_full) .. " guid=" .. tostring(player.guid))
					GMS:Print("CHARINFO ctx=" .. tostring(ctxName) .. " guid=" .. tostring(ctxGuid) .. " from=" .. tostring(ctxFrom))
				end
			end)
			wrapper:AddChild(btnDbg)
		end)

		self._pageRegistered = true
		return true
	end

	-- ###########################################################################
	-- #	RIGHT DOCK ICON
	-- ###########################################################################

	function CHARINFO:TryRegisterDockIcon()
		if self._dockRegistered then return true end

		local ui = UIRef()
		if not ui or type(ui.AddRightDockIconTop) ~= "function" then
			return false
		end

		ui:AddRightDockIconTop({
			id = "CHARINFO",
			order = 60,
			selectable = true,
			icon = ICON,
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

	function CHARINFO:TryIntegrateWithUIIfAvailable()
		if self._integrated then return true end

		local okPage = self:TryRegisterPage()
		local okDock = self:TryRegisterDockIcon()

		if okPage and okDock then
			self._integrated = true
			if self._ticker and self._ticker.Cancel then self._ticker:Cancel() end
			self._ticker = nil
			Log("INFO", "Integrated with UI", nil)
			return true
		end
		return false
	end

	function CHARINFO:StartIntegrationTicker()
		if self._integrated then return end
		if self._ticker then return end
		if not _G.C_Timer or type(_G.C_Timer.NewTicker) ~= "function" then return end

		local tries = 0
		self._ticker = _G.C_Timer.NewTicker(0.50, function()
			tries = tries + 1
			if CHARINFO:TryIntegrateWithUIIfAvailable() then return end
			if tries >= 30 then
				if CHARINFO._ticker and CHARINFO._ticker.Cancel then CHARINFO._ticker:Cancel() end
				CHARINFO._ticker = nil
				Log("WARN", "UI not available (gave up retries)", nil)
			end
		end)
	end

	-- ###########################################################################
	-- #	ACE LIFECYCLE
	-- ###########################################################################

	function CHARINFO:InitializeCharacterLog()
		-- Register or fetch DB namespace for character logging
		if GMS and GMS.DB and type(GMS.DB.RegisterModule) == "function" then
			local ok, ns = pcall(function()
				return GMS.DB:RegisterModule("CHARINFO", DB_DEFAULTS, nil)
			end)
			if ok and ns then
				self._db = ns
			end
		end

		-- Fallback: use direct DB access if available
		if not self._db and GMS and GMS.db then
			local ok, ns = pcall(function()
				return GMS.db:RegisterNamespace("CHARINFO", DB_DEFAULTS)
			end)
			if ok and ns then
				self._db = ns
			end
		end

		-- Auto-log current player to account-wide character table
		if self._db and self._db.global and type(self._db.global) == "table" then
			self._db.global.characters = self._db.global.characters or {}

			local snap = GetPlayerSnapshot()
			if snap and snap.name_full then
				self._db.global.characters[snap.name_full] = {
					name = snap.name,
					realm = snap.realm,
					guid = snap.guid,
					timestamp = _G.time and _G.time() or 0,
					class = snap.class,
					level = snap.level,
				}
				Log("INFO", "Character logged: " .. snap.name_full, nil)
			end
		end
	end

	function CHARINFO:OnEnable()
		-- Initialize and log character to account-wide DB
		SafeCall(CHARINFO.InitializeCharacterLog, CHARINFO)

		if self:TryIntegrateWithUIIfAvailable() then return end
		self:StartIntegrationTicker()

		if type(self.RegisterEvent) == "function" then
			self:RegisterEvent("PLAYER_LOGIN", function()
				SafeCall(CharInfo.TryIntegrateWithUIIfAvailable, CharInfo)
			end)
		end
	end

	function CHARINFO:OnDisable()
		if self._ticker and self._ticker.Cancel then self._ticker:Cancel() end
		self._ticker = nil
	end
