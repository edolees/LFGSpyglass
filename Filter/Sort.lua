-- Result ordering. PURE: no WoW API; unit-tested.
local _, ns = ...

local Sort = {}
ns.Sort = Sort

local FIELDS = {
	leaderRating = "leaderRating",
	members = "numMembers",
	age = "age",
	-- Raids: the leader's raid progress (Raider.IO, rank = difficulty * 100 + bosses), then the group's
	-- own difficulty (Mythic > Heroic > Normal) and bosses defeated. Groups without leader data sort
	-- after the others.
	leaderProgress = "leaderProgressRank",
}

-- a before b by `field` high to low; nil values after known ones. Returns true, false or nil (tie).
local function HighFirst(a, b, field)
	local va, vb = a[field], b[field]
	if va == vb then
		return nil
	end
	if va == nil or vb == nil then
		return vb == nil
	end
	return va > vb
end

-- Returns a NEW array: groups with an application first (Blizzard order), then the rest by the
-- chosen field. Unknown values go last; ties keep Blizzard's relative order (stable).
function Sort.Order(snaps, sort)
	local out = {}
	for i = 1, #snaps do
		out[i] = snaps[i]
	end

	local key = sort and FIELDS[sort.field]
	local descending = not (sort and sort.dir == "asc")

	table.sort(out, function(a, b)
		local mineA, mineB = a.isMine and true or false, b.isMine and true or false
		if mineA ~= mineB then
			return mineA
		end
		if mineA or not key then
			return a.blizzardIndex < b.blizzardIndex
		end
		if key == "leaderProgressRank" then
			local before = HighFirst(a, b, "leaderProgressRank")
			if before == nil then
				before = HighFirst(a, b, "difficulty")
			end
			if before == nil then
				before = HighFirst(a, b, "bossesDefeated")
			end
			if before ~= nil then
				return before
			end
			return a.blizzardIndex < b.blizzardIndex
		end
		local va, vb = a[key], b[key]
		if va == nil or vb == nil then
			if (va == nil) ~= (vb == nil) then
				return vb == nil
			end
			return a.blizzardIndex < b.blizzardIndex
		end
		if va ~= vb then
			if descending then
				return va > vb
			end
			return va < vb
		end
		return a.blizzardIndex < b.blizzardIndex
	end)

	return out
end
