-- Addon-owned results list drawn over Blizzard's search results.
-- Blizzard's ScrollBox and SearchPanel.results are only READ, never written. Whenever the list
-- is not in use (other category, restricted, searching, no results, error) it hides and the
-- untouched Blizzard list is shown again.
--
-- Rows are addon-owned instances of Blizzard's own LFGListSearchEntryTemplate, drawn by
-- Blizzard's LFGListSearchEntry_Update, so they look exactly like stock rows and keep Blizzard's
-- own Cancel button (clicked by the player) and application timer.
--
-- Shows Filter/Engine.lua results: visible only while the engine state is "filtering".
local _, ns = ...

local ResultList = ns.NewModule("ResultList")

local NAME_COLOR = "|cffffffff" -- member names in the tooltip
local ROW_TEMPLATE = "LFGListSearchEntryTemplate"

-- `list` is the addon container. Blizzard's row update reads `list.selectedResult`
-- (row -> ScrollTarget -> ScrollBox -> list), which is an addon-owned frame.
local list, scrollBox, signUpButton, watcher, emptyState
local selectedResultID
local currentRun
local blizzardAlpha -- { [frame] = previous alpha } while Blizzard's list is hidden
local initializedRows = setmetatable({}, { __mode = "k" })
local rowInfoParts = setmetatable({}, { __mode = "k" }) -- row -> { rating, flag, region }

local BLIZZARD_LIST_KEYS = { "searchScroll", "searchScrollBar", "signUpButton" }

local function SetBlizzardListHidden(hidden)
	if hidden and not blizzardAlpha then
		blizzardAlpha = {}
		for _, key in ipairs(BLIZZARD_LIST_KEYS) do
			local frame = ns.FrameMap.Get(key)
			if frame then
				blizzardAlpha[frame] = frame:GetAlpha()
				frame:SetAlpha(0)
			end
		end
	elseif not hidden and blizzardAlpha then
		for frame, alpha in pairs(blizzardAlpha) do
			frame:SetAlpha(alpha)
		end
		blizzardAlpha = nil
	end
end

-- Can this group be selected (and signed up for)? Blizzard's own rule, plus one exception: a group
-- whose application expired ("timedout") or that delisted while the player had applied
-- ("declined_delisted", Blizzard remembers it per group even after a relist) may be selected again,
-- as long as nothing is pending, it is listed right now and it didn't decline the player. The
-- application still goes through Blizzard's dialog and the player's click on its Sign Up button.
local function CanSelect(resultID)
	local canSelect = ns.FrameMap.GetFunc("canSelectResult")
	if not canSelect then
		return true
	end
	local ok, allowed = pcall(canSelect, resultID)
	if not ok then
		return false
	end
	if allowed then
		return true
	end
	local appStatus, pendingStatus = ns.SafeRead.GetApplicationInfo(resultID)
	if pendingStatus ~= nil then
		return false
	end
	local info = ns.SafeRead.GetResultInfo(resultID)
	if not info or ns.SafeRead.Field(info, "isDelisted") ~= false then
		return false -- gone from the list: nothing to apply to
	end
	local partyGUID = ns.SafeRead.Field(info, "partyGUID")
	local declines = ns.SafeRead.Field(ns.FrameMap.Get("lfgList"), "declines")
	local remembered = partyGUID and declines and ns.SafeRead.Field(declines, partyGUID) or nil
	if remembered == "declined" or remembered == "declined_full" then
		return false -- the group really declined the player
	end
	local retryable = appStatus == "timedout" or appStatus == "declined_delisted"
		or remembered == "declined_delisted"
	return retryable == true
end

-- Why the addon Sign Up control is disabled (nil = allowed). Mirrors Blizzard's own checks,
-- using read-only calls only.
local function SignUpBlockReason(resultID)
	if not resultID then
		return LFG_LIST_SELECT_A_SEARCH_RESULT
	end
	if ns.Restrictions:IsActive() then
		return LFG_LIST_SELECT_A_SEARCH_RESULT
	end
	if not CanSelect(resultID) then
		return LFG_LIST_SELECT_A_SEARCH_RESULT
	end
	local queueMessage = ns.FrameMap.GetFunc("activeQueueMessage")
	if queueMessage then
		local ok, message = pcall(queueMessage, true)
		if ok and message then
			return message
		end
	end
	local isEmpowered = ns.FrameMap.GetFunc("isAppEmpowered")
	if isEmpowered then
		local ok, empowered = pcall(isEmpowered)
		if ok and not empowered then
			return LFG_LIST_APP_UNEMPOWERED
		end
	end
	local okApps, _, numActive = pcall(C_LFGList.GetNumApplications)
	if okApps and MAX_LFG_LIST_APPLICATIONS and (numActive or 0) >= MAX_LFG_LIST_APPLICATIONS then
		return string.format(LFG_LIST_HIT_MAX_APPLICATIONS, MAX_LFG_LIST_APPLICATIONS)
	end
	local okRoles, tank, healer, dps = pcall(C_LFGList.GetAvailableRoles)
	if okRoles and not (tank or healer or dps) then
		return LFG_LIST_MUST_CHOOSE_SPEC
	end
	return nil
end

local function UpdateSignUpButton()
	if not signUpButton then
		return
	end
	local reason = SignUpBlockReason(selectedResultID)
	signUpButton:SetEnabled(reason == nil)
	signUpButton.tooltipText = reason
end

-- Open Blizzard's application dialog; the player's click on its Sign Up sends the application.
local function OpenSignUp(resultID)
	if SignUpBlockReason(resultID) then
		return
	end
	local dialog = ns.FrameMap.Get("applicationDialog")
	local show = ns.FrameMap.GetFunc("dialogShow")
	if dialog and show then
		ns.Debug("Opening application dialog for result %s", resultID)
		show(dialog, resultID)
	end
end

local function SetSelected(resultID)
	selectedResultID = resultID
	if list then
		list.selectedResult = resultID
	end
end

local function RowOnClick(row, button)
	if button == "RightButton" then
		-- Blizzard's own row menu (whisper the leader, report the group or its advertisement), opened
		-- on the player's click, exactly as in the stock list. Every entry is Blizzard's.
		local contextMenu = ns.FrameMap.GetFunc("searchEntryContextMenu")
		if contextMenu then
			local ok, err = pcall(contextMenu, row)
			if not ok then
				ns.DebugOnce("row-menu-" .. tostring(err), "Row menu failed: %s", err)
			end
		end
		return
	end
	if button ~= "LeftButton" then
		return
	end
	if CanSelect(row.resultID) and selectedResultID ~= row.resultID then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		SetSelected(row.resultID)
		ResultList:Render(currentRun)
	end
end

local function RowOnDoubleClick(row)
	SetSelected(row.resultID)
	OpenSignUp(row.resultID)
end

-- Blizzard's tooltip lists each member as a role icon plus class and spec, without a name. When the
-- client does send names (it doesn't always), LFG Spyglass puts the name in place of the class and
-- spec, in the member's class color and with their realm, keeping the role icon. The game only
-- includes a realm for players from another one, so the player's own realm is filled in for the
-- rest. Members come in index order in both Blizzard's list and ours. If the tooltip has no member lines (raid-sized groups show counts
-- instead), the names go in a "Members" section of our own. Nothing is read or written unless it is
-- a readable string.
local ownRealm -- read once

local function OwnRealm()
	if ownRealm == nil then
		local ok, realm = pcall(GetNormalizedRealmName)
		if not (ok and type(realm) == "string" and realm ~= "") then
			ok, realm = pcall(GetRealmName)
		end
		ownRealm = (ok and type(realm) == "string" and realm:gsub("%s+", "")) or false
	end
	return ownRealm or nil
end

local function MemberNameText(resultID, index)
	local member = ns.SafeRead.GetPlayerInfo(resultID, index)
	local name = member and ns.SafeRead.Field(member, "name")
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if not name:find("-", 1, true) then
		local realm = OwnRealm()
		if realm then
			name = name .. "-" .. realm
		end
	end
	local classFile = ns.SafeRead.Field(member, "classFilename")
	local color = type(classFile) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if color and color.WrapTextInColorCode then
		return color:WrapTextInColorCode(name)
	end
	return NAME_COLOR .. name .. "|r"
end

-- The tooltip line that starts Blizzard's member list, or nil when it doesn't have one.
local function MembersLineIndex()
	if not (MEMBERS_COLON and GameTooltip.NumLines) then
		return nil
	end
	for i = 1, GameTooltip:NumLines() do
		local line = _G["GameTooltipTextLeft" .. i]
		local text = line and line.GetText and line:GetText()
		if ns.SafeRead.IsReadable(text) and text == MEMBERS_COLON then
			return i
		end
	end
	return nil
end

-- Dungeons only: a five-man tooltip has one line per member, and the names fit. Raid tooltips list
-- member counts for up to 30 people, so they stay as Blizzard draws them.
local function AddMemberNames(resultID)
	if ns.Settings.Profile().rowInfo.memberNames == false then
		return
	end
	if ns.Categories.GetActive() ~= ns.Categories.DUNGEONS then
		return
	end
	local info = ns.SafeRead.GetResultInfo(resultID)
	local count = info and ns.SafeRead.Field(info, "numMembers")
	if type(count) ~= "number" or count < 1 or count > 40 then
		return
	end
	local membersLine = MembersLineIndex()
	if membersLine then
		-- Blizzard drew one line per member, in index order: the class and spec make way for the name,
		-- and the line keeps the role icon it starts with.
		for index = 1, count do
			local line = _G["GameTooltipTextLeft" .. (membersLine + index)]
			local existing = line and line.GetText and line:GetText()
			local name = MemberNameText(resultID, index)
			if name and ns.SafeRead.IsReadable(existing) and type(existing) == "string" then
				local roleIcon = existing:match("^(|A.-|a%s*)") or ""
				line:SetText(roleIcon .. name)
			end
		end
		return
	end
	local lines = {}
	for index = 1, count do
		lines[#lines + 1] = MemberNameText(resultID, index)
	end
	if #lines == 0 then
		return -- the client sent no names: Blizzard's own tooltip is all there is
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(MEMBERS_COLON or L["Members"], 1, 1, 1)
	for _, line in ipairs(lines) do
		GameTooltip:AddLine(line)
	end
end

local function RowOnEnter(row)
	if type(row.Highlight) == "table" then
		row.Highlight:Show()
	end
	if ns.Restrictions:IsActive() then
		return
	end
	local setTooltip = ns.FrameMap.GetFunc("setTooltip")
	if setTooltip and row.resultID then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT", 25, 0)
		pcall(setTooltip, GameTooltip, row.resultID)
		local ok, err = pcall(AddMemberNames, row.resultID)
		if not ok then
			ns.DebugOnce("row-names-" .. tostring(err), "Member names failed: %s", err)
		end
		GameTooltip:Show()
	end
end

local function RowOnLeave(row)
	if type(row.Highlight) == "table" then
		row.Highlight:Hide()
	end
	GameTooltip_Hide()
end

-- Leader rating + region flag/tag on the row's third line, after Blizzard's playstyle text.
-- Parts are addon-created regions on the addon-owned row.
local function RowInfoParts(row)
	local parts = rowInfoParts[row]
	if parts then
		return parts
	end
	parts = {}
	parts.rating = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	parts.progress = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall") -- raids: leader progress
	parts.heroic = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall") -- raids: Heroic next to Mythic
	parts.main = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall") -- raids: main's progress
	parts.flag = row:CreateTexture(nil, "ARTWORK")
	parts.flag:SetSize(16, 11)
	parts.flag:SetTexCoord(0, 1, 0.17, 0.83) -- Twemoji flags have empty space above and below
	parts.region = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	rowInfoParts[row] = parts
	return parts
end

-- Blizzard's item quality colours for raid difficulty: Normal uncommon, Heroic rare, Mythic epic.
local DIFFICULTY_QUALITY = { [1] = 2, [2] = 3, [3] = 4 }

local function DifficultyColor(difficulty)
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[DIFFICULTY_QUALITY[difficulty] or -1]
	if color and color.r then
		return color.r, color.g, color.b
	end
	return HIGHLIGHT_FONT_COLOR:GetRGB()
end

-- Right edge the row info may reach before Blizzard's member icons / role counts.
local ROW_INFO_RIGHT_GAP = 130

local function UpdateRowInfo(row, resultID)
	local parts = RowInfoParts(row)
	local snap = currentRun and currentRun.snapshots and currentRun.snapshots[resultID]
	local settings = ns.Settings.Profile().rowInfo or {}
	local isRaids = currentRun and currentRun.categoryID == ns.Categories.RAIDS

	local anchor = type(row.Playstyle) == "table" and row.Playstyle or nil
	local x = 8
	if not anchor or (anchor.GetText and (anchor:GetText() or "") == "") then
		anchor = type(row.ActivityName) == "table" and row.ActivityName or nil
		x = 0
	end

	local last = nil
	local function Place(region, gap)
		region:ClearAllPoints()
		if last then
			region:SetPoint("LEFT", last, "RIGHT", gap, 0)
		elseif anchor == row.Playstyle then
			region:SetPoint("LEFT", anchor, "RIGHT", x, 0)
		elseif anchor then
			region:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -1)
		else
			region:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 5)
		end
		last = region
	end

	local rating = snap and snap.readable and snap.leaderRating or 0
	if settings.leaderRating and rating > 0 and not isRaids then
		parts.rating:SetText(tostring(rating))
		local color = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
			and C_ChallengeMode.GetDungeonScoreRarityColor(rating)
		if color and color.GetRGB then
			parts.rating:SetTextColor(color:GetRGB())
		else
			parts.rating:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
		end
		Place(parts.rating, 0)
		parts.rating:Show()
	else
		parts.rating:Hide()
	end

	-- Raids: the leader's progress in this raid from Raider.IO (display only), and the main's if better
	local progress = isRaids and settings.leaderProgress and snap and snap.leaderProgress or nil
	parts.progress:Hide()
	parts.heroic:Hide()
	parts.main:Hide()
	if progress and progress.text then
		parts.progress:SetText(progress.text)
		parts.progress:SetTextColor(DifficultyColor(progress.difficulty))
		Place(parts.progress, 0)
		parts.progress:Show()
		if progress.heroic then
			parts.heroic:SetText(progress.heroic)
			parts.heroic:SetTextColor(DifficultyColor(2))
			Place(parts.heroic, 5)
			parts.heroic:Show()
		end
	end
	local region = settings.region and snap and ns.Regions.ForLeader(snap.leaderName) or nil
	if region then
		local texture = ns.Regions.FlagTexture(region.flag)
		if texture then
			parts.flag:SetTexture(texture)
			Place(parts.flag, 6)
			parts.flag:Show()
		else
			parts.flag:Hide()
		end
		parts.region:SetText(region.tag)
		Place(parts.region, texture and 3 or 6)
		parts.region:Show()
	else
		parts.flag:Hide()
		parts.region:Hide()
	end

	-- Raids: the main's progress last, left out if it would reach Blizzard's member display.
	if progress and progress.main then
		parts.main:SetText(string.format("%s %s", ns.L["main"], progress.main))
		parts.main:SetTextColor(DifficultyColor(progress.mainDifficulty))
		Place(parts.main, 6)
		parts.main:Show()
		local okFit, textRight, rowRight = pcall(function()
			return parts.main:GetRight(), row:GetRight()
		end)
		if okFit and type(textRight) == "number" and type(rowRight) == "number" and textRight > rowRight - ROW_INFO_RIGHT_GAP then
			parts.main:Hide()
		end
	end
end

-- Member icons.
-- Show spec role ON: our strip replaces the row's Blizzard icons, in the same place and order as
-- Blizzard (tanks, healers, damage, then empty slots): spec icon + role badge, crown on the leader.
-- Show spec role OFF: Blizzard's own icons are left exactly as Blizzard drew them; Show who's
-- leader only adds a crown above Blizzard's icon that matches the leader's class and role.
local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
local ROLE_ATLAS = {
	TANK = "groupfinder-icon-role-micro-tank",
	HEALER = "groupfinder-icon-role-micro-heal",
	DAMAGER = "groupfinder-icon-role-micro-dps",
}
local CROWN_ATLAS = "groupfinder-icon-leader"
-- Geometry copied from Blizzard's LFGListGroupDataDisplayTemplate / ClassRoleTemplate: 125x24
-- display anchored to the row's right edge; icons 18x18 spaced 18px apart (center to center), the
-- rightmost 12px in from the right; class circle 16x16. Crown is smaller than the tooltip's 14x9.
local MAX_SLOTS, SLOT_SIZE, SLOT_STEP, SLOT_RIGHT_INSET, CIRCLE_SIZE = 5, 18, 18, 12, 16
local CROWN_WIDTH, CROWN_HEIGHT = 11, 7
local BADGE_SIZE = 9
local memberStrips = setmetatable({}, { __mode = "k" })
local leaderCrowns = setmetatable({}, { __mode = "k" })

local function MemberStrip(row)
	local strip = memberStrips[row]
	if strip then
		return strip
	end
	strip = CreateFrame("Frame", nil, row)
	if type(row.DataDisplay) == "table" then
		strip:SetAllPoints(row.DataDisplay)
	else
		strip:SetSize(125, 24)
		strip:SetPoint("RIGHT", row, "RIGHT", 0, -1)
	end
	strip.slots = {}
	for i = 1, MAX_SLOTS do
		-- slots[1] is the leftmost; Blizzard numbers its icons from the right
		local fromRight = MAX_SLOTS - i
		local slot = CreateFrame("Frame", nil, strip)
		slot:SetSize(SLOT_SIZE, SLOT_SIZE)
		slot:SetPoint("RIGHT", strip, "RIGHT", -SLOT_RIGHT_INSET - fromRight * SLOT_STEP, 0)

		slot.icon = slot:CreateTexture(nil, "ARTWORK", nil, 1)
		slot.icon:SetSize(CIRCLE_SIZE, CIRCLE_SIZE)
		slot.icon:SetPoint("CENTER")
		slot.mask = slot:CreateMaskTexture()
		slot.mask:SetAllPoints(slot.icon)
		slot.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		slot.icon:AddMaskTexture(slot.mask)

		slot.circle = slot:CreateTexture(nil, "ARTWORK", nil, 1) -- class circle (unknown spec)
		slot.circle:SetSize(CIRCLE_SIZE, CIRCLE_SIZE)
		slot.circle:SetPoint("CENTER")

		slot.empty = slot:CreateTexture(nil, "ARTWORK", nil, 3) -- open spot, like RoleIconWithBackground
		slot.empty:SetAllPoints()

		slot.role = slot:CreateTexture(nil, "OVERLAY")
		slot.role:SetSize(BADGE_SIZE, BADGE_SIZE)
		slot.role:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 2, -2)

		slot.crown = slot:CreateTexture(nil, "OVERLAY")
		slot.crown:SetSize(CROWN_WIDTH, CROWN_HEIGHT)
		slot.crown:SetPoint("BOTTOM", slot, "TOP", 0, -2)
		slot.crown:SetAtlas(CROWN_ATLAS)
		strip.slots[i] = slot
	end
	memberStrips[row] = strip
	return strip
end

-- A crown placed above one of Blizzard's own member icons (no textures added to Blizzard's icons).
local function LeaderCrown(row)
	local crown = leaderCrowns[row]
	if crown then
		return crown
	end
	crown = CreateFrame("Frame", nil, row)
	crown:SetSize(CROWN_WIDTH, CROWN_HEIGHT)
	crown:SetFrameLevel(row:GetFrameLevel() + 10)
	crown.texture = crown:CreateTexture(nil, "OVERLAY")
	crown.texture:SetAllPoints()
	crown.texture:SetAtlas(CROWN_ATLAS)
	leaderCrowns[row] = crown
	return crown
end

-- Members of a result sorted like Blizzard's icons, or nil if any member is unreadable.
local function ReadMembers(resultID, numMembers)
	if type(numMembers) ~= "number" or numMembers < 1 then
		return nil
	end
	local byRole = { TANK = {}, HEALER = {}, DAMAGER = {} }
	for i = 1, numMembers do
		local info = ns.SafeRead.GetPlayerInfo(resultID, i)
		local classFile = ns.SafeRead.Field(info, "classFilename")
		local role = ns.SafeRead.Field(info, "assignedRole")
		if not (classFile and byRole[role]) then
			return nil
		end
		local list = byRole[role]
		list[#list + 1] = {
			classFile = classFile,
			role = role,
			specName = ns.SafeRead.Field(info, "specName"),
			isLeader = ns.SafeRead.Field(info, "isLeader") == true,
		}
	end
	local members = {}
	for _, role in ipairs(ROLE_ORDER) do
		for _, member in ipairs(byRole[role]) do
			members[#members + 1] = member
		end
	end
	return members
end

-- Role tokens inside Blizzard's role atlas names (micro, borderless and with-background variants).
local ROLE_TOKEN = { TANK = "tank", HEALER = "heal", DAMAGER = "dps" }

-- Atlas names are case-insensitive in WoW and GetAtlas() may return them lowercased.
local function AtlasOf(texture)
	if type(texture) ~= "table" or type(texture.GetAtlas) ~= "function" then
		return nil
	end
	local ok, atlas = pcall(texture.GetAtlas, texture)
	return ok and type(atlas) == "string" and atlas:lower() or nil
end

local function IsShownTexture(texture)
	return type(texture) == "table" and texture:IsShown()
end

-- Blizzard's icon on this row for the leader, or nil. Matches class circle + role; if the leader is
-- the only member with their role, the role alone is enough.
local function BlizzardIconFor(row, leader, roleCount)
	local display = type(row.DataDisplay) == "table" and row.DataDisplay or nil
	local enumerate = display and type(display.Enumerate) == "table" and display.Enumerate or nil
	if not (enumerate and enumerate:IsShown() and type(enumerate.Icons) == "table") then
		return nil
	end
	local classAtlas = ("groupfinder-icon-class-color-" .. leader.classFile):lower()
	local roleToken = ROLE_TOKEN[leader.role]
	local roleOnlyMatch
	for _, icon in ipairs(enumerate.Icons) do
		if icon:IsShown() then
			local circle = IsShownTexture(icon.ClassCircle) and AtlasOf(icon.ClassCircle) or nil
			local role = (IsShownTexture(icon.RoleIcon) and AtlasOf(icon.RoleIcon))
				or (IsShownTexture(icon.RoleIconWithBackground) and AtlasOf(icon.RoleIconWithBackground)) or nil
			local roleMatches = role ~= nil and roleToken ~= nil and role:find(roleToken, 1, true) ~= nil
			if roleMatches and circle == classAtlas then
				return icon
			end
			if roleMatches and not roleOnlyMatch then
				roleOnlyMatch = icon
			end
		end
	end
	if roleOnlyMatch and roleCount == 1 then
		return roleOnlyMatch
	end
	if ns.debug then
		local seen = {}
		for n, icon in ipairs(enumerate.Icons) do
			seen[#seen + 1] = n .. "=" .. tostring(AtlasOf(icon.ClassCircle)) .. "/" .. tostring(AtlasOf(icon.RoleIcon) or AtlasOf(icon.RoleIconWithBackground))
		end
		ns.DebugOnce("crown-" .. tostring(row.resultID), "Leader crown: no Blizzard icon for %s %s (icons: %s)",
			leader.classFile, leader.role, table.concat(seen, ", "))
	end
	return nil
end

local function UpdateMemberStrip(row, snap, settings)
	local strip, crown = memberStrips[row], leaderCrowns[row]
	if strip then
		strip:Hide()
	end
	if crown then
		crown:Hide()
	end
	-- Rows with an application (pending, invited, declined...) show Blizzard's status text there.
	local isApplication = snap ~= nil and ((snap.appStatus ~= nil and snap.appStatus ~= "none") or snap.pendingStatus ~= nil)
	if isApplication or not (snap and snap.readable) or not (settings.specs or settings.leader) then
		return -- Blizzard's own icons, as Blizzard's row update drew them
	end
	if (currentRun and currentRun.categoryID ~= ns.Categories.DUNGEONS) or (snap.numMembers or 0) > MAX_SLOTS then
		return -- raid rows: Blizzard's role counts stay (spec icons and crown are for 5-player groups)
	end
	local members = ReadMembers(row.resultID, snap.numMembers)
	if not members then
		return
	end

	if not settings.specs then
		-- Blizzard's icons stay; only add the crown above the leader's icon.
		local roleCounts = {}
		for _, member in ipairs(members) do
			roleCounts[member.role] = (roleCounts[member.role] or 0) + 1
		end
		for _, member in ipairs(members) do
			if member.isLeader then
				local icon = BlizzardIconFor(row, member, roleCounts[member.role])
				if icon then
					crown = LeaderCrown(row)
					crown:SetFrameLevel(math.max(row:GetFrameLevel(), icon:GetFrameLevel()) + 5)
					crown:ClearAllPoints()
					crown:SetPoint("BOTTOM", icon, "TOP", 0, -2)
					crown:Show()
				end
				break
			end
		end
		return
	end

	strip = MemberStrip(row)
	if type(row.DataDisplay) == "table" then
		row.DataDisplay:Hide()
	end
	local delisted = snap.isDelisted
	for i, slot in ipairs(strip.slots) do
		local member = members[i]
		slot:Show()
		slot.crown:SetShown(member ~= nil and settings.leader and member.isLeader or false)
		if member then
			slot.empty:Hide()
			local specIcon = ns.Specs.IconFor(member.classFile, member.specName)
			if specIcon then
				slot.icon:SetTexture(specIcon)
				slot.icon:Show()
				slot.circle:Hide()
			else
				-- Unknown spec: same class circle Blizzard would show for this member.
				slot.icon:Hide()
				slot.circle:SetAtlas("groupfinder-icon-class-color-" .. member.classFile, false)
				slot.circle:Show()
			end
			slot.role:SetAtlas(ROLE_ATLAS[member.role], false)
			slot.role:Show()
		else
			slot.icon:Hide()
			slot.circle:Hide()
			slot.empty:SetAtlas("groupfinder-icon-emptyslot", false)
			slot.empty:Show()
			slot.role:Hide()
		end
		for _, texture in ipairs({ slot.icon, slot.circle, slot.empty, slot.role }) do
			texture:SetDesaturated(delisted)
			texture:SetAlpha(delisted and 0.5 or 1)
		end
	end
	strip:Show()
end

-- Blizzard remembers a delisting as a decline for the whole session, so its row update paints a
-- relisted group as "Declined" (red name, no group data, no selection). Nobody declined the player
-- and the group can be applied to again, so LFG Spyglass's own rows are put back to the normal
-- look. Only rows the addon created are touched; Blizzard's own list is never changed.
local function ClearStaleDecline(row, snap)
	if not (snap and snap.wasDelisted and not snap.declined and not snap.isDelisted and snap.pendingStatus == nil) then
		return
	end
	row.isApplication = false
	for _, key in ipairs({ "PendingLabel", "ExpirationTime", "CancelButton", "Spinner" }) do
		local part = row[key]
		if type(part) == "table" and part.Hide then
			part:Hide()
		end
	end
	for _, key in ipairs({ "ResultBG", "DataDisplay" }) do
		local part = row[key]
		if type(part) == "table" and part.Show then
			part:Show()
		end
	end
	if type(row.Name) == "table" and row.Name.SetTextColor and NORMAL_FONT_COLOR then
		row.Name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
	end
	if type(row.ActivityName) == "table" and row.ActivityName.SetTextColor and GRAY_FONT_COLOR then
		row.ActivityName:SetTextColor(GRAY_FONT_COLOR:GetRGB())
	end
	-- Blizzard forced the selection off for an "application" row: give it the normal highlight.
	local selected = selectedResultID == row.resultID
	row.isSelected = selected
	if type(row.BackgroundTexture) == "table" then
		if selected then
			row.BackgroundTexture:SetAtlas("groupfinder-highlightbar-yellow")
			row.BackgroundTexture:Show()
		else
			row.BackgroundTexture:Hide()
		end
	end
end

local function InitRow(row, elementData)
	if not initializedRows[row] then
		initializedRows[row] = true
		-- Replace the template's click/hover scripts: stock ones select on Blizzard's SearchPanel.
		row:SetScript("OnClick", RowOnClick)
		row:SetScript("OnDoubleClick", RowOnDoubleClick)
		row:SetScript("OnEnter", RowOnEnter)
		row:SetScript("OnLeave", RowOnLeave)
	end
	-- Addon-owned row: resultID is the field Blizzard's template code expects.
	row.resultID = elementData.resultID
	local update = ns.FrameMap.GetFunc("searchEntryUpdate")
	if update then
		local ok, err = pcall(update, row)
		if not ok then
			ns.DebugOnce("row-update-" .. tostring(err), "Row update failed: %s", err)
		end
	end
	local snap = currentRun and currentRun.snapshots and currentRun.snapshots[elementData.resultID]
	local okStale, staleErr = pcall(ClearStaleDecline, row, snap)
	if not okStale then
		ns.DebugOnce("row-stale-" .. tostring(staleErr), "Row decline cleanup failed: %s", staleErr)
	end
	local ok, err = pcall(UpdateRowInfo, row, elementData.resultID)
	if not ok then
		ns.DebugOnce("row-info-" .. tostring(err), "Row info failed: %s", err)
	end
	local okStrip, stripErr = pcall(UpdateMemberStrip, row, snap, ns.Settings.Profile().rowInfo or {})
	if not okStrip then
		ns.DebugOnce("row-members-" .. tostring(stripErr), "Member icons failed: %s", stripErr)
		local strip, crown = memberStrips[row], leaderCrowns[row]
		if strip then
			strip:Hide()
		end
		if crown then
			crown:Hide()
		end
		if type(row.DataDisplay) == "table" and not row.isApplication then
			row.DataDisplay:Show()
		end
	end
end

local function Build()
	local panel = ns.FrameMap.Get("searchPanel")
	local inset = ns.FrameMap.Get("resultsInset") or ns.FrameMap.Get("searchScroll")
	local blizzardScroll = ns.FrameMap.Get("searchScroll")
	if not (panel and inset) then
		return false
	end

	-- Invisible watcher: re-evaluates when the search panel is shown.
	watcher = CreateFrame("Frame", nil, panel)
	watcher:SetScript("OnShow", function()
		ns.Engine:RequestRun()
	end)
	watcher:SetScript("OnHide", function()
		SetBlizzardListHidden(false)
	end)

	-- Transparent container over Blizzard's results area: Blizzard's inset background shows
	-- through; only Blizzard's ScrollBox and ScrollBar are faded out underneath.
	list = CreateFrame("Frame", nil, panel)
	list:SetAllPoints(blizzardScroll or inset)
	list:SetFrameLevel((blizzardScroll and blizzardScroll:GetFrameLevel() or panel:GetFrameLevel()) + 50)
	list:EnableMouse(true)
	list:Hide()

	scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
	scrollBox:SetAllPoints(list)

	local blizzardBar = ns.FrameMap.Get("searchScrollBar")
	local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
	if blizzardBar then
		scrollBar:SetAllPoints(blizzardBar)
		scrollBar:SetFrameLevel(list:GetFrameLevel() + 5)
	else
		scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
		scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
	end

	-- Blizzard's search box drops its suggestions (AutoCompleteFrame, frame level 20) over the results
	-- area. The addon list sits well above that, so it would cover them: while the suggestions are up,
	-- the list drops just below them, and goes back afterwards. Read-only hooks on Blizzard's frame.
	local autoComplete = ns.FrameMap.Get("searchAutoComplete")
	if autoComplete and autoComplete.HookScript then
		local function SetListLevel(level)
			list:SetFrameLevel(level)
			if scrollBar then
				scrollBar:SetFrameLevel(level + 5)
			end
		end
		local normalLevel = list:GetFrameLevel()
		autoComplete:HookScript("OnShow", function(self)
			local below = self:GetFrameLevel() - 2
			local floor = (blizzardScroll and blizzardScroll:GetFrameLevel() or 0) + 1
			SetListLevel(math.max(math.min(below, normalLevel), floor))
		end)
		autoComplete:HookScript("OnHide", function()
			SetListLevel(normalLevel)
		end)
	end

	local view = CreateScrollBoxListLinearView()
	view:SetElementInitializer(ROW_TEMPLATE, InitRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	-- Match my UI: our scroll bar sits over Blizzard's, which the suite restyles. Rows stay stock.
	ns.Skin.Apply("scrollbar", scrollBar)

	-- When filters hide every group, the list shows Blizzard's own "no groups found" text, styled and
	-- placed like the stock ScrollBox.NoResultsFound. (The filter panel's status line still says the
	-- groups were hidden by filters, and has Reset.)
	emptyState = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	emptyState:SetWidth(240)
	emptyState:SetPoint("TOP", list, "TOP", 0, -40)
	emptyState:SetText(LFG_LIST_NO_RESULTS_FOUND)
	emptyState:Hide()

	-- Addon Sign Up control sits exactly over Blizzard's (same place, same click count).
	local blizzardSignUp = ns.FrameMap.Get("signUpButton")
	signUpButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	if blizzardSignUp then
		signUpButton:SetAllPoints(blizzardSignUp)
		signUpButton:SetFrameLevel(blizzardSignUp:GetFrameLevel() + 50)
	else
		signUpButton:SetSize(120, 22)
		signUpButton:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, -26)
	end
	signUpButton:SetText(SIGN_UP)
	signUpButton:SetMotionScriptsWhileDisabled(true)
	signUpButton:Hide()
	signUpButton:SetScript("OnClick", function()
		OpenSignUp(selectedResultID)
	end)
	signUpButton:SetScript("OnEnter", function(self)
		if self.tooltipText then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	signUpButton:SetScript("OnLeave", GameTooltip_Hide)
	ns.Skin.Apply("button", signUpButton) -- over Blizzard's Sign Up, which the suite restyles

	return true
end

local function HideList()
	if list then
		list:Hide()
		signUpButton:Hide()
	end
	SetSelected(nil)
	SetBlizzardListHidden(false)
end

-- Draw an engine run. Anything other than "filtering" gives the stock Blizzard list back.
function ResultList:Render(run)
	currentRun = run
	if not list then
		return
	end
	local panel = ns.FrameMap.Get("searchPanel")
	if run and run.state == "searching" and list:IsShown() and panel and panel:IsVisible() then
		-- A refresh while filtering: keep Blizzard's list hidden until the new results are filtered,
		-- so its unfiltered rows never flash. Blizzard's Searching spinner is outside the list and
		-- stays visible; Blizzard also clears the selection when a search starts.
		scrollBox:SetDataProvider(CreateDataProvider())
		emptyState:Hide()
		SetSelected(nil)
		UpdateSignUpButton()
		return
	end
	if not (run and run.state == "filtering" and panel and panel:IsVisible()) then
		return HideList()
	end

	local dataProvider = CreateDataProvider()
	local stillPresent = false
	for i = 1, #run.visible do
		local id = run.visible[i]
		dataProvider:Insert({ resultID = id })
		stillPresent = stillPresent or id == selectedResultID
	end
	if not stillPresent then
		SetSelected(nil)
	end

	scrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)
	if #run.visible == 0 then
		emptyState:SetText(LFG_LIST_NO_RESULTS_FOUND)
		emptyState:Show()
	else
		emptyState:Hide()
	end
	list:Show()
	signUpButton:Show()
	SetBlizzardListHidden(true)
	UpdateSignUpButton()
end

function ResultList:OnRunComplete(_, run)
	local ok, err = pcall(self.Render, self, run)
	if not ok then
		ns.DebugOnce("resultlist-" .. tostring(err), "ResultList error (showing stock list): %s", err)
		HideList()
	end
end

function ResultList:OnEnable()
	if not Build() then
		ns.DebugOnce("resultlist-build", "ResultList: search panel not found; addon list disabled")
		return
	end
	self:RegisterMessage(ns.MSG.RunComplete, "OnRunComplete")
end
