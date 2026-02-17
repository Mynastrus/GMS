-- ============================================================================
--	GMS/Core/RaidIds.lua
--	Central raid ID mapping helper
-- ============================================================================

local LibStub = LibStub
if not LibStub then return end

local AceAddon = LibStub("AceAddon-3.0", true)
if not AceAddon then return end

local GMS = AceAddon:GetAddon("GMS", true)
if not GMS then return end

local METADATA = {
	TYPE         = "EXT",
	INTERN_NAME  = "RAIDIDS",
	SHORT_NAME   = "RaidIds",
	DISPLAY_NAME = "Raid IDs",
	VERSION      = "1.0.0",
}

-- Blizzard Globals
---@diagnostic disable: undefined-global
local _G = _G
---@diagnostic enable: undefined-global

GMS._LOG_BUFFER = GMS._LOG_BUFFER or {}

local function LOCAL_LOG(level, msg, ...)
	local entry = {
		level = tostring(level or "INFO"),
		type = METADATA.TYPE,
		source = METADATA.SHORT_NAME,
		msg = tostring(msg or ""),
	}
	local n = select("#", ...)
	if n > 0 then
		entry.data = { ... }
	end
	local idx = #GMS._LOG_BUFFER + 1
	GMS._LOG_BUFFER[idx] = entry
	if GMS._LOG_NOTIFY then
		GMS._LOG_NOTIFY(entry, idx)
	end
end

local RAID_IDS = _G.GMS_RAIDIDS or {}
_G.GMS_RAIDIDS = RAID_IDS

RAID_IDS.VERSION = METADATA.VERSION

-- JournalInstanceID -> MapID
RAID_IDS.JOURNAL_TO_MAP = RAID_IDS.JOURNAL_TO_MAP or {
	[1273] = 2657, -- Palast der Nerub'ar
	[1296] = 2769, -- Befreiung von Lorenhall
	[1302] = 2810, -- Manaschmiede Omega
}

RAID_IDS.MAP_TO_JOURNAL = RAID_IDS.MAP_TO_JOURNAL or {}
for journalID, mapID in pairs(RAID_IDS.JOURNAL_TO_MAP) do
	RAID_IDS.MAP_TO_JOURNAL[mapID] = journalID
end

-- per boss row: { LFR, N, H, M }
RAID_IDS.MAP_TO_BOSS_STATS = RAID_IDS.MAP_TO_BOSS_STATS or {
	[2657] = {
		aliases = {
			"palastvonnerubar",
			"palaceofnerubar",
		},
		bosses = {
			{ 40267, 40268, 40269, 40270 },
			{ 40271, 40272, 40273, 40274 },
			{ 40275, 40276, 40277, 40278 },
			{ 40279, 40280, 40281, 40282 },
			{ 40283, 40284, 40285, 40286 },
			{ 40287, 40288, 40289, 40290 },
			{ 40291, 40292, 40293, 40294 },
			{ 40295, 40296, 40297, 40298 },
		},
	},
	[2769] = {
		aliases = {
			"befreiungvonlorenhall",
			"liberationofundermine",
		},
		bosses = {
			{ 41299, 41300, 41301, 41302 },
			{ 41303, 41304, 41305, 41306 },
			{ 41307, 41308, 41309, 41310 },
			{ 41311, 41312, 41313, 41314 },
			{ 41315, 41316, 41317, 41318 },
			{ 41319, 41320, 41321, 41322 },
			{ 41323, 41324, 41325, 41326 },
			{ 41327, 41328, 41329, 41330 },
		},
	},
	[2810] = {
		aliases = {
			"manaschmiedeomega",
			"manaforgeomega",
		},
		bosses = {
			{ 41633, 41634, 41635, 41636 },
			{ 41637, 41638, 41639, 41640 },
			{ 41641, 41642, 41643, 41644 },
			{ 41645, 41646, 41647, 41648 },
			{ 41649, 41650, 41651, 41652 },
			{ 41653, 41654, 41655, 41656 },
			{ 41657, 41658, 41659, 41660 },
			{ 41661, 41662, 41663, 41664 },
		},
	},
}

RAID_IDS.DIFF_INDEX_TO_ID = RAID_IDS.DIFF_INDEX_TO_ID or {
	[1] = 17, -- LFR
	[2] = 14, -- N
	[3] = 15, -- H
	[4] = 16, -- M
}

function RAID_IDS:Validate()
	local report = {
		ok = true,
		missing_map_ids = {},
		missing_boss_tables = {},
		invalid_rows = {},
		invalid_ids = {},
		duplicate_stat_ids = {},
	}

	local seen = {}
	local j2m = self.JOURNAL_TO_MAP or {}
	local m2b = self.MAP_TO_BOSS_STATS or {}

	for journalID, mapID in pairs(j2m) do
		if type(mapID) ~= "number" then
			report.missing_map_ids[#report.missing_map_ids + 1] = "journal=" .. tostring(journalID) .. " map=invalid"
		elseif type(m2b[mapID]) ~= "table" then
			report.missing_boss_tables[#report.missing_boss_tables + 1] = mapID
		end
	end

	for mapID, cfg in pairs(m2b) do
		local bosses = type(cfg) == "table" and cfg.bosses or nil
		if type(bosses) ~= "table" or #bosses <= 0 then
			report.invalid_rows[#report.invalid_rows + 1] = "map=" .. tostring(mapID) .. " bosses=empty"
		else
			for rowIndex = 1, #bosses do
				local row = bosses[rowIndex]
				if type(row) ~= "table" or #row < 4 then
					report.invalid_rows[#report.invalid_rows + 1] = "map=" .. tostring(mapID) .. " row=" .. tostring(rowIndex) .. " format"
				else
					for diffIndex = 1, 4 do
						local statID = tonumber(row[diffIndex])
						if not statID or statID <= 0 then
							report.invalid_ids[#report.invalid_ids + 1] = "map=" .. tostring(mapID) .. " row=" .. tostring(rowIndex) .. " diff=" .. tostring(diffIndex)
						else
							local prev = seen[statID]
							if prev then
								report.duplicate_stat_ids[#report.duplicate_stat_ids + 1] =
									"stat=" .. tostring(statID) .. " " .. prev .. " + map=" .. tostring(mapID) .. "/row=" .. tostring(rowIndex)
							else
								seen[statID] = "map=" .. tostring(mapID) .. "/row=" .. tostring(rowIndex)
							end
						end
					end
				end
			end
		end
	end

	if #report.missing_map_ids > 0
		or #report.missing_boss_tables > 0
		or #report.invalid_rows > 0
		or #report.invalid_ids > 0
		or #report.duplicate_stat_ids > 0 then
		report.ok = false
	end

	return report
end

function _G.GMS_RAIDIDS_VALIDATE_DUMP()
	local lib = _G.GMS_RAIDIDS
	if type(lib) ~= "table" or type(lib.Validate) ~= "function" then
		print("GMS_RAIDIDS unavailable")
		return
	end
	local report = lib:Validate()
	if type(_G.DevTools_Dump) == "function" then
		_G.DevTools_Dump(report)
		return
	end
	print("GMS_RAIDIDS ok=" .. tostring(report.ok))
	print("missing_map_ids=" .. tostring(#report.missing_map_ids))
	print("missing_boss_tables=" .. tostring(#report.missing_boss_tables))
	print("invalid_rows=" .. tostring(#report.invalid_rows))
	print("invalid_ids=" .. tostring(#report.invalid_ids))
	print("duplicate_stat_ids=" .. tostring(#report.duplicate_stat_ids))
end

LOCAL_LOG("INFO", "RaidIds extension loaded", METADATA.VERSION)
GMS:SetReady("EXT:" .. METADATA.INTERN_NAME)
