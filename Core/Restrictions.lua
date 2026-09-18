-- Watches Blizzard's Midnight addon restrictions and combat lockdown.
-- While active, filtering pauses and the stock list is shown.
local _, ns = ...

local Restrictions = ns.NewModule("Restrictions")

-- Enum.AddOnRestrictionType member name (lowercased) -> reason key used by the UI.
local REASONS = {
	combat = "combat",
	encounter = "encounter",
	challengemode = "challengeMode",
	pvpmatch = "pvpMatch",
	map = "map",
	chat = "chat",
}

local function ReasonFor(enumName)
	return REASONS[string.lower(tostring(enumName))] or "restricted"
end

-- Returns active (boolean), reason (string or nil). API errors count as restricted.
function Restrictions:IsActive()
	if InCombatLockdown() then
		return true, "combat"
	end
	local api = C_RestrictedActions
	local types = Enum and Enum.AddOnRestrictionType
	if api and api.IsAddOnRestrictionActive and types then
		for name, value in pairs(types) do
			local ok, active = pcall(api.IsAddOnRestrictionActive, value)
			if not ok then
				return true, "restricted"
			end
			if active then
				return true, ReasonFor(name)
			end
		end
	end
	return false, nil
end

local lastActive, lastReason

function Restrictions:Check()
	local active, reason = self:IsActive()
	if active ~= lastActive or reason ~= lastReason then
		lastActive, lastReason = active, reason
		ns.Debug("Restrictions: %s (%s)", active and "active" or "clear", reason or "-")
		self:SendMessage(ns.MSG.RestrictionsChanged, active, reason)
	end
end

local function SafeRegister(self, event)
	local ok = pcall(self.RegisterEvent, self, event, "Check")
	if not ok then
		ns.DebugOnce("event-" .. event, "Restrictions: event %s unavailable", event)
	end
end

function Restrictions:OnEnable()
	SafeRegister(self, "ADDON_RESTRICTION_STATE_CHANGED")
	SafeRegister(self, "PLAYER_REGEN_DISABLED")
	SafeRegister(self, "PLAYER_REGEN_ENABLED")
	SafeRegister(self, "PLAYER_ENTERING_WORLD")
	self:Check()
end
