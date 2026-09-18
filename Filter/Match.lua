-- Filter match rules. PURE: no WoW API; unit-tested.
local _, ns = ...

local Match = {}
ns.Match = Match

local ROLES = { "TANK", "HEALER", "DAMAGER" }
local FIT_CHECKS = { "party", "hasTank", "hasHealer", "notDeclined", "bloodlust", "battleRes", "hideClass" }

-- Selected dungeon groups that still exist this season. Saved IDs that are no longer in the
-- season list are ignored (kept in saved data). Every season dungeon selected ("All") is the same
-- as none selected: no dungeon filter. seasonGroups: set { [groupID] = true } or nil.
function Match.EffectiveGroups(activityGroups, seasonGroups)
	local effective = {}
	for groupID, selected in pairs(activityGroups or {}) do
		if selected and (seasonGroups == nil or seasonGroups[groupID]) then
			effective[groupID] = true
		end
	end
	if seasonGroups and next(seasonGroups) ~= nil then
		for groupID in pairs(seasonGroups) do
			if not effective[groupID] then
				return effective
			end
		end
		return {}
	end
	return effective
end

-- Fit checkboxes that are switched on AND apply to the player's class.
function Match.ActiveFitChecks(settings, player, classUtility)
	local active = {}
	local fit = settings.fit or {}
	for _, check in ipairs(FIT_CHECKS) do
		if fit[check] and classUtility.AppliesTo(check, player.classFile) then
			active[#active + 1] = check
		end
	end
	return active
end

-- Raid ranges: minima are off at 0, maxima at -1 (0 is a real maximum: Fresh run).
local RAID_MINIMA = { "minMembers" }
local RAID_MAXIMA = { "maxBosses", "maxMembers", "maxTanks", "maxHealers" }

local function MinOn(value)
	return type(value) == "number" and value > 0
end

local function MaxOn(value)
	return type(value) == "number" and value >= 0
end

-- Every filter that is on, as ids: "dungeons" (the dungeon or raid selection), "minRating",
-- "maxRating", "difficulties", the raid ranges, then the fit checks. A filter only exists when its
-- settings key does, so one list serves Dungeons and Raids.
function Match.ActiveFilters(settings, player, classUtility)
	local active = {}
	if next(settings.activityGroups or {}) ~= nil then
		active[#active + 1] = "dungeons"
	end
	if (settings.minLeaderRating or 0) > 0 then
		active[#active + 1] = "minRating"
	end
	if (settings.maxLeaderRating or 0) > 0 then
		active[#active + 1] = "maxRating"
	end
	if next(settings.difficulties or {}) ~= nil then
		active[#active + 1] = "difficulties"
	end
	if next(settings.aliveBosses or {}) ~= nil then
		active[#active + 1] = "aliveBosses"
	end
	for _, key in ipairs(RAID_MINIMA) do
		if MinOn(settings[key]) then
			active[#active + 1] = key
		end
	end
	for _, key in ipairs(RAID_MAXIMA) do
		if MaxOn(settings[key]) then
			active[#active + 1] = key
		end
	end
	for _, check in ipairs(Match.ActiveFitChecks(settings, player, classUtility)) do
		active[#active + 1] = check
	end
	return active
end

function Match.IsFilterActive(settings, player, classUtility)
	return #Match.ActiveFilters(settings, player, classUtility) > 0
end

-- Roles the player signs up as: the ticked "Sign up as" roles the class can play, or the current
-- spec's role when none are chosen (default). available = { TANK = bool, HEALER = bool, DAMAGER = bool }.
function Match.ResolveSignUpRoles(custom, chosen, specRole, available)
	local roles = {}
	if custom and chosen then
		for _, role in ipairs(ROLES) do
			if chosen[role] and (not available or available[role]) then
				roles[#roles + 1] = role
			end
		end
	end
	if #roles == 0 and specRole then
		roles[1] = specRole
	end
	return roles
end

-- Open spots needed if the player takes `role` (nil = any role): the other party members' needs
-- (player.partyOthers, from Filter/Snapshot.lua) plus the player.
function Match.PartyNeeds(player, role)
	local others = player.partyOthers or {}
	local needs = { TANK = others.TANK or 0, HEALER = others.HEALER or 0, DAMAGER = others.DAMAGER or 0, ANY = others.ANY or 0 }
	if role and needs[role] then
		needs[role] = needs[role] + 1
	else
		needs.ANY = needs.ANY + 1
	end
	return needs
end

-- Party fit: the group has room for the party with the player in ANY of their sign-up roles.
function Match.PartyFitsAnyRole(remaining, player)
	local roles = player.signUpRoles
	if not roles or #roles == 0 then
		roles = { player.role or false }
	end
	for _, role in ipairs(roles) do
		if Match.PartyFits(remaining, Match.PartyNeeds(player, role or nil)) then
			return true
		end
	end
	return false
end

-- A group fits the party if every role need is covered by that role's open spots, and the
-- spots left over cover the members whose role is unknown (ANY).
function Match.PartyFits(remaining, needs)
	local spare = 0
	for _, role in ipairs(ROLES) do
		local open = remaining[role] or 0
		local need = needs[role] or 0
		if open < need then
			return false
		end
		spare = spare + (open - need)
	end
	return spare >= (needs.ANY or 0)
end

local function HasAnyClassIn(classes, set)
	for classFile in pairs(classes) do
		if set[classFile] then
			return true
		end
	end
	return false
end

-- Party fit for one snapshot: room for the party with the player in one of their sign-up roles.
function Match.Fits(snap, player)
	local remaining = snap.readable == true and snap.remaining or nil
	return remaining ~= nil and Match.PartyFitsAnyRole(remaining, player)
end

-- settings.activityGroups is expected to already be the effective set (see EffectiveGroups).
function Match.IsVisible(snap, settings, player, classUtility)
	if snap.isMine then
		return true
	end
	local readable = snap.readable == true

	-- Dungeon
	if next(settings.activityGroups or {}) ~= nil then
		if not readable or snap.activityGroupID == nil or not settings.activityGroups[snap.activityGroupID] then
			return false
		end
	end

	-- Leader rating range (unknown counts as 0)
	local rating = readable and snap.leaderRating or 0
	local minRating = settings.minLeaderRating or 0
	if minRating > 0 and (rating or 0) < minRating then
		return false
	end
	local maxRating = settings.maxLeaderRating or 0
	if maxRating > 0 and (rating or 0) > maxRating then
		return false
	end

	-- Difficulty (Raids): 1 Normal, 2 Heroic, 3 Mythic
	if next(settings.difficulties or {}) ~= nil then
		if not (readable and snap.difficulty and settings.difficulties[snap.difficulty]) then
			return false
		end
	end

	-- Raid ranges (unknown data fails an active range)
	local bosses = readable and snap.bossesDefeated or nil
	local members = readable and snap.numMembers or nil
	local counts = readable and snap.roleCounts or nil
	-- Bosses still alive (Raids): a ticked boss of this group's raid must not be killed yet;
	-- unknown kills (unreadable or unmatched names) fail. Bosses of other raids don't apply.
	if next(settings.aliveBosses or {}) ~= nil and snap.raidBossIDs then
		for bossID in pairs(settings.aliveBosses) do
			if snap.raidBossIDs[bossID] then
				local killed = readable and snap.killedBossIDs or nil
				if not killed or killed[bossID] then
					return false
				end
			end
		end
	end
	if MaxOn(settings.maxBosses) and not (bosses and bosses <= settings.maxBosses) then
		return false
	end
	if MinOn(settings.minMembers) and not (members and members >= settings.minMembers) then
		return false
	end
	if MaxOn(settings.maxMembers) and not (members and members <= settings.maxMembers) then
		return false
	end
	if MaxOn(settings.maxTanks) and not (counts and counts.TANK and counts.TANK <= settings.maxTanks) then
		return false
	end
	if MaxOn(settings.maxHealers) and not (counts and counts.HEALER and counts.HEALER <= settings.maxHealers) then
		return false
	end

	-- Group needs (only checkboxes that apply to the player's class)
	for _, check in ipairs(Match.ActiveFitChecks(settings, player, classUtility)) do
		if check == "party" then
			if not Match.Fits(snap, player) then
				return false
			end
		elseif check == "notDeclined" then
			if readable and snap.declined then
				return false
			end
		elseif check == "hasTank" or check == "hasHealer" then
			local counts = readable and snap.roleCounts or nil
			local role = check == "hasTank" and "TANK" or "HEALER"
			if not (counts and (counts[role] or 0) >= 1) then
				return false
			end
		else
			local classes = readable and snap.classes or nil
			if not classes then
				return false
			end
			if check == "bloodlust" and HasAnyClassIn(classes, classUtility.BLOODLUST) then
				return false
			elseif check == "battleRes" and HasAnyClassIn(classes, classUtility.BATTLE_RES) then
				return false
			elseif check == "hideClass" and player.classFile and classes[player.classFile] then
				return false -- Hide Class: someone of the player's class is already in the group
			end
		end
	end

	return true
end
