-- Saved settings (AceDB, one profile per character).
local addonName, ns = ...

local Settings = ns.NewModule("Settings")

local SCHEMA_VERSION = 2 -- 2: roles section replaced by fit.party

local function DungeonDefaults()
	return {
		activityGroups = {}, -- set { [groupID] = true }; empty = all dungeons
		excludedGroups = {}, -- set { [groupID] = true }: dungeons whose groups are hidden (right-click)
		minLeaderRating = 0, -- 0 = off
		maxLeaderRating = 0, -- 0 = off
		fit = { party = true, hasTank = false, hasHealer = false, notDeclined = false, bloodlust = false, battleRes = false, hideClass = false }, -- Party fit on by default
		sort = { field = "leaderRating", dir = "desc" }, -- "leaderRating" (desc) | "blizzard" | "age" (asc) | "members" (desc)
	}
end

-- Raids. Maxima use -1 for "off" (0 is a
-- real value: Fresh run, at most 0 tanks).
local function RaidDefaults()
	return {
		difficulties = {}, -- set { [1|2|3] = true } (Normal, Heroic, Mythic); empty = all
		aliveBosses = {}, -- set { [journalEncounterID] = true }: bosses the group must not have killed yet
		deadBosses = {}, -- set { [journalEncounterID] = true }: bosses the group must have killed already
		maxBosses = -1, -- -1 = off; 0 = Fresh run
		minMembers = 0,
		maxMembers = -1,
		maxTanks = -1,
		maxHealers = -1,
		fit = { notDeclined = false, hideClass = false }, -- the Group needs that exist for Raids
		sort = { field = "leaderProgress", dir = "desc" }, -- "leaderProgress" | "blizzard" | "age" | "members"
	}
end

local DUNGEONS, RAIDS = 2, 3

local function CategoryDefaults(categoryID)
	if categoryID == RAIDS then
		return RaidDefaults()
	end
	return DungeonDefaults()
end

Settings.CategoryDefaults = CategoryDefaults

local defaults = {
	-- Account-wide (every character): the appearance of LFG Spyglass's own frames, "stock" or
	-- "dark" (gear menu). Read once at load, so a change needs a reload.
	global = {
		appearance = "stock",
	},
	profile = {
		filterEnabled = true,
		-- Sign up as (per character): not custom = the current spec's role only
		signUpRolesCustom = false,
		signUpRoles = { TANK = false, HEALER = false, DAMAGER = false },
		-- Info added to each group row, toggled in the panel's Settings section
		rowInfo = { leaderRating = true, region = true, specs = false, leader = false, leaderProgress = true,
			memberNames = true },
		-- Ranges section shown (gear menu); the rating range doesn't filter while it's hidden
		showRanges = true,
		notices = { otherFilterAddonShown = false },
		categories = {
			[DUNGEONS] = DungeonDefaults(), -- Dungeons
			[RAIDS] = RaidDefaults(), -- Raids
		},
	},
}

local function CopyInto(target, source)
	for k, v in pairs(source) do
		if type(v) == "table" then
			target[k] = {}
			CopyInto(target[k], v)
		else
			target[k] = v
		end
	end
end

local function MigrateProfile(profile)
	if profile.schemaVersion == SCHEMA_VERSION then
		return
	end
	-- Pre-release schemas (1 had a roles section) are simply reset to defaults.
	if profile.schemaVersion ~= nil then
		for id in pairs(profile.categories) do
			Settings.ResetCategory(id)
		end
	end
	profile.schemaVersion = SCHEMA_VERSION
end

-- Raids no longer have raid buttons: drop a saved raid selection.
local function DropRaidSelection(profile)
	local raids = profile.categories and profile.categories[RAIDS]
	if type(raids) == "table" then
		raids.activityGroups = nil
	end
end

-- The dungeon buttons are always abbreviated now: drop the old option.
local function DropAbbreviationOption(profile)
	profile.dungeonAbbreviations = nil
end

-- "Match my UI" (UI-suite matching) became the appearance choice: drop the old key.
local function DropMatchUI(profile)
	profile.matchUI = nil
end

-- The appearance moved from the character's profile to account-wide: carry a saved choice over once.
local function MigrateAppearance(db)
	local profile = db.profile
	if profile.appearance ~= nil then
		if profile.appearance == "dark" then
			db.global.appearance = "dark"
		end
		profile.appearance = nil
	end
end

-- "Hide Ranges" (earlier option) became "Show Ranges": carry a saved choice over once.
local function MigrateHideRanges(profile)
	if profile.hideRatingRange ~= nil then
		profile.showRanges = not profile.hideRatingRange
		profile.hideRatingRange = nil
	end
end

-- Sort choices that are no longer offered (Leader rating low to high, Best fit for my role, the
-- raid "Difficulty, then bosses defeated") go back to the category's default sort.
local function NormalizeSorts(profile)
	for categoryID, category in pairs(profile.categories) do
		local sort = type(category) == "table" and category.sort
		if type(sort) == "table" and (sort.field == "fit" or sort.field == "raidProgress"
			or (sort.field == "leaderRating" and sort.dir == "asc")) then
			local default = CategoryDefaults(categoryID).sort
			sort.field, sort.dir = default.field, default.dir
		end
	end
end

function Settings:OnInitialize()
	-- Settings are saved per character, with no profiles UI: without a default profile name AceDB
	-- gives each character its own profile ("Name - Realm").
	local savedVars = _G[addonName .. "DB"]
	local previousKeys = {}
	if type(savedVars) == "table" and type(savedVars.profileKeys) == "table" then
		for charKey, profileKey in pairs(savedVars.profileKeys) do
			previousKeys[charKey] = profileKey
		end
	end
	self.db = LibStub("AceDB-3.0"):New(addonName .. "DB", defaults)

	-- One-time move for characters that used the old shared "Default" profile: switch them to their
	-- own profile, starting from a copy of the shared settings.
	local charKey = self.db.keys.char
	if previousKeys[charKey] == "Default" and self.db:GetCurrentProfile() ~= charKey then
		local hadShared = rawget(self.db.profiles, "Default") ~= nil
		self.db:SetProfile(charKey)
		if hadShared then
			self.db:CopyProfile("Default", true)
		end
	end
	MigrateProfile(self.db.profile)
	NormalizeSorts(self.db.profile)
	MigrateHideRanges(self.db.profile)
	DropRaidSelection(self.db.profile)
	DropAbbreviationOption(self.db.profile)
	DropMatchUI(self.db.profile)
	MigrateAppearance(self.db)
	local function OnProfileChanged()
		MigrateProfile(self.db.profile)
		NormalizeSorts(self.db.profile)
		MigrateHideRanges(self.db.profile)
		DropRaidSelection(self.db.profile)
		DropAbbreviationOption(self.db.profile)
		DropMatchUI(self.db.profile)
		MigrateAppearance(self.db)
		self:SendMessage(ns.MSG.SettingsChanged)
	end
	self.db.RegisterCallback(self, "OnProfileChanged", OnProfileChanged)
	self.db.RegisterCallback(self, "OnProfileCopied", OnProfileChanged)
	self.db.RegisterCallback(self, "OnProfileReset", OnProfileChanged)
end

function Settings.Profile()
	return Settings.db.profile
end

-- Account-wide settings (shared by every character): the appearance.
function Settings.Global()
	return Settings.db.global
end

-- Settings for one category, or nil if the category is not supported.
function Settings.ForCategory(categoryID)
	return categoryID and Settings.db.profile.categories[categoryID] or nil
end

-- Reset a category's filter + sort in place (UI keeps its references).
function Settings.ResetCategory(categoryID)
	local current = Settings.ForCategory(categoryID)
	if not current then
		return
	end
	wipe(current)
	CopyInto(current, CategoryDefaults(categoryID))
end

-- Notify listeners (engine, panel) that a setting changed. Never triggers a search.
function Settings:Changed()
	self:SendMessage(ns.MSG.SettingsChanged)
end
