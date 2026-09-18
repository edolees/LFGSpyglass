-- Raid leader's progress (and their main's, if better) from Raider.IO, for the raid row info and the
-- raid sort; never used to filter. Best and Format are pure (unit-tested); For reads Raider.IO's public
-- RaiderIO.GetProfile inside pcall and returns nil on any problem, so nothing shows without it.
local _, ns = ...

local LeaderProgress = {}
ns.LeaderProgress = LeaderProgress

local DIFFICULTY_LETTER = { [1] = "N", [2] = "H", [3] = "M" }

local function Field(tbl, key)
	if type(tbl) ~= "table" then
		return nil
	end
	return tbl[key]
end

-- Best progress entry for the raid with this instance map: highest difficulty, then most bosses.
-- entries: Raider.IO DataProviderRaidProgress[] ({ raid = { mapId, bossCount }, difficulty, progressCount }).
function LeaderProgress.Best(entries, mapID)
	if type(entries) ~= "table" or mapID == nil then
		return nil
	end
	local best
	for _, entry in ipairs(entries) do
		local raid = Field(entry, "raid")
		local difficulty, count = Field(entry, "difficulty"), Field(entry, "progressCount")
		if Field(raid, "mapId") == mapID and type(difficulty) == "number" and type(count) == "number" and count > 0 then
			if not best or difficulty > best.difficulty or (difficulty == best.difficulty and count > best.progressCount) then
				best = entry
			end
		end
	end
	return best
end

-- Best progress entry for the raid on one difficulty (1 Normal, 2 Heroic, 3 Mythic), or nil.
function LeaderProgress.BestOn(entries, mapID, difficulty)
	if type(entries) ~= "table" then
		return nil
	end
	local only = {}
	for _, entry in ipairs(entries) do
		if Field(entry, "difficulty") == difficulty then
			only[#only + 1] = entry
		end
	end
	return LeaderProgress.Best(only, mapID)
end

-- true if progress entry a is better than b (b may be nil).
function LeaderProgress.IsBetter(a, b)
	if not a then
		return false
	end
	if not b then
		return true
	end
	if a.difficulty ~= b.difficulty then
		return a.difficulty > b.difficulty
	end
	return a.progressCount > b.progressCount
end

-- "6/8 H" (letters are passed through the locale table when given).
function LeaderProgress.Format(entry, L)
	if not entry then
		return nil
	end
	local letter = DIFFICULTY_LETTER[entry.difficulty] or "?"
	local bossCount = Field(entry.raid, "bossCount")
	local total = type(bossCount) == "number" and ("/" .. bossCount) or ""
	return string.format("%d%s %s", entry.progressCount, total, L and L[letter] or letter)
end

local cache = {}

function LeaderProgress.ResetCache()
	cache = {}
end

-- { text, difficulty, rank, heroic = "8/8 H" | nil (only when the best is Mythic),
--   main = "main 8/8 M" | nil, mainDifficulty } for the leader in this raid, or nil.
function LeaderProgress.For(leaderName, mapID)
	if type(leaderName) ~= "string" or mapID == nil then
		return nil
	end
	local key = leaderName .. "\0" .. tostring(mapID)
	if cache[key] ~= nil then
		return cache[key] or nil
	end
	cache[key] = false
	local raiderIO = ns.FrameMap.Get("raiderIO")
	local getProfile = type(raiderIO) == "table" and raiderIO.GetProfile
	if type(getProfile) ~= "function" then
		return nil
	end
	local name, realm = leaderName:match("^([^%-]+)%-(.+)$")
	if not name then
		name = leaderName
		local okRealm, playerRealm = pcall(GetNormalizedRealmName)
		realm = okRealm and playerRealm or nil
	end
	local ok, profile = pcall(getProfile, name, realm)
	local raidProfile = ok and Field(profile, "raidProfile") or nil
	if not raidProfile then
		return nil
	end
	local okBest, own, main, heroic = pcall(function()
		return LeaderProgress.Best(raidProfile.progress, mapID), LeaderProgress.Best(raidProfile.mainProgress, mapID),
			LeaderProgress.BestOn(raidProfile.progress, mapID, 2)
	end)
	if not okBest or not (own or main) then
		return nil
	end
	local L = ns.L
	local result = {}
	if own then
		result.text, result.difficulty = LeaderProgress.Format(own, L), own.difficulty
		result.rank = own.difficulty * 100 + own.progressCount -- for the raid sort (Mythic 2/8 > Heroic 8/8)
		if own.difficulty == 3 and heroic then
			result.heroic = LeaderProgress.Format(heroic, L) -- Mythic progress also shows Heroic
		end
	end
	if main and LeaderProgress.IsBetter(main, own) then
		result.main, result.mainDifficulty = LeaderProgress.Format(main, L), main.difficulty
	end
	cache[key] = result
	return result
end
