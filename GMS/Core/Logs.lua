	-- ============================================================================
	--	GMS/Core/Logs.lua
	--	LOGS EXTENSION (no GMS:NewModule)
	--	- Ringbuffer (persistiert via AceDB)
	--	- GMS:LOG(level, module, msg, ...)
	--	- Speichert IMMER Timestamp, Level, Module, Message (+ optionale Data lesbar/JSON-ish)
	--	- UI Page (AceGUI) + Live-Prepend wenn offen
	--	- Slash: /gms logs -> öffnet LOGS Page
	-- ============================================================================

	local LibStub = LibStub
	if not LibStub then return end

	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end

	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end

	-- Prevent double-load
	if GMS.LOGS then return end

	local AceDB = LibStub("AceDB-3.0", true)
	local AceGUI = LibStub("AceGUI-3.0", true) -- optional (UI page)

	local LOGS = {}
	GMS.LOGS = LOGS

	-- ###########################################################################
	-- #	CONSTS / DEFAULTS
	-- ###########################################################################

	LOGS.LEVELS = { TRACE = 1, DEBUG = 2, INFO = 3, WARN = 4, ERROR = 5 }
	LOGS.LEVEL_NAMES = { [1] = "TRACE", [2] = "DEBUG", [3] = "INFO", [4] = "WARN", [5] = "ERROR" }

	local COLORS = {
		TRACE = "|cff9d9d9d",
		DEBUG = "|cff4da6ff",
		INFO  = "|cff4dff88",
		WARN  = "|cffffd24d",
		ERROR = "|cffff4d4d",
	}

	LOGS.DEFAULTS = {
		profile = {
			minLevel = LOGS.LEVELS.INFO,	-- Output/UI Filter (Speicher bleibt ALL)
			chat = false,					-- optional Chat output
			maxEntries = 400,				-- Ringbuffer Größe
			timestampFormat = "%Y-%m-%d %H:%M:%S",
			entries = {},					-- persistierter Ringbuffer
		}
	}

	LOGS._db = nil
	LOGS._entries = nil -- points to profile.entries
	LOGS._ui = nil

	LOGS._uiRegistered = false
	LOGS._slashRegistered = false

	-- ###########################################################################
	-- #	HELPERS
	-- ###########################################################################

	local function clamp(n, lo, hi)
		if n < lo then return lo end
		if n > hi then return hi end
		return n
	end

	local function toLevel(level)
		if type(level) == "number" then return clamp(level, 1, 5) end
		if type(level) == "string" then return LOGS.LEVELS[level:upper()] or LOGS.LEVELS.INFO end
		return LOGS.LEVELS.INFO
	end

	local function levelName(n)
		return LOGS.LEVEL_NAMES[n] or "INFO"
	end

	local function now(fmt)
		if type(date) == "function" then
			return date(fmt or "%Y-%m-%d %H:%M:%S")
		end
		return ""
	end

	local function profile()
		return LOGS._db and LOGS._db.profile or LOGS.DEFAULTS.profile
	end

	local function allowForOutput(levelNum)
		return levelNum >= (profile().minLevel or LOGS.LEVELS.INFO)
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

	-- JSON-ish / readable stringify (safe, bounded)
	local function _escapeStr(s)
		s = tostring(s)
		s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
		return "\"" .. s .. "\""
	end

	local function _isArray(t)
		local n = 0
		for k in pairs(t) do
			if type(k) ~= "number" then return false end
			n = n + 1
		end
		for i = 1, n do
			if rawget(t, i) == nil then return false end
		end
		return true
	end

	local function _jsonish(v, seen, depth, maxDepth, maxItems)
		local tv = type(v)
		if tv == "nil" then return "null" end
		if tv == "number" then return tostring(v) end
		if tv == "boolean" then return v and "true" or "false" end
		if tv == "string" then return _escapeStr(v) end
		if tv == "function" then return "\"<function>\"" end
		if tv == "userdata" then return "\"<userdata>\"" end
		if tv == "thread" then return "\"<thread>\"" end
		if tv ~= "table" then return _escapeStr(tostring(v)) end

		if seen[v] then return "\"<cycle>\"" end
		seen[v] = true

		if depth >= maxDepth then
			seen[v] = nil
			return "\"<maxDepth>\""
		end

		local out = {}
		local count = 0

		if _isArray(v) then
			out[#out + 1] = "["
			for i = 1, #v do
				count = count + 1
				if count > maxItems then
					out[#out + 1] = "\"<truncated>\""
					break
				end
				if i > 1 then out[#out + 1] = "," end
				out[#out + 1] = _jsonish(v[i], seen, depth + 1, maxDepth, maxItems)
			end
			out[#out + 1] = "]"
		else
			out[#out + 1] = "{"
			local first = true
			for k, val in pairs(v) do
				count = count + 1
				if count > maxItems then
					if not first then out[#out + 1] = "," end
					out[#out + 1] = _escapeStr("<truncated>") .. ":" .. _escapeStr("true")
					break
				end
				if not first then out[#out + 1] = "," end
				first = false
				local kk = _escapeStr(type(k) == "string" and k or tostring(k))
				out[#out + 1] = kk .. ":" .. _jsonish(val, seen, depth + 1, maxDepth, maxItems)
			end
			out[#out + 1] = "}"
		end

		seen[v] = nil
		return table.concat(out, "")
	end

	local function dataSuffix(...)
		local n = select("#", ...)
		if n <= 0 then return "" end

		local parts = {}
		for i = 1, n do
			local v = select(i, ...)
			if type(v) == "table" then
				parts[#parts + 1] = _jsonish(v, {}, 0, 4, 80)
			else
				parts[#parts + 1] = tostring(v)
			end
		end

		return " | data=" .. table.concat(parts, " ")
	end

	local function trimToMax()
		local p = profile()
		local max = clamp(tonumber(p.maxEntries) or 400, 50, 5000)
		p.maxEntries = max -- persist clamp result
		local entries = LOGS._entries
		if not entries then return end
		while #entries > max do
			table.remove(entries, 1)
		end
	end

	-- ###########################################################################
	-- #	UI BRIDGE (robust)
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
		if type(GMS.UI_Open) == "function" then return GMS:UI_Open(name) end
		if type(GMS.UI_OpenPage) == "function" then return GMS:UI_OpenPage(name) end
		if GMS.UI and type(GMS.UI.Open) == "function" then return GMS.UI:Open(name) end
	end

	-- ###########################################################################
	-- #	INIT / DB
	-- ###########################################################################

	function LOGS:Init()
		if AceDB then
			local ok, db = pcall(AceDB.New, AceDB, "GMS_Logs_DB", LOGS.DEFAULTS, true)
			if ok and db then
				LOGS._db = db
				LOGS._entries = db.profile.entries or {}
				db.profile.entries = LOGS._entries
				trimToMax()
				return
			end
		end
		-- fallback: in-memory only
		LOGS._db = nil
		LOGS._entries = {}
	end

	-- PUBLIC CONFIG (persisted)
	function GMS:Logs_SetLevel(level) profile().minLevel = toLevel(level) end
	function GMS:Logs_GetLevel() return profile().minLevel end
	function GMS:Logs_EnableChat(v) profile().chat = not not v end
	function GMS:Logs_IsChatEnabled() return not not profile().chat end
	function GMS:Logs_SetMaxEntries(n) profile().maxEntries = clamp(tonumber(n) or 400, 50, 5000); trimToMax() end
	function GMS:Logs_GetMaxEntries() return profile().maxEntries end
	function GMS:Logs_Clear()
		local p = profile()
		p.entries = {}
		LOGS._entries = p.entries
		if LOGS._ui and LOGS._ui.scroller then
			pcall(function() LOGS._ui.scroller:ReleaseChildren() end)
		end
	end

	function GMS:Logs_GetEntries(n, minLevel)
		local entries = LOGS._entries or {}
		local want = tonumber(n) or #entries
		if want < 1 then want = 1 end
		if want > #entries then want = #entries end
		local lvl = minLevel and toLevel(minLevel) or 1
		local out = {}
		for i = #entries, 1, -1 do
			if #out >= want then break end
			local e = entries[i]
			if e and (e.levelNum or 1) >= lvl then out[#out + 1] = e end
		end
		return out
	end

	-- ###########################################################################
	-- #	CORE: GMS:LOG(level, module, msg, ...)
	-- ###########################################################################

	function GMS:LOG(level, module, msg, ...)
		local lvl = toLevel(level)
		local mod = tostring(module or "")
		local base = tostring(msg or "")
		local text = base .. dataSuffix(...)

		local p = profile()
		local ts = now(p.timestampFormat or "%Y-%m-%d %H:%M:%S")

		local entry = {
			time = ts,
			levelNum = lvl,
			level = levelName(lvl),
			module = mod,
			msg = text,
		}

		local entries = LOGS._entries
		if not entries then
			LOGS._entries = {}
			entries = LOGS._entries
			if LOGS._db then LOGS._db.profile.entries = entries end
		end

		entries[#entries + 1] = entry
		trimToMax()

		-- chat output (filtered)
		if p.chat and allowForOutput(lvl) then
			local color = COLORS[entry.level] or "|cffffffff"
			local m = (entry.module ~= "" and ("[" .. entry.module .. "]") or "")
			chatPrint(string.format("%s[GMS][%s][%s]%s %s|r", color, entry.level, entry.time, m, entry.msg))
		end

		-- live UI prepend if open
		if LOGS._ui and LOGS._ui.prependEntry and allowForOutput(lvl) then
			pcall(LOGS._ui.prependEntry, entry)
		end
	end

	-- ###########################################################################
	-- #	UI PAGE
	-- ###########################################################################

	local function BuildLogRow(entry)
		local grp = AceGUI:Create("SimpleGroup")
		grp:SetFullWidth(true)
		grp:SetLayout("List")

		local color = COLORS[entry.level] or "|cffffffff"
		local mod = entry.module ~= "" and (" [" .. entry.module .. "]") or ""
		local header = string.format("%s[%s]%s %s%s", color, entry.level, "|r", entry.time or "", mod)

		local hdr = AceGUI:Create("Label")
		hdr:SetText(header)
		hdr:SetFullWidth(true)
		grp:AddChild(hdr)

		local body = AceGUI:Create("Label")
		body:SetText(color .. (entry.msg or "") .. "|r")
		body:SetFullWidth(true)
		grp:AddChild(body)

		return grp
	end

	local function RegisterLogsUI()
		if LOGS._uiRegistered then return true end
		if not AceGUI then return false end
		if type(UI_RegisterPage) ~= "function" then return false end

		-- UI system not ready yet?
		local canPage = false
		if (GMS.UI and type(GMS.UI.RegisterPage) == "function") or (type(GMS.UI_RegisterPage) == "function") then
			canPage = true
		end
		if not canPage then return false end

		local PAGE_NAME = "LOGS"
		local DISPLAY_NAME = "Logs"

		local function BuildPage(root)
			root:SetLayout("List")

			local header = AceGUI:Create("InlineGroup")
			header:SetTitle("Logs")
			header:SetFullWidth(true)
			header:SetLayout("Flow")
			root:AddChild(header)

			local scroller -- forward decl

			local btnRefresh = AceGUI:Create("Button")
			btnRefresh:SetText("Refresh")
			btnRefresh:SetWidth(120)
			header:AddChild(btnRefresh)

			local btnClear = AceGUI:Create("Button")
			btnClear:SetText("Clear")
			btnClear:SetWidth(120)
			header:AddChild(btnClear)

			local btnCopy = AceGUI:Create("Button")
			btnCopy:SetText("Copy")
			btnCopy:SetWidth(120)
			header:AddChild(btnCopy)

			local listGroup = AceGUI:Create("InlineGroup")
			listGroup:SetTitle("Entries (newest first)")
			listGroup:SetFullWidth(true)
			listGroup:SetFullHeight(true)
			listGroup:SetLayout("Fill")
			root:AddChild(listGroup)

			scroller = AceGUI:Create("ScrollFrame")
			scroller:SetLayout("List")
			listGroup:AddChild(scroller)

			local function RenderAll()
				scroller:ReleaseChildren()
				local entries = LOGS._entries or {}
				local minLvl = profile().minLevel or LOGS.LEVELS.INFO
				for i = #entries, 1, -1 do
					local e = entries[i]
					if e and (e.levelNum or 1) >= minLvl then
						scroller:AddChild(BuildLogRow(e))
					end
				end
			end

			local function PrependEntry(entry)
				if not scroller or not scroller.children then
					RenderAll()
					return
				end
				-- prepend widget
				local w = BuildLogRow(entry)
				table.insert(scroller.children, 1, w)
				w.frame:SetParent(scroller.content)
				scroller:DoLayout()
			end

			LOGS._ui = {
				scroller = scroller,
				renderAll = RenderAll,
				prependEntry = PrependEntry,
			}

			btnRefresh:SetCallback("OnClick", function() RenderAll() end)
			btnClear:SetCallback("OnClick", function() GMS:Logs_Clear(); RenderAll() end)

			btnCopy:SetCallback("OnClick", function()
				local entries = GMS:Logs_GetEntries(2000, profile().minLevel or 1)
				local lines = {}
				for i = 1, #entries do
					local e = entries[i]
					local mod = e.module ~= "" and (" [" .. e.module .. "]") or ""
					lines[#lines + 1] = string.format("[%s][%s]%s %s", e.level, e.time or "", mod, e.msg or "")
				end
				local text = table.concat(lines, "\n")
				if type(ChatFrame_OpenChat) == "function" then
					ChatFrame_OpenChat(text)
				else
					chatPrint(text)
				end
			end)

			RenderAll()
		end

		UI_RegisterPage("LOGS", BuildPage, { title = DISPLAY_NAME })
		if type(UI_RegisterDockIcon) == "function" then
			pcall(UI_RegisterDockIcon, "LOGS", { title = DISPLAY_NAME })
		end

		LOGS._uiRegistered = true
		return true
	end

	-- ###########################################################################
	-- #	SLASH: /gms logs
	-- ###########################################################################

	local function RegisterLogsSlash()
		if LOGS._slashRegistered then return true end

		local SC = GMS.SlashCommands
		if type(SC) ~= "table" then return false end

		-- 1) preferred API styles (if your SlashCommands extension provides them)
		if type(SC.RegisterSubCommand) == "function" then
			SC:RegisterSubCommand("logs", {
				title = "Logs",
				help = "/gms logs - öffnet die Logs UI",
				handler = function() UI_Open("LOGS") end,
			})
			LOGS._slashRegistered = true
			return true
		end

		if type(SC.Register) == "function" then
			SC:Register("logs", function() UI_Open("LOGS") end, "Öffnet die Logs UI")
			LOGS._slashRegistered = true
			return true
		end

		-- 2) fallback: SUB table pattern (passt zu deinem bisherigen Stil)
		SC.SUB = SC.SUB or {}
		SC.SUB.logs = SC.SUB.logs or {}
		SC.SUB.logs.title = SC.SUB.logs.title or "Logs"
		SC.SUB.logs.desc = SC.SUB.logs.desc or "Öffnet die Logs UI"
		SC.SUB.logs.run = function()
			UI_Open("LOGS")
		end

		LOGS._slashRegistered = true
		return true
	end

	-- ###########################################################################
	-- #	DEFERRED BOOT (UI/SlashCommands können später laden)
	-- ###########################################################################

	function LOGS:TryWire()
		local okUI = RegisterLogsUI()
		local okSlash = RegisterLogsSlash()

		-- keep trying until both are wired
		if okUI and okSlash then return end

		if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
			C_Timer.After(0.5, function()
				if GMS and GMS.LOGS and GMS.LOGS.TryWire then
					pcall(GMS.LOGS.TryWire, GMS.LOGS)
				end
			end)
		end
	end

	-- ###########################################################################
	-- #	BOOT
	-- ###########################################################################

	LOGS:Init()
	LOGS:TryWire()

	if type(GMS.Print) == "function" then
		pcall(function() GMS:Print("Logs.lua geladen") end)
	end
