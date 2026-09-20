-- LFG Spyglass on/off button in Blizzard's search panel: a square button in the
-- same style as Blizzard's Refresh button, with Blizzard's spyglass icon, placed just above the
-- Filter button. Bright = filter on (LFG Spyglass panel shown); greyed out = filter off (stock Group
-- Finder). It is an addon-owned frame; no Blizzard control is moved or changed.
local _, ns = ...

local ToggleButton = ns.NewModule("ToggleButton")
local L = ns.L

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local SIZE = 26

local button

function ToggleButton.GetFrame()
	return button
end

function ToggleButton:Refresh()
	if not button then
		return
	end
	button:SetShown(ns.Categories.IsFiltered(ns.Categories.GetActive()))
	local on = ns.Settings.Profile().filterEnabled == true
	button.Icon:SetDesaturated(not on)
	button.Icon:SetAlpha(on and 1 or 0.55)
end

local function ShowTooltip(self)
	local on = ns.Settings.Profile().filterEnabled == true
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, on and L["LFG Spyglass filter: on"] or L["LFG Spyglass filter: off"])
	GameTooltip_AddNormalLine(GameTooltip, on and L["Click to turn the filter off and show the stock Group Finder."]
		or L["Click to turn the filter on."])
	GameTooltip:Show()
end

local function Build()
	local searchPanel = ns.FrameMap.Get("searchPanel")
	if not searchPanel then
		return false
	end
	button = CreateFrame("Button", nil, searchPanel)
	button:SetSize(SIZE, SIZE)
	local filterButton = ns.FrameMap.Get("filterButton")
	if filterButton then
		button:SetPoint("BOTTOMRIGHT", filterButton, "TOPRIGHT", 2, 2)
	else
		button:SetPoint("TOPRIGHT", searchPanel, "TOPRIGHT", -8, -30)
	end

	-- Same textures as Blizzard's Refresh button.
	button:SetNormalTexture("Interface\\Buttons\\UI-SquareButton-Up")
	button:SetPushedTexture("Interface\\Buttons\\UI-SquareButton-Down")
	button:SetDisabledTexture("Interface\\Buttons\\UI-SquareButton-Disabled")
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

	-- The icon lives on the marker layer, so Match my UI's suite look can't hide it.
	button.Icon = ns.Skin.MarkerLayer(button):CreateTexture(nil, "ARTWORK", nil, 5)
	button.Icon:SetSize(14, 14)
	button.Icon:SetPoint("CENTER", button, "CENTER", -1, 0)
	button.Icon:SetTexture(ICON)
	button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	button:SetScript("OnMouseDown", function(self)
		self.Icon:SetPoint("CENTER", self, "CENTER", -2, -1)
	end)
	button:SetScript("OnMouseUp", function(self)
		self.Icon:SetPoint("CENTER", self, "CENTER", -1, 0)
	end)
	button:SetScript("OnClick", function(self)
		local profile = ns.Settings.Profile()
		profile.filterEnabled = not profile.filterEnabled
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		ns.Settings:Changed()
		if GameTooltip:GetOwner() == self then
			ShowTooltip(self)
		end
	end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	ns.Skin.Apply("button", button)
	return true
end

function ToggleButton:OnEnable()
	if not Build() then
		ns.DebugOnce("togglebutton-build", "Toggle button: search panel not found")
		return
	end
	self:RegisterMessage(ns.MSG.SettingsChanged, "Refresh")
	self:RegisterMessage(ns.MSG.ActiveCategoryChanged, "Refresh")
	self:Refresh()
end
