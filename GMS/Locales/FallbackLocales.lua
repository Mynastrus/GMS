-- ============================================================================
--	GMS/Locales/FallbackLocales.lua
--	Registers common WoW locales with preferred fallback chains
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

if type(GMS.RegisterLocale) ~= "function" then return end

local enUS = GMS.LOCALE and GMS.LOCALE.data and GMS.LOCALE.data["enUS"]
if type(enUS) ~= "table" then return end

local function clone(src)
	local out = {}
	for k, v in pairs(src) do
		out[k] = v
	end
	return out
end

local fallbackByLocale = {
	enGB = "enUS",
	frFR = "enUS",
	esES = "enUS",
	esMX = "esES",
	itIT = "enUS",
	ptBR = "enUS",
	ruRU = "enUS",
	koKR = "enUS",
	zhCN = "enUS",
	zhTW = "enUS",
}

for code, sourceCode in pairs(fallbackByLocale) do
	if not (GMS.LOCALE and GMS.LOCALE.data and GMS.LOCALE.data[code]) then
		local source = GMS.LOCALE and GMS.LOCALE.data and GMS.LOCALE.data[sourceCode]
		if type(source) ~= "table" then
			source = enUS
		end
		GMS:RegisterLocale(code, clone(source))
	end
end
