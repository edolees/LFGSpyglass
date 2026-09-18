-- Docks Raider.IO's player profile window (rating, dungeons done, item level, ...) to the right of
-- the LFG Spyglass filter panel instead of the Group Finder edge, where the two would overlap.
--
-- Raider.IO positions its profile through a frame named "RaiderIO_ProfileTooltipAnchor", placed
-- next to PVEFrame. We post-hook that frame's SetPoint: whenever Raider.IO anchors it to PVEFrame
-- while our panel is visible, we re-point it at the panel with the same offsets. When the panel
-- hides we restore Raider.IO's own point. Any other placement (dragged by the player, docked to
-- another addon, attached to a hovered row) is left alone. Raider.IO is optional: if it isn't
-- loaded, nothing happens.
local _, ns = ...

local ProfileDock = ns.NewModule("ProfileDock")

local anchorFrame -- Raider.IO's anchor frame, once found
local lastPoint -- the last point Raider.IO itself set: { point, relativeTo, relativePoint, x, y }
local applying = false

local function DockTarget()
	local panel = ns.FilterPanel and ns.FilterPanel.GetFrame()
	if panel and panel:IsVisible() then
		return panel
	end
	return nil
end

local function IsGroupFinderPoint(point)
	local pve = ns.FrameMap.Get("pve")
	return point ~= nil and pve ~= nil and (point.relativeTo == pve or point.relativeTo == "PVEFrame")
end

-- Re-apply Raider.IO's last point, redirected to our panel when appropriate.
function ProfileDock:Apply()
	if not (anchorFrame and lastPoint) then
		return
	end
	local target = IsGroupFinderPoint(lastPoint) and DockTarget() or nil
	applying = true
	local ok, err = pcall(function()
		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint(lastPoint.point, target or lastPoint.relativeTo, lastPoint.relativePoint, lastPoint.x, lastPoint.y)
	end)
	applying = false
	if not ok then
		ns.DebugOnce("profiledock-" .. tostring(err), "Raider.IO profile dock failed: %s", err)
	end
end

local function OnAnchorSetPoint(_, point, relativeTo, relativePoint, x, y)
	if applying then
		return
	end
	lastPoint = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
	if IsGroupFinderPoint(lastPoint) and DockTarget() then
		ProfileDock:Apply()
	end
end

-- Find Raider.IO's anchor and hook it once. Safe to call repeatedly.
function ProfileDock:TryHook()
	if anchorFrame then
		return true
	end
	local frame = ns.FrameMap.Get("raiderIOProfileAnchor")
	if type(frame) ~= "table" or type(frame.SetPoint) ~= "function" then
		return false
	end
	anchorFrame = frame
	hooksecurefunc(frame, "SetPoint", OnAnchorSetPoint)
	-- Capture where Raider.IO has already put it.
	if frame.GetPoint then
		local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
		if ok and point then
			lastPoint = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
		end
	end
	ns.Debug("Raider.IO profile dock active")
	self:Apply()
	return true
end

function ProfileDock:OnPanelVisibilityChanged()
	if self:TryHook() then
		self:Apply()
	end
end

function ProfileDock:OnEnable()
	self:TryHook()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "TryHook")
end
