-- Builds ResultSnapshot records and the PlayerContext.
-- All game data goes through Core/SafeRead.lua; Build never errors and marks unreadable
-- results with readable = false so the missing-data rules apply.
local _, ns = ...

local Snapshot = ns.NewModule("Snapshot")
local SafeRead = ns.SafeRead
local Field = SafeRead.Field

local ROLE_BY_ENUM -- Enum.LFGRole -> "TANK" | "HEALER" | "DAMAGER"
local ROLE_KEYS = { TANK = true, HEALER = true, DAMAGER = true }
local MINE = { applied = true, invited = true, inviteaccepted = true }
-- A real decline by the group. Blizzard also counts "declined_delisted" (the group delisted while
-- the player had applied) as a decline; LFG Spyglass doesn't: nobody declined, the listing just went
-- away, and the group may list again.
local DECLINED = { declined = true, declined_full = true }
local WAS_DELISTED = { declined_delisted = true }

local playerContext

local function PlayerRole()
	local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
	local okSpec, spec = pcall(getSpec)
	if not okSpec or not spec then
		return nil
	end
	if GetSpecializationRoleEnum and Enum and Enum.LFGRole then
		if not ROLE_BY_ENUM then
			ROLE_BY_ENUM = {
				[Enum.LFGRole.Tank] = "TANK",
				[Enum.LFGRole.Healer] = "HEALER",
				[Enum.LFGRole.Damage] = "DAMAGER",
			}
		end
		local ok, roleEnum = pcall(GetSpecializationRoleEnum, spec)
		if ok and SafeRead.IsReadable(roleEnum) and ROLE_BY_ENUM[roleEnum] then
			return ROLE_BY_ENUM[roleEnum]
		end
	end
	if GetSpecializationRole then
		local ok, role = pcall(GetSpecializationRole, spec)
		if ok and ROLE_KEYS[role] then
			return role
		end
	end
	return nil
end

local function AssignedRole(unit)
	if not UnitGroupRolesAssigned then
		return nil
	end
	local ok, role = pcall(UnitGroupRolesAssigned, unit)
	if ok and SafeRead.IsReadable(role) and ROLE_KEYS[role] then
		return role
	end
	return nil
end

-- Open spots the OTHER party members need (Party fit): one per member by assigned role; members
-- without a readable role count as ANY. The player is added per sign-up role in Filter/Match.lua.
local function PartyOthers()
	local needs = { TANK = 0, HEALER = 0, DAMAGER = 0, ANY = 0 }
	local function Add(role)
		if role then
			needs[role] = needs[role] + 1
		else
			needs.ANY = needs.ANY + 1
		end
	end
	local okGroup, inGroup = pcall(IsInGroup)
	if not (okGroup and inGroup) then
		return needs
	end
	local okCount, members = pcall(GetNumGroupMembers)
	members = okCount and type(members) == "number" and members or 1
	local okRaid, inRaid = pcall(IsInRaid)
	if okRaid and inRaid then
		needs.ANY = needs.ANY + math.max(0, members - 1) -- a raid group never fits a 5-player group
	else
		for i = 1, math.max(0, members - 1) do
			Add(AssignedRole("party" .. i))
		end
	end
	return needs
end

function Snapshot.GetPlayerContext()
	if not playerContext then
		local okClass, classFile = pcall(UnitClassBase, "player")
		classFile = okClass and SafeRead.IsReadable(classFile) and classFile or nil
		local classUtility = ns.ClassUtility
		local role = PlayerRole()
		playerContext = {
			classFile = classFile,
			role = role,
			partyOthers = PartyOthers(),
			bringsBloodlust = classFile ~= nil and classUtility.BLOODLUST[classFile] == true,
			bringsBattleRes = classFile ~= nil and classUtility.BATTLE_RES[classFile] == true,
		}
	end
	return playerContext
end

local classFiles -- ordered list of every class file name, read once

local function ClassFiles()
	if classFiles then
		return classFiles
	end
	classFiles = {}
	if type(CLASS_SORT_ORDER) == "table" then
		for _, classFile in ipairs(CLASS_SORT_ORDER) do
			classFiles[#classFiles + 1] = classFile
		end
	elseif type(LOCALIZED_CLASS_NAMES_MALE) == "table" then
		for classFile in pairs(LOCALIZED_CLASS_NAMES_MALE) do
			classFiles[#classFiles + 1] = classFile
		end
	end
	return classFiles
end

local function ClassesFromCounts(counts)
	local classes, anyKnown = {}, false
	for _, classFile in ipairs(ClassFiles()) do
		local count = Field(counts, classFile)
		if type(count) == "number" then
			anyKnown = true
			if count > 0 then
				classes[classFile] = true
			end
		end
	end
	return anyKnown and classes or nil
end

local function ClassesFromMembers(resultID, numMembers)
	if type(numMembers) ~= "number" or numMembers < 1 then
		return nil
	end
	local classes = {}
	for i = 1, numMembers do
		local member = SafeRead.GetPlayerInfo(resultID, i)
		local classFile = Field(member, "classFilename")
		if not classFile then
			return nil -- any unknown member makes the whole group's classes unknown
		end
		classes[classFile] = true
	end
	return classes
end

local function Number(value)
	return type(value) == "number" and value or nil
end

-- Raid difficulty rank (1 Normal, 2 Heroic, 3 Mythic) of an activity. Raid activities
-- carry a difficultyID (14 Normal, 15 Heroic, 16 Mythic), which is what Raider.IO reads too; other
-- IDs are asked from GetDifficultyInfo (displayMythic / displayHeroic), then the activity's
-- Normal/Heroic/Mythic flags as a last resort. nil = unknown.
local RAID_DIFFICULTY_RANK = { [14] = 1, [15] = 2, [16] = 3 }

local function DifficultyRank(activity)
	local difficultyID = Number(Field(activity, "difficultyID"))
	if difficultyID and difficultyID > 0 then
		if RAID_DIFFICULTY_RANK[difficultyID] then
			return RAID_DIFFICULTY_RANK[difficultyID]
		end
		if GetDifficultyInfo then
			local ok, name, _, isHeroic, _, displayHeroic, displayMythic = pcall(GetDifficultyInfo, difficultyID)
			if ok and name then
				if displayMythic then
					return 3
				elseif displayHeroic or isHeroic then
					return 2
				end
				return 1
			end
		end
	end
	if Field(activity, "isMythicActivity") == true then
		return 3
	elseif Field(activity, "isHeroicActivity") == true then
		return 2
	elseif Field(activity, "isNormalActivity") == true then
		return 1
	end
	return nil
end

function Snapshot.Build(resultID, blizzardIndex)
	local appStatus, pendingStatus = SafeRead.GetApplicationInfo(resultID)
	local snap = {
		resultID = resultID,
		blizzardIndex = blizzardIndex,
		appStatus = appStatus,
		pendingStatus = pendingStatus,
		isMine = MINE[appStatus] == true or pendingStatus == "applied",
		isDelisted = false,
		leaderRating = 0,
		readable = false,
	}

	local info = SafeRead.GetResultInfo(resultID)
	if not info then
		return snap
	end
	snap.readable = true
	snap.declined = DECLINED[appStatus] == true
	snap.wasDelisted = WAS_DELISTED[appStatus] == true
	local partyGUID = Field(info, "partyGUID")
	if partyGUID and not snap.declined then
		-- Blizzard remembers the last application status per group (LFGListFrame.declines) even after
		-- a relist: a real decline still counts, a delisting doesn't.
		local declines = Field(ns.FrameMap.Get("lfgList"), "declines")
		local remembered = declines and Field(declines, partyGUID) or nil
		if DECLINED[remembered] then
			snap.declined = true
		elseif WAS_DELISTED[remembered] then
			snap.wasDelisted = true
		end
	end

	local activityIDs = Field(info, "activityIDs")
	local activityID = Field(activityIDs, 1)
	snap.activityGroupID = SafeRead.GetActivityGroupID(activityID)
	local activity = SafeRead.GetActivityInfo(activityID)
	snap.mapID = Number(Field(activity, "mapID"))
	snap.difficulty = DifficultyRank(activity)
	local defeated = SafeRead.GetEncounterNames(resultID)
	snap.bossesDefeated = defeated and #defeated or nil
	-- Raids: which of the raid's bosses are dead, matched by name to the Encounter Journal list (both
	-- from the client, same language). Any name that doesn't match = unknown.
	local raid = Field(activity, "categoryID") == ns.Categories.RAIDS and ns.Categories.GetRaidForMap(snap.mapID) or nil
	if raid and raid.bossIDs then
		snap.raidBossIDs = raid.bossIDs
		if defeated then
			local killed = {}
			for _, name in ipairs(defeated) do
				local bossID = raid.bossIDByName[name]
				if not bossID then
					killed = nil
					break
				end
				killed[bossID] = true
			end
			snap.killedBossIDs = killed
		end
	end
	snap.leaderRating = Number(Field(info, "leaderOverallDungeonScore")) or 0
	local leaderName = Field(info, "leaderName")
	snap.leaderName = type(leaderName) == "string" and leaderName or nil
	snap.numMembers = Number(Field(info, "numMembers"))
	snap.age = Number(Field(info, "age"))
	snap.isDelisted = Field(info, "isDelisted") == true

	local counts = SafeRead.GetMemberCounts(resultID)
	if counts then
		local tank = Number(Field(counts, "TANK_REMAINING"))
		local healer = Number(Field(counts, "HEALER_REMAINING"))
		local damager = Number(Field(counts, "DAMAGER_REMAINING"))
		if tank and healer and damager then
			snap.remaining = { TANK = tank, HEALER = healer, DAMAGER = damager }
		end
		local tanks, healers = Number(Field(counts, "TANK")), Number(Field(counts, "HEALER"))
		if tanks and healers then
			snap.roleCounts = { TANK = tanks, HEALER = healers, DAMAGER = Number(Field(counts, "DAMAGER")) }
		end
		snap.classes = ClassesFromCounts(counts)
	end
	if not snap.classes then
		snap.classes = ClassesFromMembers(resultID, snap.numMembers)
	end

	return snap
end

-- Roles the player's class can play: { TANK = bool, HEALER = bool, DAMAGER = bool } or nil.
function Snapshot.AvailableRoles()
	if not (C_LFGList and C_LFGList.GetAvailableRoles) then
		return nil
	end
	local ok, tank, healer, dps = pcall(C_LFGList.GetAvailableRoles)
	if not ok then
		return nil
	end
	return { TANK = tank == true, HEALER = healer == true, DAMAGER = dps == true }
end

-- The player's sign-up roles right now (ordered list), per the Sign up as settings.
function Snapshot.SignUpRoles()
	local profile = ns.Settings.Profile()
	local player = Snapshot.GetPlayerContext()
	return ns.Match.ResolveSignUpRoles(profile.signUpRolesCustom, profile.signUpRoles, player.role, Snapshot.AvailableRoles())
end

function Snapshot:InvalidatePlayer()
	playerContext = nil
	self:SendMessage(ns.MSG.SettingsChanged)
end

function Snapshot:OnEnable()
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "InvalidatePlayer")
	self:RegisterEvent("PLAYER_ROLES_ASSIGNED", "InvalidatePlayer")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "InvalidatePlayer")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "InvalidatePlayer")
end
