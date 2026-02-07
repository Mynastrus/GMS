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

	local LibStub = _G.LibStub
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

		-- ============================================================================
		-- GMS/Core/Logs.lua
		-- Unified logging: single `GMS:LOG(level, module, fmt, ...)` entrypoint
		-- - ringbuffer (append newest to end), level filter, optional chat output
		-- - AceGUI UI page + right-dock icon with live view (newest on top)
		-- - Uses optional AceDB profile at `GMS.logging_db` or creates its own DB
		-- ============================================================================

		local LibStub = _G.LibStub
		if not LibStub then return end

		local AceAddon = LibStub("AceAddon-3.0", true)
		if not AceAddon then return end

		local GMS = AceAddon:GetAddon("GMS", true)
		if not GMS then return end

		-- Prevent double-load
		if GMS.LOGS then return end

		local AceDB = LibStub("AceDB-3.0", true)
		local AceGUI = LibStub("AceGUI-3.0", true) -- optional

		local LOGS = {}
		GMS.LOGS = LOGS

		LOGS.LEVELS = { TRACE = 1, DEBUG = 2, INFO = 3, WARN = 4, ERROR = 5 }
		LOGS.LEVEL_NAMES = { [1] = "TRACE", [2] = "DEBUG", [3] = "INFO", [4] = "WARN", [5] = "ERROR" }

		LOGS.DEFAULTS = {
			profile = { minLevel = LOGS.LEVELS.INFO, chat = true, maxEntries = 400, timestamp = true }
		}

		LOGS._db = nil
		LOGS._entries = {} -- append new entries with table.insert

		local COLORS = {
			TRACE = "|cff9d9d9d", -- gray
			DEBUG = "|cff4da6ff", -- light blue
			INFO  = "|cff4dff88", -- green
			WARN  = "|cffffd24d", -- yellow
			ERROR = "|cffff4d4d", -- red
		}

		local function clamp(n, lo, hi)
			if n < lo then return lo end
			if n > hi then return hi end
			return n
		end

		local function now()
			return type(date) == "function" and date("%H:%M:%S") or ""
		end

		local function toLevel(level)
			if type(level) == "number" then return clamp(level, 1, 5) end
			if type(level) == "string" then return LOGS.LEVELS[level:upper()] or LOGS.LEVELS.INFO end
			return LOGS.LEVELS.INFO
		end

		local function levelName(n) return LOGS.LEVEL_NAMES[n] or "INFO" end

		local function fmtSafe(fmt, ...)
			if select("#", ...) == 0 then return tostring(fmt) end
			local ok, out = pcall(string.format, tostring(fmt), ...)
			if ok then return out end
			local t = { tostring(fmt) }
			for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
			return table.concat(t, " ")
		end

		local function profile()
			return LOGS._db and LOGS._db.profile or LOGS.DEFAULTS.profile
		end

		local function allow(levelNum)
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

		function LOGS:Init()
			-- prefer shared logging DB
			if GMS and GMS.logging_db then
				LOGS._db = GMS.logging_db
				return
			end
			-- prefer module DB via GMS.DB
			if GMS and GMS.DB and type(GMS.DB.GetModuleDB) == "function" then
				local ok, ns = pcall(function() return GMS.DB:GetModuleDB("LOGS") end)
				if ok and ns then LOGS._db = ns; return end
			end
			-- fallback: create own DB
			if AceDB then
				local ok, db = pcall(AceDB.New, AceDB, "GMS_Logging_DB", LOGS.DEFAULTS, true)
				if ok and db then LOGS._db = db end
			end
		end

		-- PUBLIC CONFIG
		function GMS:Logs_SetLevel(level) profile().minLevel = toLevel(level) end
		function GMS:Logs_GetLevel() return profile().minLevel end
		function GMS:Logs_EnableChat(v) profile().chat = not not v end
		function GMS:Logs_IsChatEnabled() return not not profile().chat end
		function GMS:Logs_SetMaxEntries(n) profile().maxEntries = clamp(tonumber(n) or 400, 50, 5000) end
		function GMS:Logs_GetMaxEntries() return profile().maxEntries end
		function GMS:Logs_Clear() LOGS._entries = {} end
		function GMS:Logs_GetEntries(n, minLevel)
			local want = tonumber(n) or #LOGS._entries
			if want < 1 then want = 1 end
			if want > #LOGS._entries then want = #LOGS._entries end
			local lvl = minLevel and toLevel(minLevel) or 1
			local out = {}
			for i = #LOGS._entries, 1, -1 do -- newest-first
				if #out >= want then break end
				local e = LOGS._entries[i]
				if e and (e.levelNum or 1) >= lvl then out[#out + 1] = e end
			end
			return out
		end

		-- Core logging entrypoint required by the user: GMS:LOG(level, module, fmt, ...)
		function GMS:LOG(level, module, fmt, ...)
			local lvl = toLevel(level)
			if not allow(lvl) then return end
			local mod = nil
			local msgFmt = nil
			local extra = {}
			-- support calls that omit module: GMS:LOG(level, fmt, ...)
			if type(module) == "string" and fmt ~= nil then
				mod = module
				msgFmt = fmt
				for i = 1, select('#', ...) do extra[#extra+1] = select(i, ...) end
			elseif type(module) == "string" and fmt == nil then
				-- called as GMS:LOG(level, msg, ...)
				msgFmt = module
				mod = nil
				for i = 1, select('#', ...) do extra[#extra+1] = select(i, ...) end
			else
				-- fallback: everything after level is message
				msgFmt = tostring(module or fmt or "")
				for i = 1, select('#', ...) do extra[#extra+1] = select(i, ...) end
			end
			local text = fmtSafe(msgFmt, unpack(extra))
			local ts = profile().timestamp and now() or nil
			local entry = { levelNum = lvl, level = levelName(lvl), time = ts, module = tostring(mod or ""), msg = text }

			-- append and trim
			local max = clamp(profile().maxEntries or 400, 50, 5000)
			table.insert(LOGS._entries, entry)
			while #LOGS._entries > max do table.remove(LOGS._entries, 1) end

			-- chat output
			if profile().chat then
				if ts then
					chatPrint(string.format("[GMS][%s][%s] %s", entry.level, ts, text))
				else
					chatPrint(string.format("[GMS][%s] %s", entry.level, text))
				end
			end

			-- notify UI if present
			if LOGS._onAdd and type(LOGS._onAdd) == "function" then
				pcall(LOGS._onAdd, entry)
			end
		end

		-- Provide thin compatibility wrappers
		function GMS:LOGf(level, fmt, ...) return self:LOG(level, fmt, ...) end


		-- UI helpers (optional)
		local function UI_RegisterPage(name, buildFn, opts)
			if GMS.UI and type(GMS.UI.RegisterPage) == "function" then return GMS.UI:RegisterPage(name, buildFn, opts) end
			if type(GMS.UI_RegisterPage) == "function" then return GMS:UI_RegisterPage(name, buildFn, opts) end
		end

		local function UI_RegisterDockIcon(name, opts)
			if GMS.UI and type(GMS.UI.RegisterRightDockIcon) == "function" then return GMS.UI:RegisterRightDockIcon(name, opts) end
			if type(GMS.UI_RegisterRightDockIcon) == "function" then return GMS:UI_RegisterRightDockIcon(name, opts) end
		end

		local function UI_Open(name)
			if type(GMS.UI_Open) == "function" then return GMS:UI_Open(name) end
			if type(GMS.UI_OpenPage) == "function" then return GMS:UI_OpenPage(name) end
		end

		local function RegisterLogsUI()
			if not AceGUI then return end
			if not UI_RegisterPage then return end

			local PAGE_NAME = "LOGS"
			local DISPLAY_NAME = "Logs"

			local function MkButton(text, onClick)
				local b = AceGUI:Create("Button")
				b:SetText(text)
				b:SetWidth(120)
				if onClick then b:SetCallback("OnClick", function() onClick() end) end
				return b
			end

			local function BuildLogWidget(entry)
				local grp = AceGUI:Create("SimpleGroup")
				grp:SetFullWidth(true)
				grp:SetLayout("Flow")

				local color = COLORS[entry.level] or "|cffffffff"
				local title = string.format("%s[%s]%s %s", color, entry.level, "|r", entry.module ~= "" and ("("..entry.module..")") or "")
				local ts = entry.time or ""
				local msg = entry.msg or ""

				local hdr = AceGUI:Create("Label")
				hdr:SetText(title .. (ts ~= "" and (" ["..ts.."]") or ""))
				hdr:SetFullWidth(true)
				grp:AddChild(hdr)

				local body = AceGUI:Create("Label")
				body:SetText(color .. msg .. "|r")
				body:SetFullWidth(true)
				grp:AddChild(body)

				return grp
			end

			local function BuildPage(root)
				root:SetLayout("List")

				local header = AceGUI:Create("InlineGroup")
				header:SetTitle("Logs")
				header:SetFullWidth(true)
				header:SetLayout("Flow")
				root:AddChild(header)

				local btnRefresh = MkButton("Refresh", function() end)
				header:AddChild(btnRefresh)

				local btnClear = MkButton("Clear", function()
					GMS:Logs_Clear()
					if scroller then scroller:ReleaseChildren() end
				end)
				header:AddChild(btnClear)

				local listGroup = AceGUI:Create("InlineGroup")
				listGroup:SetTitle("Entries")
				listGroup:SetFullWidth(true)
				listGroup:SetFullHeight(true)
				listGroup:SetLayout("Fill")
				root:AddChild(listGroup)

				local scroller = AceGUI:Create("ScrollFrame")
				scroller:SetLayout("List")
				listGroup:AddChild(scroller)

				local function Render()
					scroller:ReleaseChildren()
					-- newest first
					for i = #LOGS._entries, 1, -1 do
						local e = LOGS._entries[i]
						local w = BuildLogWidget(e)
						scroller:AddChild(w)
					end
				end

				-- live update hook
				LOGS._onAdd = function(entry)
					-- rebuild view with newest on top
					pcall(Render)
				end

				btnRefresh:SetCallback("OnClick", function() Render() end)

				Render()
			end

			UI_RegisterPage(PAGE_NAME, BuildPage, { title = DISPLAY_NAME })
			UI_RegisterDockIcon(PAGE_NAME, { title = DISPLAY_NAME })
		end

		-- BOOT
		LOGS:Init()
		pcall(RegisterLogsUI)

		-- expose short alias
		GMS.LOGS = LOGS

		-- Notify loaded
		if GMS and type(GMS.Print) == "function" then pcall(function() GMS:Print("Logs wurde geladen") end) end
