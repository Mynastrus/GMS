	-- ============================================================================
	--	GMS/Core/SlashCommands.lua
	--	SlashCommands EXTENSION (no GMS:NewModule)
	--	- Zugriff auf GMS über AceAddon Registry
	--	- Registriert /gms (ein Command) via AceConsole-Mixin am GMS
	--	- SubCommand-Registry für Module/Extensions
	--	- Optional: STATES Updates (wenn vorhanden)
	-- ============================================================================

	local LibStub = _G.LibStub
	if not LibStub then return end

	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end

	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end

	-- Für RegisterChatCommand muss GMS AceConsole gemixt haben
	if type(GMS.RegisterChatCommand) ~= "function" then
		return
	end

	-- ###########################################################################
	-- #	META
	-- ###########################################################################

    GMS.SlashCommands = GMS.SlashCommands or {}
	local SlashCommands = GMS.SlashCommands
    
    local EXT_NAME = "SLASHCOMMANDS"
    local DISPLAY_NAME = "Chateingabe"

	SlashCommands.SUBCOMMAND_REGISTRY = SlashCommands.SUBCOMMAND_REGISTRY or {}
	SlashCommands.PRIMARY_COMMAND = SlashCommands.PRIMARY_COMMAND or "gms"

	-- ###########################################################################
	-- #	INTERNAL HELPERS
	-- ###########################################################################

	local function LOWER(s)
		return string.lower(tostring(s or ""))
	end

	local function TRIM(s)
		s = tostring(s or "")
		s = string.gsub(s, "^%s+", "")
		s = string.gsub(s, "%s+$", "")
		return s
	end

	local function NormalizeSubCommandKey(rawKey)
		return LOWER(TRIM(rawKey))
	end

	local function ParseGmsSlashInput(input)
		local fullInput = TRIM(input)

		if fullInput == "" then
			return "", "", ""
		end

		local subCommand, rest = string.match(fullInput, "^(%S+)%s*(.*)$")
		subCommand = tostring(subCommand or "")
		rest = tostring(rest or "")
		return subCommand, rest, fullInput
	end

	local function IsStringArray(value)
		if type(value) ~= "table" then return false end
		for _, v in ipairs(value) do
			if type(v) ~= "string" then return false end
		end
		return true
	end

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

	local function PrintGmsHelp(registry, header)
		if header and header ~= "" then
			if type(GMS.Print) == "function" then
				GMS:Print(tostring(header))
			end
		end

		if type(GMS.Print) == "function" then
			GMS:Print("Usage: /gms <subcommand> [args]")
			GMS:Print("Example: /gms help")
		end

		local keys = {}
		for key, _ in pairs(registry) do
			keys[#keys + 1] = key
		end
		table.sort(keys)

		if #keys == 0 then
			if type(GMS.Print) == "function" then
				GMS:Print("No subcommands registered.")
			end
			return
		end

		if type(GMS.Print) == "function" then
			GMS:Print("Subcommands:")
		end

		for _, key in ipairs(keys) do
			local entry = registry[key]
			local helpText = entry and entry.help or ""
			if helpText ~= "" then
				if type(GMS.Printf) == "function" then
					GMS:Printf(" - %s: %s", key, helpText)
				elseif type(GMS.Print) == "function" then
					GMS:Print(" - " .. key .. ": " .. helpText)
				end
			else
				if type(GMS.Printf) == "function" then
					GMS:Printf(" - %s", key)
				elseif type(GMS.Print) == "function" then
					GMS:Print(" - " .. key)
				end
			end
		end
	end

	-- ###########################################################################
	-- #	DISPATCHER
	-- ###########################################################################

	local function HandleGmsSlashCommandInput(input)
		local subCommand, arguments, fullInput = ParseGmsSlashInput(input)

		if subCommand == "" then
			HandleGmsSlashCommandInput("?")
			return
		end

		local subNorm = NormalizeSubCommandKey(subCommand)
		if subNorm == "help" or subNorm == "?" then
			PrintGmsHelp(SlashCommands.SUBCOMMAND_REGISTRY, DISPLAY_NAME)
			return
		end

		local entry = FindSubCommandEntry(SlashCommands.SUBCOMMAND_REGISTRY, subNorm)
		if not entry or type(entry.handlerFn) ~= "function" then
			PrintGmsHelp(SlashCommands.SUBCOMMAND_REGISTRY, "Unknown subcommand: " .. tostring(subCommand))
			return
		end

		local ok, err = pcall(entry.handlerFn, tostring(arguments), tostring(fullInput), tostring(subCommand))
		if not ok then
			if type(GMS.LOG_Error) == "function" then
				GMS:LOG_Error(EXT_NAME, "Subcommand handler error", { sub = subCommand, error = tostring(err) })
			end
			if type(GMS.Printf) == "function" then
				GMS:Printf("Error executing '%s'. Check logs.", tostring(subCommand))
			elseif type(GMS.Print) == "function" then
				GMS:Print("Error executing '" .. tostring(subCommand) .. "'. Check logs.")
			end
		end
	end

	-- ###########################################################################
	-- #	PUBLIC API (für Module/Extensions)
	-- ###########################################################################

	function GMS:Slash_RegisterSubCommand(key, handlerFn, opts)
		local normalizedKey = NormalizeSubCommandKey(key)
		if normalizedKey == "" then
			if type(GMS.LOG_Error) == "function" then
				GMS:LOG_Error(EXT_NAME, "RegisterSubCommand failed: empty key", { key = key })
			end
			return false
		end

		if type(handlerFn) ~= "function" then
			if type(GMS.LOG_Error) == "function" then
				GMS:LOG_Error(EXT_NAME, "RegisterSubCommand failed: handlerFn not function", { key = normalizedKey, handlerType = type(handlerFn) })
			end
			return false
		end

		opts = opts or {}

		SlashCommands.SUBCOMMAND_REGISTRY[normalizedKey] = {
			key = normalizedKey,
			handlerFn = handlerFn,
			help = tostring(opts.help or ""),
			alias = opts.alias,
			owner = tostring(opts.owner or ""),
		}

		if type(GMS.LOG_Info) == "function" then
			GMS:LOG_Info(EXT_NAME, "Subcommand registered", { key = normalizedKey, owner = opts.owner, help = opts.help })
		end

		return true
	end

	function GMS:Slash_UnregisterSubCommand(key)
		local normalizedKey = NormalizeSubCommandKey(key)
		if normalizedKey == "" then return false end

		if SlashCommands.SUBCOMMAND_REGISTRY[normalizedKey] then
			SlashCommands.SUBCOMMAND_REGISTRY[normalizedKey] = nil

			if type(GMS.LOG_Info) == "function" then
				GMS:LOG_Info(EXT_NAME, "Subcommand unregistered", { key = normalizedKey })
			end

			return true
		end

		return false
	end

	function GMS:Slash_PrintHelp()
		PrintGmsHelp(SlashCommands.SUBCOMMAND_REGISTRY, DISPLAY_NAME)
	end

	-- Shortcut: kompatibel zu deinem bisherigen Pattern
	function GMS:SlashCommand(input)
		HandleGmsSlashCommandInput(input)
	end

	-- ###########################################################################
	-- #	BOOTSTRAP (einmalig)
	-- ###########################################################################

	if not SlashCommands._registered then
		SlashCommands._registered = true

		GMS:RegisterChatCommand(SlashCommands.PRIMARY_COMMAND, function(input)
			HandleGmsSlashCommandInput(input)
		end)
	end

    if not SlashCommands._defaultsLoaded then
		SlashCommands._defaultsLoaded = true

		GMS:Slash_RegisterSubCommand("reload", function()
            if ReloadUI then
                ReloadUI()
            end
        end, {
            help = "Lädt die UI neu.",
            alias = { "rl" },
            owner = EXT_NAME,
        })
	end

-- Notify that SlashCommands core finished loading
pcall(function()
	if GMS and type(GMS.Print) == "function" then
		GMS:Print("SlashCommands wurde geladen")
	end
end)
