-- LFG Spyglass: addon object, private namespace, module registry and local debug output.
-- Constitution: no chat/addon messages are ever *sent*; debug output is local print() only.
local addonName, ns = ...

local addon = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0")
ns.addon = addon
ns.L = LibStub("AceLocale-3.0"):GetLocale(addonName)

-- Internal messages (AceEvent SendMessage/RegisterMessage) used between modules.
ns.MSG = {
	RestrictionsChanged = "LFGSpyglass_RestrictionsChanged", -- (active, reason)
	ActiveCategoryChanged = "LFGSpyglass_ActiveCategoryChanged", -- (categoryID)
	ActivePanelChanged = "LFGSpyglass_ActivePanelChanged", -- (panelKey)
	SettingsChanged = "LFGSpyglass_SettingsChanged", -- ()
	RunComplete = "LFGSpyglass_RunComplete", -- (run)
}

-- Module registry: every module is an AceAddon module with AceEvent embedded,
-- also exposed as ns.<Name> for direct access from other files.
function ns.NewModule(name)
	local module = addon:NewModule(name, "AceEvent-3.0")
	ns[name] = module
	return module
end

-- Debugging (local chat frame only). There is no in-game toggle; tests set ns.debug directly.
ns.debug = false

local PREFIX = "|cff3fa7f5LFG Spyglass|r "

local function Format(fmt, ...)
	local n = select("#", ...)
	if n == 0 then
		return tostring(fmt)
	end
	local args = {}
	for i = 1, n do
		args[i] = tostring((select(i, ...)))
	end
	local ok, text = pcall(string.format, fmt, unpack(args, 1, n))
	return ok and text or tostring(fmt)
end

function ns.Print(fmt, ...)
	print(PREFIX .. Format(fmt, ...))
end

function ns.Debug(fmt, ...)
	if ns.debug then
		print(PREFIX .. "|cff9d9d9d[debug]|r " .. Format(fmt, ...))
	end
end

local reported = {}

-- Log a problem once per session (only while debug mode is on).
function ns.DebugOnce(key, fmt, ...)
	if not ns.debug or reported[key] then
		return
	end
	reported[key] = true
	ns.Debug(fmt, ...)
end

-- One-time notice when another Group Finder filter is loaded.
local OTHER_FILTER_ADDONS = { "PremadeGroupsFilter", "BoringLFGFilter" }

function addon:OnEnable()
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
	local notices = ns.Settings.Profile().notices
	if not isLoaded or notices.otherFilterAddonShown then
		return
	end
	for _, name in ipairs(OTHER_FILTER_ADDONS) do
		local ok, loaded = pcall(isLoaded, name)
		if ok and loaded then
			ns.Print(ns.L["%s is also loaded. Results may be filtered by both addons; consider using one filter at a time."], name)
			notices.otherFilterAddonShown = true
			return
		end
	end
end
