	
	-- ============================================================================
	--	GMS/Core/UI/Slash.lua
	--	Registers "/gms ui" via SLASHCOMMANDS module (if available)
	-- ============================================================================
	
	local LibStub = LibStub
	if not LibStub then return end
	
	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end
	
	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end
	
	local UI = GMS:GetModule("UI", true)
	if not UI then return end
	
	local MODULE_NAME = "UI"
	
	-- ---------------------------------------------------------------------------
	--	Registers the "ui" subcommand if SlashCommands module is available
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:SLASH_RegisterUiSubCommandIfAvailable()
	local SlashCommands = GMS:GetModule("SLASHCOMMANDS", true)
	if not SlashCommands or type(SlashCommands.API_RegisterSubCommand) ~= "function" then
		if self.LOG_Warn then
			self:LOG_Warn("SlashCommands not available; cannot register /gms ui", nil)
		end
		return
	end
	
	SlashCommands:API_RegisterSubCommand("ui", function(rest)
		if UI.WINDOW_OpenWindowAndNavigate then
			UI:WINDOW_OpenWindowAndNavigate((type(rest) == "string" and rest ~= "" and rest) or nil)
		end
	end, {
		help = "Öffnet die GMS UI (/gms ui [page])",
		alias = { "open" },
		owner = MODULE_NAME,
	})
	
	if self.LOG_Info then
		self:LOG_Info("Registered subcommand: /gms ui", nil)
	end
	end
