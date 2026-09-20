-- Reload confirmation for the appearance choice. Looks like Blizzard's own popups (built on the
-- same dialog base template and dialog-box button art, where Blizzard's first popup sits) but is LFG
-- Spyglass's own frame: Blizzard's shared popups and StaticPopupDialogs are never used.
local _, ns = ...

local ReloadDialog = {}
ns.ReloadDialog = ReloadDialog

local L = ns.L
local WIDTH, HEIGHT = 320, 94
local BUTTON_WIDTH, BUTTON_HEIGHT = 128, 21

local dialog

-- A button drawn with the dialog-box button art Blizzard's popups use.
local function NewDialogButton(parent, text, onClick)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
	for _, part in ipairs({ { "SetNormalTexture", "Up" }, { "SetPushedTexture", "Down" },
		{ "SetDisabledTexture", "Disabled" }, { "SetHighlightTexture", "Highlight" } }) do
		button[part[1]](button, "Interface\\Buttons\\UI-DialogBox-Button-" .. part[2])
	end
	for _, region in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(),
		button:GetDisabledTexture(), button:GetHighlightTexture() }) do
		if region then
			region:SetTexCoord(0, 1, 0, 0.71875)
		end
	end
	local highlight = button:GetHighlightTexture()
	if highlight then
		highlight:SetBlendMode("ADD")
	end
	button:SetNormalFontObject("GameFontNormal")
	button:SetHighlightFontObject("GameFontHighlight")
	button:SetDisabledFontObject("GameFontDisable")
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function Build()
	local ok, frame = pcall(CreateFrame, "Frame", nil, UIParent, "StaticPopupBaseTemplate")
	if not ok or not frame then
		ns.DebugOnce("reload-dialog", "Reload dialog unavailable: %s", frame)
		return false
	end
	dialog = frame
	dialog:SetSize(WIDTH, HEIGHT)
	dialog:SetPoint("TOP", UIParent, "TOP", 0, -135)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetToplevel(true)
	dialog:EnableMouse(true)
	dialog:Hide()

	local text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetWidth(WIDTH - 40)
	text:SetPoint("TOP", dialog, "TOP", 0, -18)
	text:SetText(L["Reload the interface now to apply the new appearance?"])

	local accept = NewDialogButton(dialog, ACCEPT or "Accept", function()
		ReloadUI()
	end)
	accept:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -6, 16)
	local cancel = NewDialogButton(dialog, CANCEL or "Cancel", function()
		dialog:Hide()
	end)
	cancel:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 6, 16)
	dialog.tlfgAccept, dialog.tlfgCancel = accept, cancel
	return true
end

-- Ask to reload now; Cancel keeps the new choice for the next reload or login.
function ReloadDialog.Show()
	if not dialog and not Build() then
		return
	end
	dialog:Show()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
end

function ReloadDialog.Hide()
	if dialog then
		dialog:Hide()
	end
end

function ReloadDialog.GetFrame()
	return dialog
end
