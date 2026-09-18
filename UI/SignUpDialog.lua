-- Pre-ticks the player's "Sign up as" roles in Blizzard's application dialog. Blizzard fills the dialog's role checkboxes from GetLFGRoles; right after that
-- (post-hook on LFGListApplicationDialog_UpdateRoles) we set the checkboxes the player can use to
-- their LFG Spyglass roles and let Blizzard re-check the Sign Up button. The player still clicks Sign Up.
-- We never call SetLFGRoles, so the player's saved Group Finder / Dungeon Finder roles don't change.
local _, ns = ...

local SignUpDialog = ns.NewModule("SignUpDialog")

local BUTTON_FOR_ROLE = { TANK = "TankButton", HEALER = "HealerButton", DAMAGER = "DamagerButton" }

local function ApplyRoles(dialog)
	if not (ns.Settings.Profile().filterEnabled and ns.Categories.IsFiltered(ns.Categories.GetActive())) then
		return
	end
	if ns.Restrictions:IsActive() then
		return
	end
	local roles = ns.Snapshot.SignUpRoles()
	if #roles == 0 then
		return
	end
	local wanted = {}
	for _, role in ipairs(roles) do
		wanted[role] = true
	end
	local changed = false
	for role, key in pairs(BUTTON_FOR_ROLE) do
		local roleButton = dialog[key]
		local check = type(roleButton) == "table" and roleButton.CheckButton or nil
		if type(check) == "table" and roleButton:IsShown() then
			check:SetChecked(wanted[role] == true)
			changed = true
		end
	end
	local updateValidState = changed and ns.FrameMap.GetFunc("dialogUpdateValidState")
	if updateValidState then
		pcall(updateValidState, dialog)
	end
end

function SignUpDialog:OnEnable()
	ns.FrameMap.Hook("dialogUpdateRoles", function(dialog)
		if dialog == ns.FrameMap.Get("applicationDialog") then
			ApplyRoles(dialog)
		end
	end)
end
