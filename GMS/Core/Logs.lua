	-- ============================================================================
	--	GMS/Core/Logs.lua
	--	LOGS EXTENSION (no GMS:NewModule)
	--	- Ringbuffer + Level-Filter + optionale Chat-Ausgabe
	--	- Optional: AceDB-3.0 Settings
	--	- Optional: UI-Page (AceGUI + GMS UI registry)
	--	- Optional: SlashCommand (/gms logs ...) via GMS.SlashCommands
	--
	--	API:
	--		GMS:Log(level, msg, ...)
	--		GMS:Logf(level, fmt, ...)
	--		GMS:Trace(...), :Debug(...), :Info(...), :Warn(...), :Error(...)
	--		GMS:Logs_GetEntries([n], [minLevel])
	--		GMS:Logs_Clear()
	--		GMS:Logs_SetLevel(level) / :Logs_GetLevel()
	--		GMS:Logs_EnableChat(true/false) / :Logs_IsChatEnabled()
	--		GMS:Logs_SetMaxEntries(n) / :Logs_GetMaxEntries()
	--
	--	Levels:
	--		TRACE, DEBUG, INFO, WARN, ERROR
	-- ============================================================================

	local LibStub = LibStub
	if not LibStub then return end

	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end

	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end

	-- Prevent double-load
	if GMS.LOGS then return end

	local AceDB	= LibStub("AceDB-3.0", true)
	local AceGUI	= LibStub("AceGUI-3.0", true) -- optional, for UI page

	-- ###########################################################################
	-- #	STATE
	-- ###########################################################################

	local LOGS = {}
	GMS.LOGS = LOGS

	LOGS.LEVELS = {
		TRACE = 1,
		DEBUG = 2,
		INFO  = 3,
		WARN  = 4,
		ERROR = 5,
	}

	LOGS.LEVEL_NAMES = {
		[1] = "TRACE",
		[2] = "DEBUG",
		[3] = "INFO",
		[4] = "WARN",
		[5] = "ERROR",
	}

	LOGS.DEFAULTS = {
		profile = {
			minLevel = LOGS.LEVELS.INFO,
			chat = true,
			maxEntries = 400,
			timestamp = true,
		}
	}

	LOGS._db = nil
	LOGS._entries = {}
	LOGS._head = 0
	LOGS._count = 0

	-- ###########################################################################
	-- #	UTIL
	-- ###########################################################################

	local function clamp(n, lo, hi)
		if n < lo then return lo end
		if n > hi then return hi end
		return n
	end

	local function now()
		return type(date) == "function" and date("%H:%M:%S") or ""
	end

	local function toLevel(level)
		if type(level) == "number" then
			return clamp(level, 1, 5)
		end
		if type(level) == "string" then
			return LOGS.LEVELS[level:upper()] or LOGS.LEVELS.INFO
		end
		return LOGS.LEVELS.INFO
	end

	local function levelName(n)
		return LOGS.LEVEL_NAMES[n] or "INFO"
	end

	local function fmtSafe(fmt, ...)
		if select("#", ...) == 0 then
			return tostring(fmt)
		end
		local ok, out = pcall(string.format, tostring(fmt), ...)
		if ok then return out end
		local t = { tostring(fmt) }
		for i = 1, select("#", ...) do
			t[#t + 1] = tostring(select(i, ...))
		end
		return table.concat(t, " ")
	end

	local function profile()
		return LOGS._db and LOGS._db.profile or LOGS.DEFAULTS.profile
	end

	local function allow(levelNum)
		return levelNum >= (profile().minLevel or LOGS.LEVELS.INFO)
	end

	local function ringPush(entry)
		local max = clamp(profile().maxEntries or 400, 50, 5000)
		LOGS._head = (LOGS._head % max) + 1
		LOGS._entries[LOGS._head] = entry
		if LOGS._count < max then
			LOGS._count = LOGS._count + 1
		end
	end

	local function chatPrint(msg)
		if type(GMS.Printf) == "function" then
			GMS:Printf("%s", msg)
		elseif type(GMS.Print) == "function" then
			GMS:Print(msg)
		else
			print(msg)
		end
	end

	-- ###########################################################################
	-- #	INIT
	-- ###########################################################################

	function LOGS:Init()
		if AceDB then
			local ok, db = pcall(AceDB.New, AceDB, "GMS_LOGS_DB", LOGS.DEFAULTS, true)
			if ok and db then
				LOGS._db = db
			end
		end
	end

	-- ###########################################################################
	-- #	PUBLIC API (CONFIG)
	-- ###########################################################################

	function GMS:Logs_SetLevel(level)
		profile().minLevel = toLevel(level)
	end

	function GMS:Logs_GetLevel()
		return profile().minLevel
	end

	function GMS:Logs_EnableChat(v)
		profile().chat = not not v
	end

	function GMS:Logs_IsChatEnabled()
		return not not profile().chat
	end

	function GMS:Logs_SetMaxEntries(n)
		profile().maxEntries = clamp(tonumber(n) or 400, 50, 5000)
	end

	function GMS:Logs_GetMaxEntries()
		return profile().maxEntries
	end

	function GMS:Logs_Clear()
		wipe(LOGS._entries)
		LOGS._head = 0
		LOGS._count = 0
	end

	function GMS:Logs_GetEntries(n, minLevel)
		local want = tonumber(n) or LOGS._count
		if want < 1 then want = 1 end
		if want > LOGS._count then want = LOGS._count end

		local lvl = minLevel and toLevel(minLevel) or 1
		local out = {}

		local max = clamp(profile().maxEntries or 400, 50, 5000)
		for i = 0, LOGS._count - 1 do
			if #out >= want then break end
			local idx = LOGS._head - i
			if idx <= 0 then idx = idx + max end
			local e = LOGS._entries[idx]
			if e and (e.levelNum or 1) >= lvl then
				out[#out + 1] = e
			end
		end

		return out
	end

	-- ###########################################################################
	-- #	LOGGING
	-- ###########################################################################

	function GMS:Log(level, msg, ...)
		local lvl = toLevel(level)
		if not allow(lvl) then return end

		local p = profile()
		local text = fmtSafe(msg, ...)
		local ts = p.timestamp and now() or nil

		local entry = {
			levelNum = lvl,
			level = levelName(lvl),
			time = ts,
			msg = text,
		}

		ringPush(entry)

		if p.chat then
			if ts then
				chatPrint(string.format("[GMS][%s][%s] %s", entry.level, ts, text))
			else
				chatPrint(string.format("[GMS][%s] %s", entry.level, text))
			end
		end
	end

	function GMS:Logf(level, fmt, ...)
		return self:Log(level, fmt, ...)
	end

	function GMS:Trace(...) return self:Log(LOGS.LEVELS.TRACE, ...) end
	function GMS:Debug(...) return self:Log(LOGS.LEVELS.DEBUG, ...) end
	function GMS:Info(...)  return self:Log(LOGS.LEVELS.INFO,  ...) end
	function GMS:Warn(...)  return self:Log(LOGS.LEVELS.WARN,  ...) end
	function GMS:Error(...) return self:Log(LOGS.LEVELS.ERROR, ...) end

	-- ###########################################################################
	-- #	OPTIONAL: UI PAGE (AceGUI + GMS UI Registry)
	-- ###########################################################################

	local function UI_RegisterPage(name, buildFn, opts)
		if GMS.UI and type(GMS.UI.RegisterPage) == "function" then
			return GMS.UI:RegisterPage(name, buildFn, opts)
		end
		if type(GMS.UI_RegisterPage) == "function" then
			return GMS:UI_RegisterPage(name, buildFn, opts)
		end
	end

	local function UI_RegisterDockIcon(name, opts)
		if GMS.UI and type(GMS.UI.RegisterRightDockIcon) == "function" then
			return GMS.UI:RegisterRightDockIcon(name, opts)
		end
		if type(GMS.UI_RegisterRightDockIcon) == "function" then
			return GMS:UI_RegisterRightDockIcon(name, opts)
		end
	end

	local function UI_Open(name)
		if type(GMS.UI_Open) == "function" then
			return GMS:UI_Open(name)
		end
		if type(GMS.UI_OpenPage) == "function" then
			return GMS:UI_OpenPage(name)
		end
	end

	local function RegisterLogsUI()
		if not AceGUI then return end
		if not UI_RegisterPage then return end

		local PAGE_NAME = "LOGS"
		local DISPLAY_NAME = "Logs"

		local LEVEL_ORDER = { "TRACE", "DEBUG", "INFO", "WARN", "ERROR" }

		local function MkButton(text, onClick)
			local b = AceGUI:Create("Button")
			b:SetText(text)
			b:SetWidth(120)
			if onClick then
				b:SetCallback("OnClick", function() onClick() end)
			end
			return b
		end

		local function MkLabel(text)
			local l = AceGUI:Create("Label")
			l:SetText(text or "")
			l:SetFullWidth(true)
			return l
		end

		local function BuildCopyText(entries)
			local t = {}
			for i = 1, #entries do
				local e = entries[i]
				local lvl = e.level or levelName(e.levelNum or LOGS.LEVELS.INFO)
				local ts = e.time or ""
				local msg = e.msg or ""
				if ts ~= "" then
					t[#t + 1] = string.format("[%s][%s] %s", lvl, ts, msg)
				else
					t[#t + 1] = string.format("[%s] %s", lvl, msg)
				end
			end
			return table.concat(t, "\n")
		end

		local function BuildPage(root)
			root:SetLayout("List")

			local header = AceGUI:Create("InlineGroup")
			header:SetTitle("Logs")
			header:SetFullWidth(true)
			header:SetLayout("Flow")
			root:AddChild(header)

			local dd = AceGUI:Create("Dropdown")
			dd:SetLabel("Min Level")
			dd:SetWidth(180)
			do
				local list = {}
				for i = 1, #LEVEL_ORDER do
					local k = LEVEL_ORDER[i]
					list[k] = k
				end
				dd:SetList(list, LEVEL_ORDER)
				dd:SetValue(levelName(GMS:Logs_GetLevel() or LOGS.LEVELS.INFO))
			end
			header:AddChild(dd)

			local edtN = AceGUI:Create("EditBox")
			edtN:SetLabel("Show last N")
			edtN:SetWidth(140)
			edtN:SetText("200")
			header:AddChild(edtN)

			local chkChat = AceGUI:Create("CheckBox")
			chkChat:SetLabel("Chat output")
			chkChat:SetWidth(140)
			chkChat:SetValue(GMS:Logs_IsChatEnabled() and true or false)
			chkChat:SetCallback("OnValueChanged", function(_, _, val)
				GMS:Logs_EnableChat(val and true or false)
			end)
			header:AddChild(chkChat)

			local copyBox = AceGUI:Create("MultiLineEditBox")
			copyBox:SetLabel("Copy (select all + Ctrl+C)")
			copyBox:SetNumLines(6)
			copyBox:SetFullWidth(true)
			copyBox:DisableButton(true)
			root:AddChild(copyBox)

			local listGroup = AceGUI:Create("InlineGroup")
			listGroup:SetTitle("Entries")
			listGroup:SetFullWidth(true)
			listGroup:SetFullHeight(true)
			listGroup:SetLayout("Fill")
			root:AddChild(listGroup)

			local scroller = AceGUI:Create("ScrollFrame")
			scroller:SetLayout("List")
			listGroup:AddChild(scroller)

			local function DoRefresh()
				scroller:ReleaseChildren()

				local minLevel = toLevel(dd:GetValue() or "INFO")
				local n = tonumber(edtN:GetText() or "") or 200
				if n < 1 then n = 1 end
				if n > 2000 then n = 2000 end

				local entries = GMS:Logs_GetEntries(n, minLevel) or {}
				copyBox:SetText(BuildCopyText(entries))

				if #entries == 0 then
					scroller:AddChild(MkLabel("Keine Einträge (oder Filter zu hoch)."))
					return
				end

				for i = 1, #entries do
					local e = entries[i]
					local lvl = e.level or levelName(e.levelNum or LOGS.LEVELS.INFO)
					local ts = e.time or ""
					local msg = e.msg or ""
					local line = (ts ~= "")
						and string.format("[%s][%s] %s", lvl, ts, msg)
						or  string.format("[%s] %s", lvl, msg)
					scroller:AddChild(MkLabel(line))
				end
			end

			header:AddChild(MkButton("Refresh", DoRefresh))
			header:AddChild(MkButton("Clear", function()
				GMS:Logs_Clear()
				DoRefresh()
			end))

			header:AddChild(MkButton("Copy", function()
				copyBox.editBox:SetFocus()
				copyBox.editBox:HighlightText(0, copyBox.editBox:GetNumLetters() or 0)
			end))

			dd:SetCallback("OnValueChanged", function()
				local v = dd:GetValue()
				if v then GMS:Logs_SetLevel(v) end
				DoRefresh()
			end)

			edtN:SetCallback("OnEnterPressed", function()
				DoRefresh()
			end)

			DoRefresh()
		end

		UI_RegisterPage(PAGE_NAME, BuildPage, { title = DISPLAY_NAME })
		UI_RegisterDockIcon(PAGE_NAME, { title = DISPLAY_NAME })
	end

	-- ###########################################################################
	-- #	OPTIONAL: SLASHCOMMAND (/gms logs ...)
	-- ###########################################################################

	local function RegisterSlash()
		if not GMS.SlashCommands or type(GMS.SlashCommands.RegisterSubCommand) ~= "function" then
			return
		end

		GMS.SlashCommands:RegisterSubCommand("logs", {
			title = "Logs",
			help = "logs ui | show [N] [LEVEL] | level LEVEL | chat on/off | max N | clear",
			handler = function(args)
				args = tostring(args or "")
				local a, rest = args:match("^(%S+)%s*(.*)$")
				a = (a and a:lower()) or ""
				rest = tostring(rest or "")

				if a == "" or a == "ui" then
					UI_Open("LOGS")
					return
				end

				if a == "clear" then
					GMS:Logs_Clear()
					GMS:Info("Logs geleert.")
					return
				end

				if a == "chat" then
					local v = rest:lower()
					if v == "on" then
						GMS:Logs_EnableChat(true)
						GMS:Info("Chat output: on")
					elseif v == "off" then
						GMS:Logs_EnableChat(false)
						GMS:Info("Chat output: off")
					else
						GMS:Info("Chat output ist %s", GMS:Logs_IsChatEnabled() and "on" or "off")
					end
					return
				end

				if a == "max" then
					local n = tonumber(rest)
					if n then GMS:Logs_SetMaxEntries(n) end
					GMS:Info("MaxEntries = %d", GMS:Logs_GetMaxEntries())
					return
				end

				if a == "level" then
					local lvl = rest:match("^(%S+)")
					if lvl then GMS:Logs_SetLevel(lvl) end
					GMS:Info("minLevel = %s", levelName(GMS:Logs_GetLevel() or LOGS.LEVELS.INFO))
					return
				end

				if a == "show" then
					local nStr, lvlStr = rest:match("^(%d+)%s*(%S*)")
					local n = tonumber(nStr) or 10
					local lvl = (lvlStr and lvlStr ~= "") and lvlStr or 1
					local entries = GMS:Logs_GetEntries(n, lvl) or {}

					GMS:Info("Letzte %d Log-Einträge:", #entries)
					for i = 1, #entries do
						local e = entries[i]
						local l = e.level or levelName(e.levelNum or LOGS.LEVELS.INFO)
						local ts = e.time or ""
						local msg = e.msg or ""
						if ts ~= "" then
							chatPrint(string.format("  [%s][%s] %s", l, ts, msg))
						else
							chatPrint(string.format("  [%s] %s", l, msg))
						end
					end
					return
				end

				-- fallback: /gms logs debug
				local shortcut = LOGS.LEVELS[a:upper()]
				if shortcut then
					GMS:Logs_SetLevel(shortcut)
					GMS:Info("minLevel = %s", levelName(GMS:Logs_GetLevel() or shortcut))
					return
				end

				GMS:Info("Usage: /gms logs ui | show [N] [LEVEL] | level LEVEL | chat on/off | max N | clear")
			end
		})
	end

	-- ###########################################################################
	-- #	BOOT
	-- ###########################################################################

	LOGS:Init()
	RegisterLogsUI()
	RegisterSlash()

	GMS:Debug("LOGS Extension geladen")
