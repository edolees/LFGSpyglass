-- Group Finder categories and active-category tracking (read-only post-hooks).
local _, ns = ...

local Categories = ns.NewModule("Categories")

Categories.DUNGEONS = 2
Categories.RAIDS = 3

-- Categories that get the LFG Spyglass filter: Dungeons and Raids.
Categories.FILTERED = { [2] = true, [3] = true }

local activeCategoryID
local activePanelKey

function Categories.GetActive()
	return activeCategoryID
end

function Categories.GetActivePanel()
	return activePanelKey
end

function Categories.IsFiltered(categoryID)
	return categoryID ~= nil and Categories.FILTERED[categoryID] == true
end

-- Current-season activity groups of a category, read from the game: dungeons (2) or raids (3). Returns an ordered list of
-- { groupID, name, mapID, icon, abbreviation }. Empty results are not cached (data may not be ready
-- yet right after login).
local seasonGroups, seasonSets = {}, {}
local CurrentGroupIDs

-- Mythic+ icons for dungeons, matched by instance map or name.
local function ChallengeIcons()
	local iconByMap, iconByName = {}, {}
	if C_ChallengeMode and C_ChallengeMode.GetMapTable then
		local okTable, maps = pcall(C_ChallengeMode.GetMapTable)
		for _, challengeMapID in ipairs(okTable and maps or {}) do
			local okInfo, name, _, _, texture, _, mapID = pcall(C_ChallengeMode.GetMapUIInfo, challengeMapID)
			if okInfo and texture then
				if mapID then
					iconByMap[mapID] = texture
				end
				if name then
					iconByName[name] = texture
				end
			end
		end
	end
	return iconByMap, iconByName
end

-- Encounter Journal instance of a raid's instance map, and its button image. Falls
-- back to the journal's own raid list for the current tier (EJ_GetInstanceByIndex, 11th return = map).
local function JournalInstance(mapID)
	if not mapID then
		return nil
	end
	local journalInstanceID
	if C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap then
		local okInstance, id = pcall(C_EncounterJournal.GetInstanceForGameMap, mapID)
		journalInstanceID = okInstance and type(id) == "number" and id or nil
	end
	if not journalInstanceID and EJ_GetInstanceByIndex then
		for index = 1, 40 do
			local ok, id, _, _, _, _, _, _, _, _, _, instanceMapID = pcall(EJ_GetInstanceByIndex, index, true)
			if not (ok and type(id) == "number") then
				break
			end
			if instanceMapID == mapID then
				journalInstanceID = id
				break
			end
		end
	end
	if not journalInstanceID then
		return nil
	end
	local icon
	if EJ_GetInstanceInfo then
		local okInfo, _, _, _, buttonImage = pcall(EJ_GetInstanceInfo, journalInstanceID)
		icon = okInfo and buttonImage or nil
	end
	return journalInstanceID, icon
end

-- A raid's bosses in Encounter Journal order: { { id = journalEncounterID, name } } plus a
-- name -> id lookup. Like other raid add-ons, the instance is selected first
-- (EJ_SelectInstance) so the boss calls answer; the journal's previous selection is put back, and
-- nothing is read while the Encounter Journal window is open (retried later).
local function JournalBosses(journalInstanceID)
	local bosses, idByName = {}, {}
	if not (journalInstanceID and EJ_GetEncounterInfoByIndex) then
		return bosses, idByName
	end
	local journal = ns.FrameMap.Get("encounterJournal")
	if journal and journal.IsShown and journal:IsShown() then
		return bosses, idByName
	end
	local previous = ns.SafeRead.Field(journal, "instanceID")
	if EJ_SelectInstance then
		pcall(EJ_SelectInstance, journalInstanceID)
	end
	for index = 1, 40 do
		local ok, name, _, bossID = pcall(EJ_GetEncounterInfoByIndex, index, journalInstanceID)
		if not (ok and type(bossID) == "number" and bossID > 0 and type(name) == "string") then
			break
		end
		bosses[#bosses + 1] = { id = bossID, name = name }
		idByName[name] = bossID
	end
	if EJ_SelectInstance and type(previous) == "number" and previous ~= journalInstanceID then
		pcall(EJ_SelectInstance, previous)
	end
	return bosses, idByName
end

local BOSS_RETRY_SECONDS = 5

-- Fill (or retry) a raid's boss list; an empty list is retried at most every few seconds.
local function EnsureBosses(group)
	if group.bosses and #group.bosses > 0 then
		return
	end
	local now = GetTime and GetTime() or 0
	if group.bossRetryAt and now < group.bossRetryAt then
		return
	end
	group.bossRetryAt = now + BOSS_RETRY_SECONDS
	if not group.journalInstanceID then
		group.journalInstanceID, group.icon = JournalInstance(group.mapID)
	end
	group.bosses, group.bossIDByName = JournalBosses(group.journalInstanceID)
	group.bossIDs = {}
	for _, boss in ipairs(group.bosses) do
		group.bossIDs[boss.id] = true
	end
end

local function QueryGroups(categoryID, filterValue)
	if not (filterValue and C_LFGList.GetAvailableActivityGroups) then
		return {}
	end
	local ok, groups = pcall(C_LFGList.GetAvailableActivityGroups, categoryID, filterValue)
	if ok and ns.SafeRead.IsReadable(groups) and type(groups) == "table" then
		return groups
	end
	return {}
end

-- Activity group IDs to offer. Dungeons: the current Mythic+ season. Raids aren't tagged
-- CurrentSeason (the list came back empty in game): use Blizzard's own "Raids - Current"
-- filter (Recommended), then CurrentSeason, then CurrentExpansion. Every one of those covers the
-- whole expansion, so the season's raids are picked out later by Data/SeasonRaids.lua; Blizzard's
-- isCurrentRaidActivity flag is set on all of them and narrows nothing.
CurrentGroupIDs = function(categoryID)
	local filter = Enum and Enum.LFGListFilter
	if not filter then
		return {}
	end
	if categoryID ~= Categories.RAIDS then
		return QueryGroups(categoryID, bit.bor(filter.CurrentSeason, filter.PvE))
	end
	for _, key in ipairs({ "Recommended", "CurrentSeason", "CurrentExpansion" }) do
		local groups = filter[key] and QueryGroups(categoryID, bit.bor(filter[key], filter.PvE)) or {}
		if #groups > 0 then
			return groups
		end
	end
	return {}
end

function Categories.GetSeasonGroups(categoryID)
	if seasonGroups[categoryID] then
		return seasonGroups[categoryID]
	end
	local list = {}
	for _, groupID in ipairs(CurrentGroupIDs(categoryID)) do
		local okName, name = pcall(C_LFGList.GetActivityGroupInfo, groupID)
		list[#list + 1] = { groupID = groupID, name = okName and name or tostring(groupID) }
	end
	local iconByMap, iconByName = {}, {}
	if categoryID == Categories.DUNGEONS then
		iconByMap, iconByName = ChallengeIcons()
	end
	for _, group in ipairs(list) do
		-- Instance map of the group's activities: used for the icon and the abbreviation.
		if C_LFGList.GetAvailableActivities then
			local okActs, activities = pcall(C_LFGList.GetAvailableActivities, categoryID, group.groupID)
			for _, activityID in ipairs(okActs and activities or {}) do
				local mapID = ns.SafeRead.Field(ns.SafeRead.GetActivityInfo(activityID), "mapID")
				if type(mapID) == "number" then
					group.mapID = group.mapID or mapID
				end
			end
		end
		if categoryID == Categories.DUNGEONS then
			group.icon = iconByName[group.name] or (group.mapID and iconByMap[group.mapID])
		else
			group.journalInstanceID, group.icon = JournalInstance(group.mapID)
			group.bosses, group.bossIDByName, group.bossIDs = {}, {}, {} -- filled on first use (EnsureBosses)
		end
		group.abbreviation = ns.DungeonAbbreviations.For(group.mapID, group.name)
	end

	if categoryID == Categories.RAIDS then
		list = ns.SeasonRaids.Pick(list) -- this season's raids only
	end

	if #list > 0 then
		table.sort(list, function(a, b)
			return tostring(a.name) < tostring(b.name)
		end)
		seasonGroups[categoryID] = list
		local set = {}
		for _, group in ipairs(list) do
			set[group.groupID] = true
		end
		seasonSets[categoryID] = set
	end
	return list
end

-- Set { [groupID] = true } of a category's current-season groups, or nil if not known yet.
function Categories.GetSeasonGroupSet(categoryID)
	Categories.GetSeasonGroups(categoryID)
	return seasonSets[categoryID]
end

-- The current raid for an instance map (with its bosses), or nil.
function Categories.GetRaidForMap(mapID)
	if mapID == nil then
		return nil
	end
	for _, group in ipairs(Categories.GetSeasonGroups(Categories.RAIDS)) do
		if group.mapID == mapID then
			EnsureBosses(group)
			return group
		end
	end
	return nil
end

-- The raids whose bosses the panel lists: the selected raids, else every raid of the season. A
-- season is one tier, so the merged list stays short and the bosses of a raid nobody selected are
-- still there to tick.
function Categories.GetBossListRaids(settings)
	local raids = Categories.GetSeasonGroups(Categories.RAIDS)
	local selected = {}
	for _, group in ipairs(raids) do
		if settings and settings.activityGroups and settings.activityGroups[group.groupID] then
			selected[#selected + 1] = group
		end
	end
	local shown = #selected > 0 and selected or raids
	for _, raid in ipairs(shown) do
		EnsureBosses(raid)
	end
	return shown
end

function Categories.GetSeasonDungeons()
	return Categories.GetSeasonGroups(Categories.DUNGEONS)
end

function Categories.GetSeasonDungeonSet()
	return Categories.GetSeasonGroupSet(Categories.DUNGEONS)
end

local PANEL_KEYS = { "categorySelection", "searchPanel", "entryCreation", "applicationViewer" }

local function PanelKeyFor(panel)
	for _, key in ipairs(PANEL_KEYS) do
		if panel ~= nil and panel == ns.FrameMap.Get(key) then
			return key
		end
	end
	return "other"
end

function Categories:OnEnable()
	-- Pick up the category if the search panel was already set up before we loaded (e.g. /reload).
	local initial = ns.SafeRead.Field(ns.FrameMap.Get("searchPanel"), "categoryID")
	if type(initial) == "number" then
		activeCategoryID = initial
	end

	ns.FrameMap.Hook("setCategory", function(panel, categoryID)
		if panel ~= ns.FrameMap.Get("searchPanel") or not ns.SafeRead.IsReadable(categoryID) then
			return
		end
		if categoryID ~= activeCategoryID then
			activeCategoryID = categoryID
			ns.Debug("Active category: %s", categoryID)
			self:SendMessage(ns.MSG.ActiveCategoryChanged, categoryID)
		end
	end)

	ns.FrameMap.Hook("setActivePanel", function(_, panel)
		local key = PanelKeyFor(panel)
		if key ~= activePanelKey then
			activePanelKey = key
			self:SendMessage(ns.MSG.ActivePanelChanged, key)
		end
	end)
end
