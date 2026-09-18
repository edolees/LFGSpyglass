-- Short dungeon names for the filter panel's dungeon grid ("Show dungeon abbreviations").
-- PURE: no WoW API; unit-tested.
-- Keyed by instance map ID (activity info `mapID`), never by localized name. The abbreviations are
-- the ones the Mythic+ community uses; update the table when a season adds dungeons.
local _, ns = ...

local DungeonAbbreviations = {}
ns.DungeonAbbreviations = DungeonAbbreviations

DungeonAbbreviations.BY_MAP = {
	-- Midnight
	[2805] = "WS", -- Windrunner Spire
	[2811] = "MT", -- Magisters' Terrace
	[2813] = "MR", -- Murder Row
	[2825] = "DON", -- Den of Nalorakk
	[2859] = "BV", -- The Blinding Vale
	[2874] = "MC", -- Maisara Caverns
	[2915] = "NPX", -- Nexus-Point Xenas
	[2923] = "VSA", -- Voidscar Arena
	[2987] = "TG", -- The Tidebound Grotto
	[2993] = "AOF", -- Altar of Fangs
	[3004] = "VA", -- The Venomous Abyss
	-- Earlier expansions in Midnight seasons
	[658] = "POS", -- Pit of Saron
	[1209] = "SR", -- Skyreach
	[1753] = "SEAT", -- Seat of the Triumvirate
	[1762] = "KR", -- Kings' Rest
	[1877] = "TOS", -- Temple of Sethraliss
	[2521] = "RLP", -- Ruby Life Pools
	[2526] = "AA", -- Algeth'ar Academy
}

local MINOR_WORDS = { the = true, of = true, ["and"] = true }
-- First character of a word as a whole UTF-8 sequence (localized names), not a single byte.
local FIRST_LETTER = "^[%z\1-\127\194-\244][\128-\191]*"

-- Abbreviation for a dungeon: from the table by map ID, otherwise the initials of the name's main
-- words ("Halls of Valor" -> "HV"), or its first four letters for a one-word name.
function DungeonAbbreviations.For(mapID, name)
	local known = mapID and DungeonAbbreviations.BY_MAP[mapID]
	if known then
		return known
	end
	if type(name) ~= "string" or name == "" then
		return ""
	end
	name = name:gsub(",.*$", "") -- "Ara-Kara, City of Echoes" -> "Ara-Kara"
	local initials = {}
	for word in name:gmatch("[^%s%-,:]+") do
		if not MINOR_WORDS[word:lower()] then
			initials[#initials + 1] = (word:match(FIRST_LETTER) or ""):upper()
		end
	end
	if #initials >= 2 then
		return table.concat(initials)
	end
	local letters = name:gsub("^[Tt]he%s+", ""):gsub("[^%a]", "")
	return letters:sub(1, 4):upper()
end
