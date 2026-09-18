-- Filter panel docked next to the Group Finder.
-- Layout follows the user's "LFG Filter" design (Dungeons, Ranges, Group needs, I sign up as,
-- footer count; Sort is the icon next to the gear), built only from Blizzard templates and fonts so it looks stock.
-- Every change writes settings and asks the engine to re-filter; it never starts a search.
local _, ns = ...

local FilterPanel = ns.NewModule("FilterPanel")
local L = ns.L

local PANEL_WIDTH = 290
local CONTENT_WIDTH = PANEL_WIDTH - 36
-- Content box inside the PortraitFrameTemplate: below the title bar, above the bottom border.
local CONTENT_TOP, CONTENT_BOTTOM, CONTENT_LEFT, CONTENT_RIGHT = 30, 10, 14, 12
local FOOTER_HEIGHT = 16
local GRID_COLUMNS = 2
local GRID_GAP = 4
local DUNGEON_BUTTON_WIDTH = (CONTENT_WIDTH - GRID_GAP) / GRID_COLUMNS
local DUNGEON_BUTTON_MAX_HEIGHT, DUNGEON_BUTTON_MIN_HEIGHT = 31, 20 -- shrinks to fit the panel
local CHECK_ATLAS = "checkmark-minimal" -- Blizzard's checkbox checkmark (CheckButtonTemplates.xml)
local CHECK_TEXTURE = [[Interface\Buttons\UI-CheckBox-Check]] -- fallback if the atlas is missing
local RATING_CHIPS = { 2000, 3000, 3200, 3500 }
local RATING_BOX_WIDTH = 54
local SIGN_UP_LABEL_WIDTH = 72
local SORT_ARROW_ATLAS = "auctionhouse-ui-sortarrow" -- Blizzard's column sort arrow (Communities roster)
local DUNGEON_SORT_OPTIONS = {
	{ field = "leaderRating", dir = "desc", text = "Leader rating (high to low)" }, -- default
	{ field = "blizzard", text = "Blizzard order" },
	{ field = "age", dir = "asc", text = "Newest listings first" },
	{ field = "members", dir = "desc", text = "Most members" },
}
local RAID_SORT_OPTIONS = {
	{ field = "leaderProgress", dir = "desc", text = "Leader progress (high to low)" }, -- default
	{ field = "blizzard", text = "Blizzard order" },
	{ field = "age", dir = "asc", text = "Newest listings first" },
	{ field = "members", dir = "desc", text = "Most members" },
}
-- Raid difficulty buttons: rank saved in `difficulties` -> Blizzard GlobalString name.
local DIFFICULTIES = {
	{ rank = 1, global = "PLAYER_DIFFICULTY1", fallback = "Normal" },
	{ rank = 2, global = "PLAYER_DIFFICULTY2", fallback = "Heroic" },
	{ rank = 3, global = "PLAYER_DIFFICULTY6", fallback = "Mythic" },
}
local RAID_BOX_WIDTH = 46
local BOSS_COLUMNS = 2
local BOSS_ROW_STEP = 20
local MIN_BOSS_ROWS = 2 -- the boss list never shrinks below this; the rest is scrolled to
local MARK_DEAD = [[Interface\RaidFrame\ReadyCheck-NotReady]] -- Blizzard's ready-check cross
local FIT_CHECKS = { "party", "hasTank", "hasHealer", "battleRes", "bloodlust", "notDeclined", "hideClass" }
local NEEDS_COLUMN_WIDTH = CONTENT_WIDTH / 2
local SIGN_UP_ROLES = { "TANK", "HEALER", "DAMAGER" }
-- Fallback role icon atlases if Blizzard's GetIconForRole isn't available.
local ROLE_ICON_FALLBACK = { TANK = "UI-LFG-RoleIcon-Tank", HEALER = "UI-LFG-RoleIcon-Healer", DAMAGER = "UI-LFG-RoleIcon-DPS" }

local panel
local ui = {}

function FilterPanel.GetFrame()
	return panel
end

local function Current()
	return ns.Settings.ForCategory(ns.Categories.GetActive())
end

local function IsRaids()
	return ns.Categories.GetActive() == ns.Categories.RAIDS
end

local function SortOptions()
	return IsRaids() and RAID_SORT_OPTIONS or DUNGEON_SORT_OPTIONS
end

local function Changed()
	ns.Settings:Changed()
end

-- Blizzard's role icon (the one its sign-up dialog uses); disabled = greyed variant.
local function RoleIconAtlas(role, disabled)
	if GetIconForRole then
		local ok, atlas = pcall(GetIconForRole, role, disabled and true or false)
		if ok and type(atlas) == "string" then
			return atlas
		end
	end
	return ROLE_ICON_FALLBACK[role]
end

local function NewCheckmark(parent, size)
	local check = parent:CreateTexture(nil, "OVERLAY")
	check:SetSize(size, size)
	local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(CHECK_ATLAS)
	if hasAtlas then
		check:SetAtlas(CHECK_ATLAS)
	else
		check:SetTexture(CHECK_TEXTURE)
	end
	check:Hide()
	return check
end

local function PauseReasonText(reason)
	if reason == "combat" then
		return L["in combat"]
	elseif reason == "encounter" then
		return L["encounter"]
	elseif reason == "challengeMode" then
		return L["Mythic+"]
	elseif reason == "pvpMatch" then
		return L["PvP"]
	end
	return L["restricted"]
end

-- Short dungeon name for the grid (the full name is in the tooltip): no leading "The ", nothing
-- after a comma ("Ara-Kara, City of Echoes" -> "Ara-Kara").
local function ShortName(name)
	if type(name) ~= "string" then
		return ""
	end
	local short = name:gsub("^The ", ""):gsub(",.*$", "")
	return short ~= "" and short or name
end

local function FitLabel(check)
	if check == "party" then
		return L["Party fit"]
	elseif check == "hasTank" then
		return L["Has a Tank"]
	elseif check == "hasHealer" then
		return L["Has a Healer"]
	elseif check == "notDeclined" then
		return L["Not Declined"]
	elseif check == "bloodlust" then
		return L["Bloodlust"]
	elseif check == "hideClass" then
		return L["Hide Class"]
	end
	return L["Battle Res"]
end

local function FitTooltip(check)
	if check == "party" then
		return L["Hide groups without an open spot for your role, or, in a party, for every member's role."]
	elseif check == "hasTank" then
		return L["Show only groups that already have a tank."]
	elseif check == "hasHealer" then
		return L["Show only groups that already have a healer."]
	elseif check == "notDeclined" then
		return L["Hide groups that have declined your application."]
	elseif check == "bloodlust" then
		return L["Hide groups that already have a Shaman, Mage, Evoker or Hunter."]
	elseif check == "hideClass" then
		return L["Hide groups that already have someone of your class."]
	end
	return L["Hide groups that already have a Druid, Death Knight, Warlock or Paladin."]
end

-- Settings (gear menu) ----------------------------------------------------------------------

-- Kept in a Blizzard menu behind the gear icon: what to show on each group row (saved
-- in rowInfo), Show ranges (saved on the profile), then Reset all.
local SETTINGS_OPTIONS = {
	{ key = "leaderRating", text = "Show leader rating", tooltip = "Show the group leader's Mythic+ rating on each group." },
	{ key = "region", text = "Show region", tooltip = "Show the group leader's region (flag and tag, for example East or DE) on each group." },
	{ key = "specs", text = "Show spec role", tooltip = "Show each member's spec icon with a role badge instead of Blizzard's class icons. Off: Blizzard's default icons." },
	{ key = "leader", text = "Show who's leader", tooltip = "Show a crown on the group leader's icon." },
	{ key = "leaderProgress", text = "Show leader progress", tooltip = "Show the raid leader's progress in that raid (and their main's, if better) from Raider.IO. Needs Raider.IO." },
	{ key = "showRanges", onProfile = true, text = "Show ranges", tooltip = "Show the Ranges section (Dungeons: leader rating; Raids: members, most tanks and healers). Off: the section is hidden and those ranges don't filter; your values come back when you turn it on again." },
}

local function SettingsTable(option)
	local profile = ns.Settings.Profile()
	return option.onProfile and profile or profile.rowInfo
end

local function ResetAll()
	ns.Settings.ResetCategory(ns.Categories.GetActive())
	ns.Settings.Profile().signUpRolesCustom = false -- back to "my spec's role"
	Changed()
end

-- Sort ---------------------------------------------------------------------------------------

local function SortOptionMatches(option, sort)
	return option.field == sort.field and (option.dir == nil or option.dir == (sort.dir == "asc" and "asc" or "desc"))
end

-- Name of the active category's current sort (sort button tooltip).
local function SortText()
	local settings = Current()
	if not settings then
		return ""
	end
	for _, option in ipairs(SortOptions()) do
		if SortOptionMatches(option, settings.sort) then
			return L[option.text]
		end
	end
	return L["Blizzard order"]
end

-- Sort menu (the sort icon next to the gear): the active category's choices as radio options.
local function SetupSortMenu(dropdown, root)
	local settings = Current()
	if not settings then
		return
	end
	root:CreateTitle(L["Sort"])
	for _, option in ipairs(SortOptions()) do
		root:CreateRadio(L[option.text], function()
			return SortOptionMatches(option, settings.sort)
		end, function()
			settings.sort.field = option.field
			settings.sort.dir = option.dir or "desc"
			Changed()
		end)
	end
end

-- Gear menu: the display settings, then Reset all.
local function SetupSettingsMenu(dropdown, root)
	root:CreateTitle(L["Settings"])
	for _, option in ipairs(SETTINGS_OPTIONS) do
		local description = root:CreateCheckbox(L[option.text], function()
			return SettingsTable(option)[option.key] == true
		end, function()
			local store = SettingsTable(option)
			store[option.key] = not store[option.key]
			Changed()
		end)
		if description and description.SetTooltip then
			description:SetTooltip(function(tooltip)
				GameTooltip_SetTitle(tooltip, L[option.text])
				GameTooltip_AddNormalLine(tooltip, L[option.tooltip])
			end)
		end
	end
	-- Last option: Reset all, centered
	root:CreateDivider()
	local reset = root:CreateButton(L["Reset all"], ResetAll)
	if reset and reset.AddInitializer then
		reset:AddInitializer(function(button)
			local text = button.fontString
			if text then
				text:ClearAllPoints()
				text:SetPoint("CENTER", button, "CENTER", 0, 0)
			end
		end)
	end
	if reset and reset.SetTooltip then
		reset:SetTooltip(function(tooltip)
			GameTooltip_SetTitle(tooltip, L["Reset all"])
			GameTooltip_AddNormalLine(tooltip, L["Clear this category's filters and sort, and sign up as your spec's role again."])
		end)
	end
end

-- Build ---------------------------------------------------------------------------------------

local function NewLabel(parent, text, font)
	local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormalSmall")
	label:SetText(text)
	return label
end

local function SimpleTooltip(frame, text)
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(text, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", GameTooltip_Hide)
end

-- Small text-only button (All / None): grey text that turns gold on hover.
local function NewTextButton(parent, text, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetNormalFontObject("GameFontDisableSmall")
	button:SetHighlightFontObject("GameFontNormalSmall")
	button:SetText(text)
	local label = button:GetFontString()
	local width = label and label.GetStringWidth and label:GetStringWidth() or 0
	button:SetSize(math.max(width, 16) + 4, 16)
	button:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		onClick()
	end)
	return button
end

-- Dungeon grid: one Blizzard panel button per current-season dungeon, 2 per row. A selected
-- dungeon shows Blizzard's checkmark on its button until clicked again.
local function DungeonButton(index)
	local button = ui.dungeonButtons[index]
	if button then
		return button
	end
	button = CreateFrame("Button", nil, ui.content, "UIPanelButtonTemplate")
	button:SetSize(DUNGEON_BUTTON_WIDTH, DUNGEON_BUTTON_MAX_HEIGHT)
	button:SetNormalFontObject("GameFontNormalSmall")
	button:SetHighlightFontObject("GameFontHighlightSmall")
	button:SetDisabledFontObject("GameFontDisableSmall")
	button:SetText(" ")

	-- Dungeon icon on the left; checkmark on the right, its space always reserved.
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(22, 22)
	icon:SetPoint("LEFT", button, "LEFT", 4, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.tlfgIcon = icon

	button.tlfgCheck = NewCheckmark(button, 14)
	button.tlfgCheck:SetPoint("RIGHT", button, "RIGHT", -4, 0)
	-- Excluded (right-click): Blizzard's ready-check cross where the checkmark goes.
	button.tlfgCross = button:CreateTexture(nil, "OVERLAY")
	button.tlfgCross:SetSize(14, 14)
	button.tlfgCross:SetPoint("RIGHT", button, "RIGHT", -4, 0)
	button.tlfgCross:SetTexture(MARK_DEAD)
	button.tlfgCross:Hide()

	local label = button:GetFontString()
	if label then
		label:SetWordWrap(false)
	end
	-- Left-click selects (only selected dungeons shown), right-click excludes (that dungeon hidden);
	-- the same click again clears it.
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(self, mouseButton)
		local settings = Current()
		local groupID = self.tlfgGroupID
		if not (settings and groupID and settings.activityGroups and settings.excludedGroups) then
			return
		end
		local marks, other = settings.activityGroups, settings.excludedGroups
		if mouseButton == "RightButton" then
			marks, other = settings.excludedGroups, settings.activityGroups
		end
		local on = not marks[groupID]
		marks[groupID] = on or nil
		if on then
			other[groupID] = nil
		end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Changed()
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tlfgName or "")
		if self.tlfgSelected then
			GameTooltip:AddLine(L["Selected: only the selected dungeons are shown."], 0.1, 1, 0.1, true)
		elseif self.tlfgExcluded then
			GameTooltip:AddLine(L["Excluded: this dungeon's groups are hidden."], 1, 0.25, 0.25, true)
		end
		GameTooltip:AddLine(L["Left-click: show only selected dungeons. Right-click: hide this dungeon. Click again to clear."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	ui.dungeonButtons[index] = button
	return button
end

-- Raid boss checkbox, two columns. Left-click ticks it "alive" (only groups that haven't killed
-- it yet), right-click marks it "dead" (only groups that have killed it: Blizzard's ready-check
-- cross in the box, name greyed); the same click again clears the mark. The box's look is set from
-- the settings on every layout.
local function BossCheck(index)
	local check = ui.bossChecks[index]
	if check then
		return check
	end
	check = CreateFrame("CheckButton", nil, ui.bossArea, "UICheckButtonTemplate")
	check:SetSize(22, 22)
	check:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if type(check.Text) == "table" then
		check.Text:SetFontObject("GameFontHighlightSmall")
		check.Text:SetWidth(NEEDS_COLUMN_WIDTH - 26)
		check.Text:SetJustifyH("LEFT")
		check.Text:SetWordWrap(false)
	end
	check.tlfgCross = check:CreateTexture(nil, "OVERLAY")
	check.tlfgCross:SetSize(14, 14)
	check.tlfgCross:SetPoint("CENTER", check, "CENTER", 0, 0)
	check.tlfgCross:SetTexture(MARK_DEAD)
	check.tlfgCross:Hide()

	check:SetScript("OnClick", function(self, mouseButton)
		local settings = Current()
		local bossID = self.tlfgBossID
		if not (settings and settings.aliveBosses and settings.deadBosses and bossID) then
			return
		end
		local marks, other = settings.aliveBosses, settings.deadBosses
		if mouseButton == "RightButton" then
			marks, other = settings.deadBosses, settings.aliveBosses
		end
		local on = not marks[bossID]
		marks[bossID] = on or nil
		if on then
			other[bossID] = nil
			if settings.maxBosses == 0 then
				settings.maxBosses = -1 -- marking a boss turns Fresh run off (Fresh run clears the marks)
			end
		end
		Changed()
	end)
	check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tlfgName or "")
		if self.tlfgRaid then
			GameTooltip:AddLine(self.tlfgRaid, 0.6, 0.6, 0.6, true)
		end
		if self.tlfgState == "alive" then
			GameTooltip:AddLine(L["Only groups that haven't killed this boss yet."], 0.1, 1, 0.1, true)
		elseif self.tlfgState == "dead" then
			GameTooltip:AddLine(L["Only groups that have already killed this boss."], 1, 0.25, 0.25, true)
		end
		GameTooltip:AddLine(L["Left-click: still alive. Right-click: already dead. Click again to clear."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	check:SetScript("OnLeave", GameTooltip_Hide)
	ui.bossChecks[index] = check
	return check
end

-- Number box for a range value (min or max); empty = off (offValue: 0, or -1 where 0 is a real
-- maximum). Shows a grey "min"/"max" placeholder when empty.
local function NewNumberBox(parent, key, placeholder, width, offValue, maxValue)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(maxValue >= 1000 and 4 or 2)
	box:SetJustifyH("CENTER")
	box.tlfgPlaceholder = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	box.tlfgPlaceholder:SetPoint("CENTER", box, "CENTER", 0, 0)
	box.tlfgPlaceholder:SetText(placeholder)
	local function UpdatePlaceholder(editBox)
		editBox.tlfgPlaceholder:SetShown(editBox:GetText() == "" and not editBox:HasFocus())
	end
	local function Commit(editBox)
		local settings = Current()
		if settings and settings[key] ~= nil then
			local number = tonumber(editBox:GetText())
			local value = number and math.max(0, math.min(maxValue, number)) or offValue
			if value ~= settings[key] then
				settings[key] = value
				Changed()
			end
			editBox:SetText(value ~= offValue and tostring(value) or "")
		end
		UpdatePlaceholder(editBox)
	end
	box:SetScript("OnEnterPressed", function(editBox)
		editBox:ClearFocus()
		Commit(editBox)
	end)
	box:SetScript("OnEditFocusLost", Commit)
	box:SetScript("OnEditFocusGained", UpdatePlaceholder)
	box:SetScript("OnEscapePressed", function(editBox)
		editBox:ClearFocus()
	end)
	box.tlfgKey = key
	box.tlfgOff = offValue
	box.tlfgUpdatePlaceholder = UpdatePlaceholder
	return box
end

local function NewRatingBox(parent, key, placeholder)
	return NewNumberBox(parent, key, placeholder, RATING_BOX_WIDTH, 0, 5000)
end

-- Show a box's saved value (unless the player is typing in it).
local function SyncBox(box, settings)
	if not box:HasFocus() then
		local value = settings[box.tlfgKey]
		box:SetText((value ~= nil and value ~= box.tlfgOff) and tostring(value) or "")
	end
	box.tlfgUpdatePlaceholder(box)
end

-- Small Blizzard panel toggle button with a checkmark on the right (rating chips, difficulties, Fresh run).
local function NewToggleChip(parent, text, width)
	local chip = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	chip:SetSize(width, 20)
	chip:SetNormalFontObject("GameFontNormalSmall")
	chip:SetHighlightFontObject("GameFontHighlightSmall")
	chip:SetText(text)
	chip.tlfgCheck = NewCheckmark(chip, 11)
	chip.tlfgCheck:SetPoint("RIGHT", chip, "RIGHT", -3, 0)
	return chip
end

-- "I sign up as" pill: Blizzard panel button with the role icon, label, and a checkmark on the
-- icon when chosen. Roles the class can't play are disabled with Blizzard's lock badge.
local function NewRoleButton(parent, role)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetHeight(22)
	button:SetNormalFontObject("GameFontNormalSmall")
	button:SetHighlightFontObject("GameFontHighlightSmall")
	button:SetDisabledFontObject("GameFontDisableSmall")
	button:SetText(role == "DAMAGER" and L["DPS"] or _G[role] or role)
	button:SetMotionScriptsWhileDisabled(true) -- locked roles still explain themselves
	button.tlfgRole = role

	button.tlfgRoleIcon = button:CreateTexture(nil, "ARTWORK")
	button.tlfgRoleIcon:SetSize(16, 16)
	button.tlfgRoleIcon:SetPoint("LEFT", button, "LEFT", 4, 0)
	button.tlfgCheck = NewCheckmark(button, 12)
	button.tlfgCheck:SetPoint("CENTER", button.tlfgRoleIcon, "BOTTOMRIGHT", 0, 2)
	button.tlfgLock = button:CreateTexture(nil, "OVERLAY")
	button.tlfgLock:SetSize(9, 11)
	button.tlfgLock:SetPoint("BOTTOMRIGHT", button.tlfgRoleIcon, "BOTTOMRIGHT", 3, -2)
	button.tlfgLock:SetAtlas("groupfinder-icon-lock")
	button.tlfgLock:Hide()

	local label = button:GetFontString()
	if label then
		label:ClearAllPoints()
		label:SetPoint("LEFT", button, "LEFT", 23, 0)
		label:SetPoint("RIGHT", button, "RIGHT", -2, 0)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(false)
	end

	button:SetScript("OnClick", function(self)
		local profile = ns.Settings.Profile()
		if not profile.signUpRolesCustom then
			-- First change: start from the current roles (the spec's role).
			for _, r in ipairs(SIGN_UP_ROLES) do
				profile.signUpRoles[r] = false
			end
			for _, r in ipairs(ns.Snapshot.SignUpRoles()) do
				profile.signUpRoles[r] = true
			end
			profile.signUpRolesCustom = true
		end
		profile.signUpRoles[role] = not profile.signUpRoles[role]
		if #ns.Match.ResolveSignUpRoles(true, profile.signUpRoles, nil, ns.Snapshot.AvailableRoles()) == 0 then
			profile.signUpRoles[role] = true -- keep at least one role
		end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Changed()
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.tlfgLocked then
			GameTooltip:SetText(L["Your class can't play this role."], nil, nil, nil, nil, true)
		else
			GameTooltip:SetText(L["Roles you sign up as: pre-ticked in Blizzard's sign-up dialog and used by Party fit. Default: your spec's role."], nil, nil, nil, nil, true)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function Build()
	local pve = ns.FrameMap.Get("pve")
	local searchPanel = ns.FrameMap.Get("searchPanel")
	if not (pve and searchPanel) then
		return false
	end

	-- Looks attached to the Group Finder, the way Premade Groups Filter does it: the same frame
	-- template as PVEFrame (PortraitFrameTemplate) with Blizzard's no-portrait border, flush against
	-- PVEFrame's right edge and exactly as tall. Parented to the search panel so it shows and hides
	-- with it.
	panel = CreateFrame("Frame", nil, searchPanel, "PortraitFrameTemplate")
	panel:SetSize(PANEL_WIDTH, pve:GetHeight() > 0 and pve:GetHeight() or 428)
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", pve, "TOPRIGHT", 0, 0)
	panel:EnableMouse(true)
	if type(panel.SetBorder) == "function" then
		pcall(panel.SetBorder, panel, "ButtonFrameTemplateNoPortrait")
	end
	if type(panel.SetPortraitShown) == "function" then
		pcall(panel.SetPortraitShown, panel, false)
	end
	if type(panel.CloseButton) == "table" then
		panel.CloseButton:Hide()
	end
	if type(panel.SetTitle) == "function" then
		panel:SetTitle("LFG Spyglass")
	end

	local content = CreateFrame("Frame", nil, panel)
	content:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_LEFT, -CONTENT_TOP)
	content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -CONTENT_RIGHT, CONTENT_BOTTOM)
	ui.content = content

	-- Header row: Dungeons n/8, All, None ... gear
	-- Settings: Blizzard's gear icon dropdown (the Quest Log's settings button); Reset all is its
	-- last option.
	ui.gear = CreateFrame("DropdownButton", nil, content, "UIPanelIconDropdownButtonTemplate")
	ui.gear:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	ui.gear:SetupMenu(SetupSettingsMenu)
	SimpleTooltip(ui.gear, L["Settings"])
	-- Sort: an icon dropdown left of the gear, drawn like the gear (Blizzard's icon dropdown button):
	-- Blizzard's column sort arrow twice, one pointing up and one down; the menu lists the active
	-- category's sort choices.
	ui.sort = CreateFrame("DropdownButton", nil, content)
	ui.sort:SetSize(18, 16)
	ui.sort:SetPoint("RIGHT", ui.gear, "LEFT", -6, 0)
	ui.sort.tlfgArrows = {}
	for index, x in ipairs({ -3, 3 }) do
		for _, layer in ipairs({ "ARTWORK", "HIGHLIGHT" }) do
			local arrow = ui.sort:CreateTexture(nil, layer)
			arrow:SetAtlas(SORT_ARROW_ATLAS)
			arrow:SetSize(10, 10)
			arrow:SetPoint("CENTER", ui.sort, "CENTER", x, 0)
			if index == 1 then
				arrow:SetRotation(math.pi) -- the left arrow points the other way
			end
			if layer == "HIGHLIGHT" then
				arrow:SetBlendMode("ADD")
				arrow:SetAlpha(0.4)
			end
			ui.sort.tlfgArrows[#ui.sort.tlfgArrows + 1] = arrow
		end
	end
	ui.sort:HookScript("OnMouseDown", function(self)
		for _, arrow in ipairs(self.tlfgArrows) do
			arrow:AdjustPointsOffset(1, -1)
		end
	end)
	ui.sort:HookScript("OnMouseUp", function(self)
		for _, arrow in ipairs(self.tlfgArrows) do
			arrow:AdjustPointsOffset(-1, 1)
		end
	end)
	ui.sort:SetupMenu(SetupSortMenu)
	ui.sort:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L["Sort"])
		GameTooltip_AddNormalLine(GameTooltip, SortText())
		GameTooltip:Show()
	end)
	ui.sort:HookScript("OnLeave", GameTooltip_Hide)

	ui.dungeonsLabel = NewLabel(content, L["Dungeons"])
	ui.dungeonCount = NewLabel(content, "", "GameFontHighlightSmall")
	ui.dungeonCount:SetPoint("LEFT", ui.dungeonsLabel, "RIGHT", 4, 0)
	ui.allDungeons = NewTextButton(content, L["All"], function()
		local settings = Current()
		if settings then
			for _, group in ipairs(ns.Categories.GetSeasonGroups(ns.Categories.GetActive())) do
				settings.activityGroups[group.groupID] = true
			end
			wipe(settings.excludedGroups or {})
			Changed()
		end
	end)
	ui.allDungeons:SetPoint("LEFT", ui.dungeonCount, "RIGHT", 8, 0)
	SimpleTooltip(ui.allDungeons, L["Select all (same as none: all groups shown)."])
	ui.noDungeons = NewTextButton(content, L["None"], function()
		local settings = Current()
		if settings then
			wipe(settings.activityGroups)
			wipe(settings.excludedGroups or {})
			Changed()
		end
	end)
	ui.noDungeons:SetPoint("LEFT", ui.allDungeons, "RIGHT", 4, 0)
	SimpleTooltip(ui.noDungeons, L["Clear the selection and the exclusions (all groups shown)."])
	ui.dungeonButtons = {}
	ui.dungeonsUnavailable = NewLabel(content, "", "GameFontDisableSmall")

	-- Raids only: difficulty buttons (none selected = all difficulties)
	ui.difficultyLabel = NewLabel(content, L["Difficulty"])
	ui.difficulties = {}
	local difficultyWidth = (CONTENT_WIDTH - GRID_GAP * (#DIFFICULTIES - 1)) / #DIFFICULTIES
	for index, difficulty in ipairs(DIFFICULTIES) do
		local chip = NewToggleChip(content, _G[difficulty.global] or L[difficulty.fallback], difficultyWidth)
		chip.tlfgRank = difficulty.rank
		chip:SetScript("OnClick", function(self)
			local settings = Current()
			if settings and settings.difficulties then
				settings.difficulties[self.tlfgRank] = (not settings.difficulties[self.tlfgRank]) or nil
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				Changed()
			end
		end)
		ui.difficulties[index] = chip
	end

	-- Raids only: boss checkboxes (alive or dead) with None and Fresh run on the header row.
	-- The season's raids share one list, in a clipped area that scrolls with the wheel when it has
	-- more bosses than the panel has room for.
	ui.bossesTitle = NewLabel(content, L["Bosses"])
	ui.bossArea = CreateFrame("Frame", nil, content)
	ui.bossArea:SetClipsChildren(true)
	ui.bossArea:EnableMouseWheel(true)
	ui.bossArea:SetScript("OnMouseWheel", function(_, delta)
		local hidden = (ui.bossRowsTotal or 0) - (ui.bossRowsShown or 0)
		if hidden <= 0 then
			return
		end
		local offset = math.min(math.max((ui.bossOffset or 0) - delta * BOSS_ROW_STEP, 0), hidden * BOSS_ROW_STEP)
		if offset ~= ui.bossOffset then
			ui.bossOffset = offset
			FilterPanel:RequestRefresh(true)
		end
	end)
	ui.bossChecks = {}
	ui.bossesUnavailable = NewLabel(content, L["Boss list not available yet"], "GameFontDisableSmall")
	ui.noBosses = NewTextButton(content, L["None"], function()
		local settings = Current()
		if settings and settings.aliveBosses and settings.deadBosses then
			wipe(settings.aliveBosses)
			wipe(settings.deadBosses)
			Changed()
		end
	end)
	SimpleTooltip(ui.noBosses, L["Clear the boss marks."])
	ui.freshRun = NewToggleChip(content, L["Fresh run"], 76)
	ui.freshRun:SetScript("OnClick", function()
		local settings = Current()
		if settings and settings.maxBosses ~= nil then
			settings.maxBosses = settings.maxBosses == 0 and -1 or 0
			if settings.maxBosses == 0 then
				-- Fresh run replaces the boss marks (every boss is alive in a fresh run)
				wipe(settings.aliveBosses or {})
				wipe(settings.deadBosses or {})
			end
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Changed()
		end
	end)
	SimpleTooltip(ui.freshRun, L["Only groups with no bosses defeated yet."])

	-- Raids only: ranges (members, most tanks / healers)
	ui.membersLabel = NewLabel(content, L["Members"], "GameFontHighlightSmall")
	ui.membersMin = NewNumberBox(content, "minMembers", L["min"], RAID_BOX_WIDTH, 0, 40)
	ui.membersMax = NewNumberBox(content, "maxMembers", L["max"], RAID_BOX_WIDTH, -1, 40)
	ui.tanksLabel = NewLabel(content, L["Most tanks"], "GameFontHighlightSmall")
	ui.tanksMax = NewNumberBox(content, "maxTanks", L["max"], RAID_BOX_WIDTH, -1, 40)
	ui.healersLabel = NewLabel(content, L["Most healers"], "GameFontHighlightSmall")
	ui.healersMax = NewNumberBox(content, "maxHealers", L["max"], RAID_BOX_WIDTH, -1, 40)
	ui.raidRangeRegions = { ui.membersLabel, ui.membersMin, ui.membersMax, ui.tanksLabel, ui.tanksMax,
		ui.healersLabel, ui.healersMax }

	-- Ranges: leader rating min / max, and quick minimums
	ui.rangesLabel = NewLabel(content, L["Ranges"])
	ui.ratingLabel = NewLabel(content, L["Leader rating"], "GameFontHighlightSmall")
	ui.ratingMin = NewRatingBox(content, "minLeaderRating", L["min"])
	ui.ratingMax = NewRatingBox(content, "maxLeaderRating", L["max"])
	ui.chips = {}
	local chipWidth = (CONTENT_WIDTH - GRID_GAP * (#RATING_CHIPS - 1)) / #RATING_CHIPS
	for index, value in ipairs(RATING_CHIPS) do
		local chip = NewToggleChip(content, value .. "+", chipWidth)
		chip.tlfgRating = value
		chip:SetScript("OnClick", function(self)
			local settings = Current()
			if settings then
				-- Click sets the minimum; clicking the chosen one again turns it off.
				settings.minLeaderRating = settings.minLeaderRating == self.tlfgRating and 0 or self.tlfgRating
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				Changed()
			end
		end)
		SimpleTooltip(chip, string.format(L["Only leaders rated %d or more."], value))
		ui.chips[index] = chip
	end

	-- Group needs (two columns)
	ui.fitLabel = NewLabel(content, L["Group needs"])
	ui.fit = {}
	for _, check in ipairs(FIT_CHECKS) do
		local button = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
		button:SetSize(24, 24)
		button:SetScript("OnClick", function(self)
			local settings = Current()
			if settings then
				settings.fit[check] = self:GetChecked() and true or false
				Changed()
			end
		end)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(FitTooltip(check), nil, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		if type(button.Text) == "table" then
			button.Text:SetFontObject("GameFontHighlightSmall")
		end
		ui.fit[check] = button
	end

	-- I sign up as: roles the class can play; default is the current spec's role only.
	ui.signUpLabel = NewLabel(content, L["I sign up as"], "GameFontHighlightSmall")
	ui.signUp = {}
	for _, role in ipairs(SIGN_UP_ROLES) do
		ui.signUp[role] = NewRoleButton(content, role)
	end

	-- Footer: how many groups match, or why the filter isn't running
	ui.status = NewLabel(content, "", "GameFontHighlightSmall")
	ui.status:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 2)
	ui.status:SetWidth(CONTENT_WIDTH)
	ui.status:SetJustifyH("LEFT")

	panel:Hide()
	return true
end

-- Layout --------------------------------------------------------------------------------------

local function Place(region, x, y)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", ui.content, "TOPLEFT", x, y)
end

-- Raids: the header row is Difficulty ... gear, then [Normal] [Heroic] [Mythic] (none selected =
-- all difficulties). Returns the next y.
local function LayoutDifficulty(settings, y)
	ui.difficultyLabel:Show()
	Place(ui.difficultyLabel, 0, y - 5)
	for index, chip in ipairs(ui.difficulties) do
		Place(chip, (index - 1) * (chip:GetWidth() + GRID_GAP), y - 22)
		chip.tlfgCheck:SetShown(settings.difficulties and settings.difficulties[chip.tlfgRank] == true)
		chip:Show()
	end
	return y - 22 - 26
end

-- Raids: Bosses ... None [Fresh run], then a checkbox per boss of every raid of the season
-- (ticked = still alive, cross = already dead). The list scrolls with the wheel when
-- it has more bosses than the panel has room for. Returns the next y.
local function LayoutBosses(settings, y, bossRows)
	local bossRaids = {}
	for _, raid in ipairs(ns.Categories.GetBossListRaids()) do
		if raid.bosses and #raid.bosses > 0 then
			bossRaids[#bossRaids + 1] = raid
		end
	end
	ui.bossesTitle:SetText(#bossRaids == 1 and string.format(L["Bosses (%s)"], ShortName(bossRaids[1].name))
		or L["Bosses"])
	ui.bossesTitle:Show()
	Place(ui.bossesTitle, 0, y)
	local freshX = CONTENT_WIDTH - ui.freshRun:GetWidth()
	Place(ui.freshRun, freshX, y + 3)
	ui.freshRun.tlfgCheck:SetShown(settings.maxBosses == 0)
	ui.freshRun:Show()
	y = y - 18

	-- One list across the raids (the panel is only so tall): the raid is named in each tooltip.
	local bosses = {}
	for _, raid in ipairs(bossRaids) do
		for _, boss in ipairs(raid.bosses) do
			bosses[#bosses + 1] = { boss = boss, raid = #bossRaids > 1 and ShortName(raid.name) or nil }
		end
	end
	local anyMark = next(settings.aliveBosses or {}) ~= nil or next(settings.deadBosses or {}) ~= nil
	ui.noBosses:SetShown(#bosses > 0 and anyMark)
	Place(ui.noBosses, freshX - ui.noBosses:GetWidth() - 6, y + 18 + 1)
	ui.bossRowsTotal = math.ceil(#bosses / BOSS_COLUMNS)
	ui.bossRowsShown = math.max(MIN_BOSS_ROWS, math.min(ui.bossRowsTotal, bossRows or ui.bossRowsTotal))
	ui.bossOffset = math.min(math.max(ui.bossOffset or 0, 0), (ui.bossRowsTotal - ui.bossRowsShown) * BOSS_ROW_STEP)
	ui.bossArea:SetShown(#bosses > 0)
	if #bosses > 0 then
		ui.bossArea:SetSize(CONTENT_WIDTH, ui.bossRowsShown * BOSS_ROW_STEP)
		Place(ui.bossArea, 0, y)
	end
	for index, entry in ipairs(bosses) do
		local check = BossCheck(index)
		local bossID = entry.boss.id
		local state = (settings.aliveBosses and settings.aliveBosses[bossID] and "alive")
			or (settings.deadBosses and settings.deadBosses[bossID] and "dead") or nil
		check.tlfgBossID = bossID
		check.tlfgName = entry.boss.name
		check.tlfgRaid = entry.raid
		check.tlfgState = state
		if type(check.Text) == "table" then
			check.Text:SetText(entry.boss.name)
			check.Text:SetFontObject(state == "dead" and "GameFontDisableSmall" or "GameFontHighlightSmall")
		end
		check:SetChecked(state == "alive")
		check.tlfgCross:SetShown(state == "dead")
		check:ClearAllPoints()
		check:SetPoint("TOPLEFT", ui.bossArea, "TOPLEFT", -2 + ((index - 1) % BOSS_COLUMNS) * NEEDS_COLUMN_WIDTH,
			ui.bossOffset - math.floor((index - 1) / BOSS_COLUMNS) * BOSS_ROW_STEP)
		check:Show()
	end
	for index = #bosses + 1, #ui.bossChecks do
		ui.bossChecks[index]:Hide()
	end
	ui.bossesUnavailable:SetShown(#bosses == 0)
	if #bosses == 0 then
		Place(ui.bossesUnavailable, 0, y)
		return y - 18 - 5
	end
	return y - ui.bossRowsShown * BOSS_ROW_STEP - 6
end

-- Stack every control top to bottom (the dungeon count and Group needs rows vary). The panel keeps
-- the Group Finder's height; if the controls wouldn't fit, the dungeon buttons get shorter.
local function LayoutPass(settings, buttonHeight, bossRows)
	local y = 0

	local raids = IsRaids()
	local profile = ns.Settings.Profile()

	-- Raids have no raid buttons: the header row is Difficulty (see LayoutDifficulty), then the bosses.
	local showGrid = not raids
	ui.dungeonsLabel:SetShown(showGrid)
	ui.dungeonCount:SetShown(showGrid)
	local groups = showGrid and ns.Categories.GetSeasonGroups(ns.Categories.GetActive()) or {}
	if raids then
		for _, button in ipairs(ui.dungeonButtons) do
			button:Hide()
		end
		ui.allDungeons:Hide()
		ui.noDungeons:Hide()
		ui.dungeonsUnavailable:Hide()
		y = LayoutDifficulty(settings, y)
		y = LayoutBosses(settings, y, bossRows)
	end

	-- Dungeons header: Dungeons n/N  All  None ... gear
	local selected = 0
	for _, group in ipairs(groups) do
		if settings.activityGroups[group.groupID] then
			selected = selected + 1
		end
	end
	if showGrid then
		ui.dungeonsLabel:SetText(L["Dungeons"])
		Place(ui.dungeonsLabel, 0, y - 5)
		ui.dungeonCount:SetText(string.format("%d/%d", selected, #groups)) -- selected dungeons, 0/N to N/N
		y = y - 26
	end

	-- Dungeons or raids (2 x N grid)
	for index, group in ipairs(groups) do
		local button = DungeonButton(index)
		local isSelected = settings.activityGroups[group.groupID] == true
		button.tlfgGroupID = group.groupID
		button.tlfgName = group.name
		button.tlfgSelected = isSelected
		-- Dungeon buttons always show the short name (KR, RLP, ...); the full name is in the tooltip.
		local abbreviated = group.abbreviation ~= nil and group.abbreviation ~= ""
		button:SetText(abbreviated and group.abbreviation or ShortName(group.name))
		-- Names sit left, after the icon; abbreviations are centered in the open space between the
		-- icon's right edge (26) and the checkmark's left edge (18 from the right).
		local label = button:GetFontString()
		if label then
			label:ClearAllPoints()
			label:SetPoint("LEFT", button, "LEFT", abbreviated and 26 or 28, 0)
			label:SetPoint("RIGHT", button, "RIGHT", abbreviated and -18 or -20, 0)
			label:SetJustifyH(abbreviated and "CENTER" or "LEFT")
		end
		local isExcluded = not isSelected and settings.excludedGroups ~= nil and settings.excludedGroups[group.groupID] == true
		button.tlfgExcluded = isExcluded
		button.tlfgCheck:SetShown(isSelected)
		button.tlfgCross:SetShown(isExcluded)
		button:SetNormalFontObject(isExcluded and "GameFontDisableSmall" or "GameFontNormalSmall")
		button.tlfgIcon:SetDesaturated(isExcluded)
		if group.icon then
			button.tlfgIcon:SetTexture(group.icon)
			button.tlfgIcon:Show()
		else
			button.tlfgIcon:Hide()
		end
		local column = (index - 1) % GRID_COLUMNS
		local row = math.floor((index - 1) / GRID_COLUMNS)
		button:SetHeight(buttonHeight)
		Place(button, column * (DUNGEON_BUTTON_WIDTH + GRID_GAP), y - row * (buttonHeight + GRID_GAP))
		button:Show()
	end
	for index = #groups + 1, #ui.dungeonButtons do
		ui.dungeonButtons[index]:Hide()
	end
	local rows = math.ceil(#groups / GRID_COLUMNS)
	if showGrid then
		ui.allDungeons:SetShown(rows > 0)
		ui.noDungeons:SetShown(rows > 0)
		if rows == 0 then
			ui.dungeonsUnavailable:SetText(L["Dungeon list not available yet"])
			Place(ui.dungeonsUnavailable, 0, y)
			ui.dungeonsUnavailable:Show()
			y = y - 18
		else
			ui.dungeonsUnavailable:Hide()
			y = y - rows * (buttonHeight + GRID_GAP)
		end
	end
	y = y - 5

	-- Dungeons: no difficulty buttons (Raids place them at the top, see LayoutDifficulty)
	if not raids then
		ui.difficultyLabel:Hide()
		for _, chip in ipairs(ui.difficulties) do
			chip:Hide()
		end
	end

	-- Dungeons: no boss list
	if not raids then
		for _, region in ipairs({ ui.bossesTitle, ui.freshRun, ui.noBosses, ui.bossArea, ui.bossesUnavailable }) do
			region:Hide()
		end
		ui.bossRowsTotal = 0
	end

	-- Ranges (hidden from the gear menu; while hidden the ranges don't filter, see Engine).
	-- Dungeons: Leader rating [min] [max] + quick minimum chips. Raids: Fresh run on the label row,
	-- Bosses defeated [min] [max], Members [min] [max], Most tanks [ ]  Most healers [ ].
	local showRanges = profile.showRanges ~= false
	local dungeonRanges = showRanges and not raids
	local raidRanges = showRanges and raids
	ui.rangesLabel:SetShown(showRanges)
	for _, region in ipairs({ ui.ratingLabel, ui.ratingMin, ui.ratingMax }) do
		region:SetShown(dungeonRanges)
	end
	for _, chip in ipairs(ui.chips) do
		chip:SetShown(dungeonRanges)
	end
	for _, region in ipairs(ui.raidRangeRegions) do
		region:SetShown(raidRanges)
	end
	if showRanges then
		Place(ui.rangesLabel, 0, y)
	end
	if dungeonRanges then
		y = y - 15
		Place(ui.ratingLabel, 0, y - 4)
		Place(ui.ratingMax, CONTENT_WIDTH - RATING_BOX_WIDTH, y)
		Place(ui.ratingMin, CONTENT_WIDTH - RATING_BOX_WIDTH * 2 - 12, y)
		SyncBox(ui.ratingMin, settings)
		SyncBox(ui.ratingMax, settings)
		y = y - 24
		for index, chip in ipairs(ui.chips) do
			Place(chip, (index - 1) * (chip:GetWidth() + GRID_GAP), y)
			chip.tlfgCheck:SetShown(settings.minLeaderRating == chip.tlfgRating)
		end
		y = y - 26
	elseif raidRanges then
		y = y - 15
		local rightMax = CONTENT_WIDTH - RAID_BOX_WIDTH
		local rightMin = CONTENT_WIDTH - RAID_BOX_WIDTH * 2 - 12
		Place(ui.membersLabel, 0, y - 4)
		Place(ui.membersMin, rightMin, y)
		Place(ui.membersMax, rightMax, y)
		y = y - 24
		local half = CONTENT_WIDTH / 2
		Place(ui.tanksLabel, 0, y - 4)
		Place(ui.tanksMax, half - RAID_BOX_WIDTH - 6, y)
		Place(ui.healersLabel, half + 2, y - 4)
		Place(ui.healersMax, rightMax, y)
		for _, box in ipairs({ ui.membersMin, ui.membersMax, ui.tanksMax, ui.healersMax }) do
			SyncBox(box, settings)
		end
		y = y - 28
	end

	-- Group needs (only checkboxes that apply to the player's class), two columns
	local player = ns.Snapshot.GetPlayerContext()
	local shown = 0
	local function Offered(check)
		return settings.fit[check] ~= nil and ns.ClassUtility.AppliesTo(check, player.classFile)
	end
	for _, check in ipairs(FIT_CHECKS) do
		if Offered(check) then
			shown = shown + 1
		end
	end
	ui.fitLabel:SetShown(shown > 0)
	if shown > 0 then
		Place(ui.fitLabel, 0, y)
		y = y - 14
	end
	local index = 0
	for _, check in ipairs(FIT_CHECKS) do
		local button = ui.fit[check]
		if Offered(check) then
			local column = index % 2
			local row = math.floor(index / 2)
			Place(button, -2 + column * NEEDS_COLUMN_WIDTH, y - row * 22)
			if type(button.Text) == "table" then
				button.Text:SetText(FitLabel(check))
			end
			button:SetChecked(settings.fit[check] == true)
			button:Show()
			index = index + 1
		else
			button:Hide()
		end
	end
	if shown > 0 then
		y = y - math.ceil(shown / 2) * 22 - 2
	end

	-- I sign up as [Tank] [Healer] [DPS]; roles the class can't play are shown locked
	local available = ns.Snapshot.AvailableRoles() or { TANK = true, HEALER = true, DAMAGER = true }
	local current = {}
	for _, role in ipairs(ns.Snapshot.SignUpRoles()) do
		current[role] = true
	end
	Place(ui.signUpLabel, 0, y - 6)
	local pillWidth = (CONTENT_WIDTH - SIGN_UP_LABEL_WIDTH - GRID_GAP * 2) / 3
	for roleIndex, role in ipairs(SIGN_UP_ROLES) do
		local button = ui.signUp[role]
		local locked = not available[role]
		button.tlfgLocked = locked
		button.tlfgSelected = not locked and current[role] == true
		button:SetWidth(pillWidth)
		Place(button, SIGN_UP_LABEL_WIDTH + (roleIndex - 1) * (pillWidth + GRID_GAP), y)
		button:SetEnabled(not locked)
		button.tlfgCheck:SetShown(button.tlfgSelected)
		button.tlfgRoleIcon:SetAtlas(RoleIconAtlas(role, locked))
		button.tlfgRoleIcon:SetDesaturated(locked)
		button.tlfgLock:SetShown(locked)
		button:Show()
	end
	y = y - 28

	return -y, rows
end

local function Layout(settings)
	local pve = ns.FrameMap.Get("pve")
	local height = pve and pve:GetHeight() or 0
	if height > 0 then
		panel:SetHeight(height)
	end
	local available = panel:GetHeight() - CONTENT_TOP - CONTENT_BOTTOM - FOOTER_HEIGHT
	local buttonHeight = DUNGEON_BUTTON_MAX_HEIGHT
	local needed, rows = LayoutPass(settings, buttonHeight)
	if needed > available and rows > 0 then
		local shrink = math.ceil((needed - available) / rows)
		buttonHeight = math.max(DUNGEON_BUTTON_MIN_HEIGHT, buttonHeight - shrink)
		needed = LayoutPass(settings, buttonHeight)
	end
	-- Still too tall (a season whose raids have many bosses): the boss list keeps the rows that fit
	-- and the wheel scrolls the rest into view.
	if needed > available and (ui.bossRowsTotal or 0) > MIN_BOSS_ROWS then
		local over = math.ceil((needed - available) / BOSS_ROW_STEP)
		needed = LayoutPass(settings, buttonHeight, ui.bossRowsTotal - over)
	end
	if needed > available then
		ns.DebugOnce("panel-overflow", "Filter panel content is %d px taller than the panel", needed - available)
	end
end

local function MatchCountText(count)
	if count == 0 then
		return L["Nothing matches"]
	elseif count == 1 then
		return L["1 group matches"]
	end
	return string.format(L["%d groups match"], count)
end

local function StatusText(run)
	if not run then
		return ""
	end
	if run.state == "filtering" then
		return MatchCountText(#run.visible)
	elseif run.state == "unfiltered" then
		return MatchCountText(run.totalCount)
	elseif run.state == "paused" then
		return string.format(L["Filters paused (%s)"], PauseReasonText(run.pauseReason))
	elseif run.state == "error" then
		return L["Filter error: showing all groups"]
	elseif run.state == "off" then
		return L["Filter off"]
	end
	return ""
end

-- full = true rebuilds controls from settings; otherwise only visibility and the footer change
-- (result updates arrive often and must not disturb an open dropdown menu).
function FilterPanel:Refresh(full)
	if not panel then
		return
	end
	local categoryID = ns.Categories.GetActive()
	local settings = Current()
	-- Hidden while the filter is off: the spyglass button in the Group Finder turns it back on.
	local show = settings ~= nil and ns.Categories.IsFiltered(categoryID) and ns.Settings.Profile().filterEnabled == true
	panel:SetShown(show and true or false)
	if not show then
		return
	end

	ui.status:SetText(StatusText(ns.Engine.GetLastRun()))
	if not full then
		return
	end
	Layout(settings)
end

function FilterPanel:RequestRefresh(full)
	local ok, err = pcall(self.Refresh, self, full)
	if not ok then
		ns.DebugOnce("filterpanel-" .. tostring(err), "Filter panel error: %s", err)
		if panel then
			panel:Hide()
		end
	end
end

function FilterPanel:OnEnable()
	if not Build() then
		ns.DebugOnce("filterpanel-build", "Filter panel: Group Finder frames not found")
		return
	end
	self:RegisterMessage(ns.MSG.RunComplete, function()
		FilterPanel:RequestRefresh(false)
	end)
	self:RegisterMessage(ns.MSG.SettingsChanged, function()
		FilterPanel:RequestRefresh(true)
	end)
	self:RegisterMessage(ns.MSG.ActiveCategoryChanged, function()
		FilterPanel:RequestRefresh(true)
	end)
	panel:HookScript("OnShow", function()
		FilterPanel:RequestRefresh(true)
		ns.ProfileDock:OnPanelVisibilityChanged()
	end)
	panel:HookScript("OnHide", function()
		ns.ProfileDock:OnPanelVisibilityChanged()
	end)
end
