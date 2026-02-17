-- ============================================================================
--	GMS/Locales/Locale.lua
--	Global localization registry + lookup
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

---@diagnostic disable: undefined-global
local GetLocale = GetLocale
---@diagnostic enable: undefined-global

GMS.LOCALE = GMS.LOCALE or {}
GMS.LOCALE.data = GMS.LOCALE.data or {}

function GMS:RegisterLocale(localeCode, strings)
	local code = tostring(localeCode or "")
	if code == "" or type(strings) ~= "table" then
		return false
	end
	self.LOCALE.data[code] = strings
	return true
end

function GMS:GetLanguage()
	local mode = tostring((type(self.db) == "table" and type(self.db.profile) == "table" and self.db.profile.addonLanguageMode) or "AUTO")
	local data = self.LOCALE and self.LOCALE.data or nil
	if mode ~= "" and string.upper(mode) ~= "AUTO" and type(data) == "table" then
		if type(data[mode]) == "table" then
			return mode
		end
		local modeLower = string.lower(mode)
		for code, strings in pairs(data) do
			if type(strings) == "table" and string.lower(tostring(code)) == modeLower then
				return tostring(code)
			end
		end
	end

	local locale = tostring((type(GetLocale) == "function" and GetLocale()) or "")
	if locale == "" then
		return "enUS"
	end
	return locale
end

function GMS:SetLanguageMode(mode)
	local nextMode = tostring(mode or "AUTO")
	if nextMode == "" then nextMode = "AUTO" end

	local data = self.LOCALE and self.LOCALE.data or nil
	if string.upper(nextMode) == "AUTO" then
		nextMode = "AUTO"
	else
		if type(data) ~= "table" then
			return false
		end
		if type(data[nextMode]) ~= "table" then
			local wanted = string.lower(nextMode)
			local resolved = nil
			for code, strings in pairs(data) do
				if type(strings) == "table" and string.lower(tostring(code)) == wanted then
					resolved = tostring(code)
					break
				end
			end
			if not resolved then
				return false
			end
			nextMode = resolved
		end
	end

	if type(self.db) == "table" and type(self.db.profile) == "table" then
		self.db.profile.addonLanguageMode = nextMode
	end

	if type(self.SendMessage) == "function" then
		self:SendMessage("GMS_LOCALE_CHANGED", self:GetLanguage())
	end

	return true
end

function GMS:L(key)
	local k = tostring(key or "")
	if k == "" then return "" end

	local lang = self:GetLanguage()
	local byLang = self.LOCALE and self.LOCALE.data and self.LOCALE.data[lang]
	if type(byLang) == "table" and byLang[k] ~= nil then
		return byLang[k]
	end

	local en = self.LOCALE and self.LOCALE.data and self.LOCALE.data["enUS"]
	if type(en) == "table" and en[k] ~= nil then
		return en[k]
	end

	return k
end

function GMS:T(key, ...)
	local fmt = self:L(key)
	if select("#", ...) == 0 then
		return fmt
	end
	local ok, text = pcall(string.format, tostring(fmt), ...)
	return ok and text or tostring(fmt)
end
