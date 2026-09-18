-- Secret-safe, read-only access to Group Finder data.
-- Every read is pcall-wrapped; secret or unreadable values come back as nil.
-- This module never writes to Blizzard tables.
local _, ns = ...

local SafeRead = ns.NewModule("SafeRead")

local issecretvalue = issecretvalue or function()
	return false
end
local canaccesstable = canaccesstable or function()
	return true
end

function SafeRead.IsReadable(value)
	if value == nil or issecretvalue(value) then
		return false
	end
	if type(value) == "table" and not canaccesstable(value) then
		return false
	end
	return true
end

local IsReadable = SafeRead.IsReadable

local function Index(tbl, key)
	return tbl[key]
end

-- Read tbl[key]; nil if the table or the value is not readable. Runs dozens of times per result
-- per filter pass, so the pcall goes through a shared function instead of a new closure.
function SafeRead.Field(tbl, key)
	if not IsReadable(tbl) then
		return nil
	end
	local ok, value = pcall(Index, tbl, key)
	if ok and IsReadable(value) then
		return value
	end
	return nil
end

local Field = SafeRead.Field

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, ...)
	if ok and IsReadable(value) then
		return value
	end
	return nil
end

function SafeRead.GetResultInfo(resultID)
	return Call(C_LFGList.GetSearchResultInfo, resultID)
end

function SafeRead.GetMemberCounts(resultID)
	return Call(C_LFGList.GetSearchResultMemberCounts, resultID)
end

-- Copy of an encounter list's names; errors on any unreadable entry (called through pcall).
local function ReadNames(encounters)
	local names = {}
	for i = 1, #encounters do
		local name = encounters[i]
		if not (IsReadable(name) and type(name) == "string") then
			error("unreadable")
		end
		names[i] = name
	end
	return names
end

-- Defeated bosses in a listing: Blizzard's defeated-encounter names (the list shown in the group
-- tooltip) as a new array of strings, {} when none, nil when it can't be read.
function SafeRead.GetEncounterNames(resultID)
	if not C_LFGList.GetSearchResultEncounterInfo then
		return nil
	end
	local ok, encounters = pcall(C_LFGList.GetSearchResultEncounterInfo, resultID)
	if not ok then
		return nil
	end
	if encounters == nil then
		return {} -- no bosses defeated
	end
	if not IsReadable(encounters) then
		return nil
	end
	local okRead, names = pcall(ReadNames, encounters)
	return okRead and names or nil
end

-- Number of bosses defeated, or nil when unknown.
function SafeRead.GetEncounterCount(resultID)
	local names = SafeRead.GetEncounterNames(resultID)
	return names and #names or nil
end

function SafeRead.GetPlayerInfo(resultID, memberIndex)
	return Call(C_LFGList.GetSearchResultPlayerInfo, resultID, memberIndex)
end

local groupIDByActivity = {}

function SafeRead.GetActivityGroupID(activityID)
	if not IsReadable(activityID) then
		return nil
	end
	local cached = groupIDByActivity[activityID]
	if cached ~= nil then
		return cached or nil
	end
	local info = Call(C_LFGList.GetActivityInfoTable, activityID)
	local groupID = Field(info, "groupFinderActivityGroupID")
	groupIDByActivity[activityID] = groupID or false
	return groupID
end

function SafeRead.GetActivityInfo(activityID)
	if not IsReadable(activityID) then
		return nil
	end
	return Call(C_LFGList.GetActivityInfoTable, activityID)
end

function SafeRead.GetActivityCategoryID(activityID)
	if not IsReadable(activityID) then
		return nil
	end
	return Field(Call(C_LFGList.GetActivityInfoTable, activityID), "categoryID")
end

-- Returns appStatus ("none" if unknown), pendingStatus (or nil).
function SafeRead.GetApplicationInfo(resultID)
	local ok, _, appStatus, pendingStatus = pcall(C_LFGList.GetApplicationInfo, resultID)
	if not ok then
		return "none", nil
	end
	if not IsReadable(appStatus) then
		appStatus = "none"
	end
	if not IsReadable(pendingStatus) then
		pendingStatus = nil
	end
	return appStatus, pendingStatus
end

-- Result IDs in Blizzard's final display order (results, then applications not in results),
-- read from LFGListFrame.SearchPanel after Blizzard has sorted them.
-- Returns ids (new array), totalResults, isSearching; ids == nil means "not readable".
function SafeRead.GetResultIDsInBlizzardOrder()
	local panel = ns.FrameMap.Get("searchPanel")
	if not IsReadable(panel) then
		return nil
	end
	local searching = Field(panel, "searching") and true or false
	local results = Field(panel, "results")
	if not results then
		return nil, 0, searching
	end

	local ids, seen = {}, {}
	local ok = pcall(function()
		for i = 1, #results do
			local id = results[i]
			if IsReadable(id) and not seen[id] then
				ids[#ids + 1] = id
				seen[id] = true
			end
		end
		local apps = Call(C_LFGList.GetApplications)
		if apps then
			for i = 1, #apps do
				local id = apps[i]
				if IsReadable(id) and not seen[id] then
					ids[#ids + 1] = id
					seen[id] = true
				end
			end
		end
	end)
	if not ok then
		return nil
	end
	local total = Field(panel, "totalResults")
	return ids, total or #results, searching
end

-- Category of the player's own active listing (activityIDs are NeverSecret per docs).
function SafeRead.GetActiveEntryCategory()
	local hasEntry = Call(C_LFGList.HasActiveEntryInfo)
	if not hasEntry then
		return nil
	end
	local info = Call(C_LFGList.GetActiveEntryInfo)
	local activityIDs = Field(info, "activityIDs")
	local activityID = Field(activityIDs, 1)
	return SafeRead.GetActivityCategoryID(activityID)
end
