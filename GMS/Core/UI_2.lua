-- ============================================================================
--	GMS/Core/BootCheck.lua
--	Boot/Ready Checks
--	- Checkt ob _G.GMS existiert (Namespace vorhanden)
--	- Checkt ob GMS via AceAddon Registry vorhanden ist
--	- Checkt ob SlashCommands registriert sind
--	- Stellt Helper-Funktionen bereit, ohne harte Abhängigkeiten
-- ============================================================================

	local _G = _G

	-- Optional: wenn du willst, dass /run darauf zugreifen kann
	_G.GMS_BOOTCHECK = _G.GMS_BOOTCHECK or {}
	local BootCheck = _G.GMS_BOOTCHECK

	-- ---------------------------------------------------------------------------
	--	Intern: Safe LibStub/AceAddon
	-- ---------------------------------------------------------------------------

	local function INTERNAL_GetAceAddon()
		local LibStub = _G.LibStub
		if not LibStub then return nil end

		local AceAddon = LibStub("AceAddon-3.0", true)
		return AceAddon
	end

	-- ---------------------------------------------------------------------------
	--	1) Check: GMS Namespace vorhanden?
	-- ---------------------------------------------------------------------------

	function BootCheck:IsGMSNamespaceReady()
		return (_G.GMS ~= nil)
	end

	-- ---------------------------------------------------------------------------
	--	2) Check: GMS via AceAddon Registry vorhanden?
	-- ---------------------------------------------------------------------------

	function BootCheck:IsGMSAceReady()
		local AceAddon = INTERNAL_GetAceAddon()
		if not AceAddon then
			return false, "LibStub/AceAddon fehlt"
		end

		local addon = AceAddon:GetAddon("GMS", true)
		if addon then
			return true, addon
		end

		return false, "AceAddon:GetAddon('GMS') nil"
	end

	-- ---------------------------------------------------------------------------
	--	3) Check: SlashCommands registriert?
	--
	--	Heuristik:
	--	- SlashCmdList["GMS"] existiert und ist function
	--	- oder SLASH_GMS1 existiert (z.B. "/gms")
	--	- optional: _G.GMS.SLASH_READY oder _G.GMS.INTERNAL_SLASH_READY (falls du das setzt)
	-- ---------------------------------------------------------------------------

	function BootCheck:IsSlashCommandsReady()
		-- 1) direkter WoW-Mechanismus
		if _G.SlashCmdList and type(_G.SlashCmdList["GMS"]) == "function" then
			return true, "SlashCmdList.GMS"
		end

		-- 2) SLASH_* Konstanten
		if _G.SLASH_GMS1 ~= nil then
			return true, "SLASH_GMS1"
		end

		-- 3) optionales Flag im GMS Namespace (falls du es irgendwo setzt)
		if _G.GMS then
			if _G.GMS.SLASH_READY == true then
				return true, "GMS.SLASH_READY"
			end
			if _G.GMS.INTERNAL_SLASH_READY == true then
				return true, "GMS.INTERNAL_SLASH_READY"
			end
		end

		return false, "nicht registriert"
	end

	-- ---------------------------------------------------------------------------
	--	Komfort: Alles zusammen
	-- ---------------------------------------------------------------------------

	function BootCheck:CheckAll()
		local out = {
			gms_namespace = false,
			gms_ace = false,
			slash = false,
			ace_reason = nil,
			slash_reason = nil,
		}

		out.gms_namespace = self:IsGMSNamespaceReady()

		local ace_ok, ace_info = self:IsGMSAceReady()
		out.gms_ace = (ace_ok == true)
		if ace_ok ~= true then
			out.ace_reason = ace_info
		end

		local slash_ok, slash_info = self:IsSlashCommandsReady()
		out.slash = (slash_ok == true)
		if slash_ok ~= true then
			out.slash_reason = slash_info
		end

		return out
	end

	-- ---------------------------------------------------------------------------
	--	Optional: Debug Print (falls GMS:Print existiert, nutzt es das)
	-- ---------------------------------------------------------------------------

	function BootCheck:DebugPrint()
		local res = self:CheckAll()

		local function P(msg)
			if _G.GMS and type(_G.GMS.Print) == "function" then
				_G.GMS:Print(msg)
				return
			end
			if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
				_G.DEFAULT_CHAT_FRAME:AddMessage(tostring(msg))
			end
		end

		P(("BootCheck: GMS namespace = %s"):format(tostring(res.gms_namespace)))
		P(("BootCheck: GMS ace       = %s%s"):format(
			tostring(res.gms_ace),
			res.ace_reason and (" ("..tostring(res.ace_reason)..")") or ""
		))
		P(("BootCheck: Slashcommands = %s%s"):format(
			tostring(res.slash),
			res.slash_reason and (" ("..tostring(res.slash_reason)..")") or ""
		))
	end
