	-- ============================================================================
	--	GMS/Core/SlashCommands.lua
	--	SlashCommands Core (Ace-only)
	--	- KEIN _G, KEIN addonTable
	--	- Zugriff auf GMS ausschließlich über AceAddon Registry
	--	- Registriert /gms (ein Command)
	--	- SubCommand-Registry für Module
	-- ============================================================================

	local LibStub = LibStub
	if not LibStub then return end

	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end

	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end

	local AceConsole = LibStub("AceConsole-3.0", true)
	if not AceConsole then return end

	-- ###########################################################################
	-- #	ACE MODULE
	-- ###########################################################################

	local MODULE_NAME = "SLASHCOMMANDS"
	local DISPLAY_NAME = "Slash Commands"

	local SlashCommands = GMS:NewModule(MODULE_NAME, "AceConsole-3.0")
	GMS.SlashCommands = SlashCommands

	-- ###########################################################################
	-- #	STATES (optional)
	-- ###########################################################################

	local STATES = (GMS and GMS.STATES) or nil

	local function STATE_Update(state, reason, meta)
		if not STATES or type(STATES.UPDATE) ~= "function" then
			return
		end
		STATES:UPDATE(MODULE_NAME, state, reason, meta)
	end

	-- Mark file load
	STATE_Update("LOADED")

	-- ###########################################################################
	-- #	STATE
	-- ###########################################################################

	SlashCommands.SUBCOMMAND_REGISTRY = SlashCommands.SUBCOMMAND_REGISTRY or {}
	SlashCommands.PRIMARY_COMMAND = "gms"

	-- ---------------------------------------------------------------------------
	--	Normalisiert einen SubCommand-Key
	--	@param rawKey string
	--	@return string
	-- ---------------------------------------------------------------------------

	local function NormalizeSubCommandKey(rawKey)
		if not rawKey then return "" end
		return string.lower(tostring(rawKey))
	end

	-- ---------------------------------------------------------------------------
	--	Parsed Input für "/gms <sub> <rest>"
	--	@param input string
	--	@return string subCommand
	--	@return string arguments
	--	@return string fullInput
	-- ---------------------------------------------------------------------------

	local function ParseGmsSlashInput(input)
		local fullInput = tostring(input or "")
		fullInput = string.gsub(fullInput, "^%s+", "")
		fullInput = string.gsub(fullInput, "%s+$", "")

		if fullInput == "" then
			return "", "", ""
		end

		local subCommand, rest = string.match(fullInput, "^(%S+)%s*(.*)$")
		subCommand = tostring(subCommand or "")
		rest = tostring(rest or "")
		return subCommand, rest, fullInput
	end

	-- ---------------------------------------------------------------------------
	--	Prüft, ob ein Wert ein Array von Strings ist
	--	@param value any
	--	@return boolean
	-- ---------------------------------------------------------------------------

	local function IsStringArray(value)
		if type(value) ~= "table" then return false end
		for _, v in ipairs(value) do
			if type(v) ~= "string" then return false end
		end
		return true
	end

	-- ---------------------------------------------------------------------------
	--	Sucht einen Registry-Eintrag nach Key oder Alias
	--	@param registry table
	--	@param subCommand string
	--	@return table|nil
	-- ---------------------------------------------------------------------------

	local function FindSubCommandEntry(registry, subCommand)
		local normalized = NormalizeSubCommandKey(subCommand)
		if normalized == "" then return nil end

		local direct = registry[normalized]
		if direct then return direct end

		for _, entry in pairs(registry) do
			local alias = entry and entry.alias
			if type(alias) == "string" then
				if NormalizeSubCommandKey(alias) == normalized then
					return entry
				end
			elseif IsStringArray(alias) then
				for _, a in ipairs(alias) do
					if NormalizeSubCommandKey(a) == normalized then
						return entry
					end
				end
			end
		end

		return nil
	end

	-- ---------------------------------------------------------------------------
	--	Gibt Hilfe / SubCommand-Liste aus
	--	@param registry table
	--	@param header string|nil
	--	@return nil
	-- ---------------------------------------------------------------------------

	local function PrintGmsHelp(registry, header)
		if header and header ~= "" then
			GMS:Print(tostring(header))
		end

		GMS:Print("Usage: /gms <subcommand> [args]")
		GMS:Print("Example: /gms help")

		local keys = {}
		for key, _ in pairs(registry) do
			keys[#keys + 1] = key
		end
		table.sort(keys)

		if #keys == 0 then
			GMS:Print("No subcommands registered.")
			return
		end

		GMS:Print("Subcommands:")
		for _, key in ipairs(keys) do
			local entry = registry[key]
			local helpText = entry and entry.help or ""
			if helpText ~= "" then
				GMS:Printf(" - %s: %s", key, helpText)
			else
				GMS:Printf(" - %s", key)
			end
		end
	end

	-- ---------------------------------------------------------------------------
	--	Dispatcher für /gms
	--	@param input string
	--	@return nil
	-- ---------------------------------------------------------------------------

	local function HandleGmsSlashCommandInput(input)
		local subCommand, arguments, fullInput = ParseGmsSlashInput(input)

		if subCommand == "" then
			HandleGmsSlashCommandInput("ui")
			return
		end
		if subCommand == "help" or subCommand == "?" then
			PrintGmsHelp(SlashCommands.SUBCOMMAND_REGISTRY, DISPLAY_NAME)
			return
		end

		local entry = FindSubCommandEntry(SlashCommands.SUBCOMMAND_REGISTRY, subCommand)
		if not entry or type(entry.handlerFn) ~= "function" then
			PrintGmsHelp(SlashCommands.SUBCOMMAND_REGISTRY, "Unknown subcommand: " .. tostring(subCommand))
			return
		end

		local ok, err = pcall(entry.handlerFn, tostring(arguments), tostring(fullInput), tostring(subCommand))
		if not ok then
			GMS:LOG_Error(MODULE_NAME, "Subcommand handler error", { sub = subCommand, error = tostring(err) })
			GMS:Printf("Error executing '%s'. Check logs.", tostring(subCommand))
		end
	end

	-- ###########################################################################
	-- #	PUBLIC API (für Module)
	-- ###########################################################################

	function SlashCommands:API_RegisterSubCommand(key, handlerFn, opts)
		local normalizedKey = NormalizeSubCommandKey(key)
		if normalizedKey == "" then
			GMS:LOG_Error(MODULE_NAME, "RegisterSubCommand failed: empty key", { key = key })
			return false
		end

		if type(handlerFn) ~= "function" then
			GMS:LOG_Error(MODULE_NAME, "RegisterSubCommand failed: handlerFn not function", { key = normalizedKey, handlerType = type(handlerFn) })
			return false
		end

		opts = opts or {}

		self.SUBCOMMAND_REGISTRY[normalizedKey] = {
			key = normalizedKey,
			handlerFn = handlerFn,
			help = tostring(opts.help or ""),
			alias = opts.alias,
			owner = tostring(opts.owner or ""),
		}

		GMS:LOG_Info(MODULE_NAME, "Subcommand registered", { key = normalizedKey, owner = opts.owner, help = opts.help })
		return true
	end

	function SlashCommands:API_UnregisterSubCommand(key)
		local normalizedKey = NormalizeSubCommandKey(key)
		if normalizedKey == "" then return false end

		if self.SUBCOMMAND_REGISTRY[normalizedKey] then
			self.SUBCOMMAND_REGISTRY[normalizedKey] = nil
			GMS:LOG_Info(MODULE_NAME, "Subcommand unregistered", { key = normalizedKey })
			return true
		end

		return false
	end

	function SlashCommands:API_PrintHelp()
		PrintGmsHelp(self.SUBCOMMAND_REGISTRY, DISPLAY_NAME)
	end

	-- ###########################################################################
	-- #	ACE LIFECYCLE
	-- ###########################################################################

	function SlashCommands:OnInitialize()
		STATE_Update("INITIALIZED")
	end

	function SlashCommands:OnEnable()
		STATE_Update("ENABLED")

		if self.DID_REGISTER_PRIMARY_COMMAND then
			-- bereits registriert => trotzdem ready markieren (idempotent)
			STATE_Update("READY")
			return
		end

		self.DID_REGISTER_PRIMARY_COMMAND = true

		GMS:RegisterChatCommand(self.PRIMARY_COMMAND, function(input)
			HandleGmsSlashCommandInput(input)
		end)

		GMS:LOG_Info(MODULE_NAME, "Primary slash command registered", { cmd = "/gms" })

		-- Jetzt ist /gms wirklich da
		STATE_Update("READY")
	end

	function SlashCommands:OnDisable()
		STATE_Update("DISABLED")
	end
