-- This season's raids, for the Raids buttons in the filter panel.
-- PURE: no WoW API; unit-tested.
-- Blizzard's raid list in the Group Finder covers the whole expansion, so this table picks the
-- season's raids out of it. Keyed by instance map ID
-- (activity info `mapID`), never by localized name. Update it when a season adds or retires raids.
local _, ns = ...

local SeasonRaids = {}
ns.SeasonRaids = SeasonRaids

SeasonRaids.BY_MAP = {
	-- Current season (checked in game 2026-09-16)
	[3004] = true, -- The Venomous Abyss
	[2987] = true, -- The Tidebound Grotto
}

-- The raids of `groups` (each with a `mapID`) that are in the table, in the same order. If none
-- are, `groups` itself: an out-of-date table shows every raid rather than none.
function SeasonRaids.Pick(groups)
	local season = {}
	for _, group in ipairs(groups) do
		if group.mapID and SeasonRaids.BY_MAP[group.mapID] then
			season[#season + 1] = group
		end
	end
	return #season > 0 and season or groups
end
