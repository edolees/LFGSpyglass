-- Filter engine: one coalesced pass per Blizzard result update or setting change. Never starts a
-- search.
local _, ns = ...

local Engine = ns.NewModule("Engine")

-- Test-only switch (raise inside the pass) used by the smoke test; never saved.
Engine.debugBreak = false

local queued = false
local lastRun

function Engine.GetLastRun()
	return lastRun
end

-- Range fields per their "off" value: minima 0, maxima -1 (raids) or 0 (dungeon leader rating).
local RANGE_OFF = {
	minLeaderRating = 0, maxLeaderRating = 0,
	minMembers = 0, maxMembers = -1, maxTanks = -1, maxHealers = -1,
}

local function EffectiveSettings(settings, categoryID)
	local seasonSet = ns.Categories.GetSeasonGroupSet(categoryID)
	local effective = {}
	for k, v in pairs(settings) do
		effective[k] = v
	end
	-- Raids have no raid selection (the boss list covers the season's raids): never a raid filter.
	effective.activityGroups = categoryID == ns.Categories.RAIDS and {}
		or ns.Match.EffectiveGroups(settings.activityGroups, seasonSet)
	-- Excluded dungeons: only those still in the season filter (no invisible filter).
	if settings.excludedGroups then
		effective.excludedGroups = {}
		for groupID in pairs(settings.excludedGroups) do
			if seasonSet == nil or seasonSet[groupID] then
				effective.excludedGroups[groupID] = true
			end
		end
	end
	-- Boss marks: only the marks of the bosses the panel shows filter (no invisible filter); marks
	-- left from an earlier season's raids are ignored.
	for _, key in ipairs({ "aliveBosses", "deadBosses" }) do
		if settings[key] then
			effective[key] = {}
			for _, raid in ipairs(ns.Categories.GetBossListRaids()) do
				for bossID in pairs(settings[key]) do
					if raid.bossIDs and raid.bossIDs[bossID] then
						effective[key][bossID] = true
					end
				end
			end
		end
	end
	if ns.Settings.Profile().showRanges == false then
		-- Ranges section hidden: no invisible filter (saved values are kept for when it's shown again)
		for key, off in pairs(RANGE_OFF) do
			if effective[key] ~= nil then
				effective[key] = off
			end
		end
	end
	return effective
end

local function Pass(run, ids, settings, categoryID)
	if Engine.debugBreak then
		error("LFG Spyglass debug: forced filter error")
	end
	local player = ns.Snapshot.GetPlayerContext()
	player.signUpRoles = ns.Snapshot.SignUpRoles()
	local classUtility = ns.ClassUtility
	local effective = EffectiveSettings(settings, categoryID)

	run.filterActive = ns.Match.IsFilterActive(effective, player, classUtility)
	local sorting = settings.sort and settings.sort.field ~= "blizzard"
	local rowInfo = ns.Settings.Profile().rowInfo
	local isRaids = categoryID == ns.Categories.RAIDS
	local showRowInfo = rowInfo and (rowInfo.region or (isRaids and rowInfo.leaderProgress)
		or (not isRaids and (rowInfo.leaderRating or rowInfo.specs or rowInfo.leader)))
	if not run.filterActive and not sorting and not showRowInfo then
		run.state = "unfiltered"
		return
	end

	local visible = {}
	for i = 1, #ids do
		local snap = ns.Snapshot.Build(ids[i], i)
		run.snapshots[ids[i]] = snap
		if ns.Match.IsVisible(snap, effective, player, classUtility) then
			visible[#visible + 1] = snap
		end
	end
	-- Raids: the leader's progress from Raider.IO, read after filtering (never
	-- used to filter) for visible groups only, for the row info and the leader progress sort.
	local sortByLeader = settings.sort and settings.sort.field == "leaderProgress"
	if isRaids and (sortByLeader or (rowInfo and rowInfo.leaderProgress)) then
		ns.LeaderProgress.ResetCache()
		for i = 1, #visible do
			local snap = visible[i]
			if snap.readable then
				snap.leaderProgress = ns.LeaderProgress.For(snap.leaderName, snap.mapID)
				snap.leaderProgressRank = snap.leaderProgress and snap.leaderProgress.rank or nil
			end
		end
	end
	local ordered = ns.Sort.Order(visible, settings.sort)
	for i = 1, #ordered do
		run.visible[i] = ordered[i].resultID
	end
	run.state = "filtering"
end

function Engine:Run()
	queued = false
	local categoryID = ns.Categories.GetActive()
	local run = {
		state = "inactive",
		categoryID = categoryID,
		visible = {},
		snapshots = {}, -- resultID -> ResultSnapshot, for row info
		totalCount = 0,
		hiddenCount = 0,
	}

	if ns.Categories.IsFiltered(categoryID) then
		local profile = ns.Settings.Profile()
		local restricted, reason = ns.Restrictions:IsActive()
		if not profile.filterEnabled then
			run.state = "off"
		elseif restricted then
			run.state, run.pauseReason = "paused", reason
		else
			local ids, _, searching = ns.SafeRead.GetResultIDsInBlizzardOrder()
			if searching then
				run.state = "searching" -- a search (e.g. Refresh) is running; results come next
			elseif ids == nil then
				run.state, run.pauseReason = "paused", "restricted"
			elseif #ids == 0 then
				run.state = "noResults"
			else
				run.totalCount = #ids
				local started = ns.debug and debugprofilestop and debugprofilestop()
				local ok, err = pcall(Pass, run, ids, ns.Settings.ForCategory(categoryID), categoryID)
				if started then
					ns.Debug("Filter pass: %d results in %.2f ms", #ids, debugprofilestop() - started)
				end
				if not ok then
					run.state = "error"
					run.visible = {}
					ns.DebugOnce("engine-" .. tostring(err), "Filter error (showing stock list): %s", err)
				end
				if run.state == "filtering" then
					run.hiddenCount = run.totalCount - #run.visible
				end
			end
		end
	end

	lastRun = run
	self:SendMessage(ns.MSG.RunComplete, run)
	return run
end

function Engine:RequestRun()
	if queued then
		return
	end
	queued = true
	C_Timer.After(0, function()
		Engine:Run()
	end)
end

function Engine:OnEnable()
	ns.FrameMap.Hook("updateResultList", function()
		Engine:RequestRun()
	end)
	self:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED", "RequestRun")
	self:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED", "RequestRun")
	self:RegisterMessage(ns.MSG.RestrictionsChanged, "RequestRun")
	self:RegisterMessage(ns.MSG.ActiveCategoryChanged, "RequestRun")
	self:RegisterMessage(ns.MSG.ActivePanelChanged, "RequestRun")
	self:RegisterMessage(ns.MSG.SettingsChanged, "RequestRun")
end
