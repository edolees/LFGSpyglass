-- The ONLY place that names Blizzard Group Finder frames and functions.
-- Getters are nil-safe: a missing path returns nil, is logged once, and callers skip it.
local _, ns = ...

local FrameMap = ns.NewModule("FrameMap")

local SP = { "LFGListFrame", "SearchPanel" }

local function Sub(base, ...)
	local path = { unpack(base) }
	for i = 1, select("#", ...) do
		path[#path + 1] = (select(i, ...))
	end
	return path
end

local FRAMES = {
	pve = { "PVEFrame" },
	groupFinder = { "GroupFinderFrame" },
	lfgList = { "LFGListFrame" },
	categorySelection = { "LFGListFrame", "CategorySelection" },
	searchPanel = SP,
	searchScroll = Sub(SP, "ScrollBox"),
	searchScrollBar = Sub(SP, "ScrollBar"),
	signUpButton = Sub(SP, "SignUpButton"),
	filterButton = Sub(SP, "FilterButton"), -- anchor for the LFG Spyglass toggle button
	resultsInset = Sub(SP, "ResultsInset"),
	searchAutoComplete = Sub(SP, "AutoCompleteFrame"), -- search box suggestions: drop below them
	entryCreation = { "LFGListFrame", "EntryCreation" },
	applicationViewer = { "LFGListFrame", "ApplicationViewer" },
	applicationDialog = { "LFGListApplicationDialog" },
	-- Other addons (optional; nil when not loaded)
	raiderIOProfileAnchor = { "RaiderIO_ProfileTooltipAnchor" },
	raiderIO = { "RaiderIO" },
	encounterJournal = { "EncounterJournal" }, -- Blizzard's Encounter Journal (load on demand): read instanceID / IsShown only -- Raider.IO public interface: GetProfile, display only
}

local FUNCS = {
	-- post-hooked (hooksecurefunc only)
	updateResultList = "LFGListSearchPanel_UpdateResultList",
	setCategory = "LFGListSearchPanel_SetCategory",
	setActivePanel = "LFGListFrame_SetActivePanel",
	-- called (display / dialog only)
	searchEntryUpdate = "LFGListSearchEntry_Update", -- draws addon-owned template rows
	setTooltip = "LFGListUtil_SetSearchEntryTooltip",
	dialogShow = "LFGListApplicationDialog_Show",
	dialogUpdateRoles = "LFGListApplicationDialog_UpdateRoles", -- post-hooked: pre-tick sign-up roles
	dialogUpdateValidState = "LFGListApplicationDialog_UpdateValidState",
	canSelectResult = "LFGListSearchPanelUtil_CanSelectResult",
	activeQueueMessage = "LFGListUtil_GetActiveQueueMessage",
	isAppEmpowered = "LFGListUtil_IsAppEmpowered",
}

-- Keys for other addons' frames: missing is normal, so it isn't logged.
local OPTIONAL = { raiderIOProfileAnchor = true, raiderIO = true, encounterJournal = true }

-- Test-only simulation of a patch removing a frame (smoke test); never saved.
local broken = {}

function FrameMap.SetBroken(key, isBroken)
	broken[key] = isBroken or nil
end

local canaccesstable = canaccesstable or function()
	return true
end

function FrameMap.Get(key)
	local path = FRAMES[key]
	if not path then
		ns.DebugOnce("framemap-unknown-" .. tostring(key), "FrameMap: unknown key %s", key)
		return nil
	end
	if broken[key] then
		return nil
	end
	local node = _G[path[1]]
	for i = 2, #path do
		if type(node) ~= "table" or not canaccesstable(node) then
			node = nil
			break
		end
		node = node[path[i]]
	end
	if node == nil and not OPTIONAL[key] then
		ns.DebugOnce("framemap-missing-" .. key, "FrameMap: %s (%s) not found", key, table.concat(path, "."))
	end
	return node
end

function FrameMap.GetFunc(key)
	local name = FUNCS[key]
	local fn = name and _G[name]
	if type(fn) ~= "function" or broken[key] then
		ns.DebugOnce("framemap-func-" .. tostring(key), "FrameMap: function %s not found", tostring(name))
		return nil
	end
	return fn
end

-- Post-hook a Blizzard function by map key. Returns true if the hook was installed.
function FrameMap.Hook(key, handler)
	local name = FUNCS[key]
	if not (name and type(_G[name]) == "function") then
		ns.DebugOnce("framemap-hook-" .. tostring(key), "FrameMap: cannot hook %s", tostring(name))
		return false
	end
	hooksecurefunc(name, function(...)
		local ok, err = pcall(handler, ...)
		if not ok then
			ns.DebugOnce("hook-error-" .. key, "Hook %s failed: %s", name, err)
		end
	end)
	return true
end
