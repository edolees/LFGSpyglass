-- Leader region tags and flags.
-- Realm -> region / time zone / language comes from Data/RealmData.lua, generated from
-- LibRealmInfo's data (static data that ships with the addon). Flags are
-- Twemoji images (CC-BY 4.0), see README.
--
-- Regions.TagFor, RealmFromName and Lookup are PURE (unit-tested); ForLeader uses the WoW API.
local addonName, ns = ...

local Regions = {}
ns.Regions = Regions

local FLAG_PATH = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\Flags\\"

-- GetCurrentRegion() id -> LibRealmInfo region code
Regions.REGION_BY_ID = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN" }

local US_BY_TIMEZONE = {
	EST = { tag = "East", flag = "us" },
	CST = { tag = "Central", flag = "us" },
	MST = { tag = "West", flag = "us" },
	PST = { tag = "West", flag = "us" },
	AEST = { tag = "OCE", flag = "au" },
}

local EU_BY_LOCALE = {
	enUS = { tag = "EN", flag = "gb" },
	enGB = { tag = "EN", flag = "gb" },
	deDE = { tag = "DE", flag = "de" },
	frFR = { tag = "FR", flag = "fr" },
	esES = { tag = "ES", flag = "es" },
	itIT = { tag = "IT", flag = "it" },
	ruRU = { tag = "RU", flag = "ru" },
	ptPT = { tag = "PT", flag = "pt" },
	ptBR = { tag = "PT", flag = "pt" },
}

local OTHER_REGIONS = {
	KR = { tag = "KR", flag = "kr" },
	TW = { tag = "TW", flag = "tw" },
	CN = { tag = "CN", flag = "cn" },
}

-- Pure: region code + realm locale + time zone -> { tag, flag } or nil when unknown.
function Regions.TagFor(region, locale, timezone)
	if region == "US" then
		if locale == "ptBR" then
			return { tag = "BR", flag = "br" }
		elseif locale == "esMX" then
			return { tag = "LATAM", flag = "mx" }
		end
		return US_BY_TIMEZONE[timezone]
	elseif region == "EU" then
		return EU_BY_LOCALE[locale]
	end
	return OTHER_REGIONS[region]
end

function Regions.FlagTexture(flag)
	return flag and (FLAG_PATH .. flag .. ".tga") or nil
end

-- Pure: realm part of a "Name-Realm" leader name, or nil when there is no realm suffix.
function Regions.RealmFromName(leaderName)
	if type(leaderName) ~= "string" then
		return nil
	end
	local realm = leaderName:match("^[^%-]+%-(.+)$")
	if realm and realm ~= "" then
		return realm
	end
	return nil
end

-- Pure: { tag, flag } for an API realm name in a region, using a RealmData table.
function Regions.Lookup(realmData, region, realm)
	local byRealm = realmData and realmData[region]
	local value = byRealm and byRealm[realm]
	if type(value) ~= "string" then
		return nil
	end
	local locale, timezone = value:match("^([^,]+),?(.*)$")
	return Regions.TagFor(region, locale, timezone ~= "" and timezone or nil)
end

local cache = {} -- realm (normalized) -> { tag, flag } | false

local function CurrentRegionCode()
	local ok, id = pcall(GetCurrentRegion)
	return ok and Regions.REGION_BY_ID[id] or nil
end

-- { tag, flag } for a listing's leader, or nil if the realm or region is unknown.
function Regions.ForLeader(leaderName)
	if not ns.SafeRead.IsReadable(leaderName) then
		return nil
	end
	local realm = Regions.RealmFromName(leaderName)
	if not realm then
		local ok, own = pcall(GetNormalizedRealmName)
		realm = ok and own or nil
	end
	if not realm then
		return nil
	end
	local cached = cache[realm]
	if cached ~= nil then
		return cached or nil
	end

	local region = CurrentRegionCode()
	local result = region and Regions.Lookup(ns.RealmData, region, realm) or nil
	if not result and region then
		-- Unknown realm (newer than the realm list): at least show the player's own region.
		result = OTHER_REGIONS[region] or (region == "US" and { tag = "US", flag = "us" }) or (region == "EU" and { tag = "EU", flag = nil }) or nil
	end
	cache[realm] = result or false
	return result
end
