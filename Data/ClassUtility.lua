-- Group fit class rules. PURE: no WoW API; unit-tested.
-- A class counts as bringing a buff if ANY of its specs can. Hunters therefore always count
-- as Bloodlust (Primal Rage needs a Ferocity pet; Marksmanship has Harrier's Cry) because a
-- listing does not tell us a hunter's pet or talents.
local _, ns = ...

local ClassUtility = {}
ns.ClassUtility = ClassUtility

ClassUtility.lastVerified = "2026-09-13 / 12.1.0"

ClassUtility.BLOODLUST = {
	SHAMAN = true, -- Bloodlust / Heroism
	MAGE = true, -- Time Warp
	EVOKER = true, -- Fury of the Aspects
	HUNTER = true, -- Primal Rage (Ferocity pet) / Harrier's Cry (Marksmanship)
}

ClassUtility.BATTLE_RES = {
	DRUID = true, -- Rebirth
	DEATHKNIGHT = true, -- Raise Ally
	WARLOCK = true, -- Soulstone
	PALADIN = true, -- Intercession
}

-- Whether a Group fit checkbox is offered to (and applies for) a player of this class.
function ClassUtility.AppliesTo(checkbox, classFile)
	if checkbox == "bloodlust" then
		return ClassUtility.BLOODLUST[classFile] == true
	elseif checkbox == "battleRes" then
		return ClassUtility.BATTLE_RES[classFile] == true
	elseif checkbox == "party" or checkbox == "hasTank" or checkbox == "hasHealer" or checkbox == "notDeclined"
		or checkbox == "hideClass" then
		return true -- these apply to every class
	end
	return false
end
