-- Defers layout changes (size/anchors) that must not happen in combat.
local _, ns = ...

local CombatQueue = ns.NewModule("CombatQueue")

local queue = {}

function CombatQueue:Run(fn)
	if not InCombatLockdown() then
		local ok, err = pcall(fn)
		if not ok then
			ns.DebugOnce("combatqueue-" .. tostring(err), "CombatQueue: %s", err)
		end
		return
	end
	queue[#queue + 1] = fn
end

function CombatQueue:PLAYER_REGEN_ENABLED()
	local pending = queue
	queue = {}
	for i = 1, #pending do
		self:Run(pending[i])
	end
end

function CombatQueue:OnEnable()
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
end
