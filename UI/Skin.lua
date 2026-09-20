-- Appearance: LFG Spyglass's own frames can be drawn dark instead of Blizzard's look. Opt-in
-- (profile.appearance), read once at load, so a change needs a reload. The only file that draws an
-- appearance. Nothing here touches Blizzard's frames or the result rows, and it ships no media: the
-- Dark appearance is plain colors plus Blizzard's own fonts and icon art.
local _, ns = ...

local Skin = {}
ns.Skin = Skin

local STOCK, DARK = "stock", "dark"
local MARKER_LEVEL_OFFSET = 3 -- above our backdrop
local WHITE = [[Interface\Buttons\WHITE8X8]]

-- Dark palette: { r, g, b, a }
local DARK_COLORS = {
	panel = { 0.06, 0.06, 0.07, 0.96 },
	control = { 0.11, 0.11, 0.12, 0.95 },
	input = { 0.03, 0.03, 0.04, 0.95 },
	border = { 0.24, 0.24, 0.27, 1 },
	hover = { 1, 1, 1, 0.07 },
	pressed = { 0, 0, 0, 0.25 },
	accent = { 1, 0.82, 0 }, -- Blizzard's gold, for our checkmarks
}

local appearance = STOCK -- the appearance this session was loaded with
local decided, scheduled = false, false
local registry = {} -- { kind, frame } for every control, in creation order
local drawn = setmetatable({}, { __mode = "k" })
local tinted = setmetatable({}, { __mode = "k" }) -- our checkmarks

-- The appearance to use, from the saved choice. Unknown values fall back to stock. Pure.
function Skin.Resolve(saved)
	return saved == DARK and DARK or STOCK
end

-- Fade every texture the control draws itself; ours live on the marker layer (MarkerLayer), so they
-- stay. Frames are LFG Spyglass's own.
local function FadeRegions(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "Texture" then
			region:SetAlpha(0)
		end
	end
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
		local texture = frame[getter] and frame[getter](frame)
		if texture then
			texture:SetAlpha(0)
		end
	end
end

local function SetColor(texture, color)
	texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

-- Flat fill with a 1px border, on a child frame under the control's content.
local function Backdrop(frame, fill)
	local backdrop = frame.tlfgBackdrop
	if not backdrop then
		backdrop = CreateFrame("Frame", nil, frame)
		backdrop:SetAllPoints(frame)
		backdrop:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
		backdrop.fill = backdrop:CreateTexture(nil, "BACKGROUND")
		backdrop.fill:SetAllPoints(backdrop)
		backdrop.edges = {}
		for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local line = backdrop:CreateTexture(nil, "BORDER")
			if edge == "TOP" or edge == "BOTTOM" then
				line:SetHeight(1)
				line:SetPoint(edge .. "LEFT")
				line:SetPoint(edge .. "RIGHT")
			else
				line:SetWidth(1)
				line:SetPoint("TOP" .. edge)
				line:SetPoint("BOTTOM" .. edge)
			end
			SetColor(line, DARK_COLORS.border)
			backdrop.edges[#backdrop.edges + 1] = line
		end
		frame.tlfgBackdrop = backdrop
	end
	SetColor(backdrop.fill, fill)
	return backdrop
end

-- Hover and press feedback, since the control's own textures are faded.
local function AddButtonStates(frame, backdrop)
	local hover = backdrop:CreateTexture(nil, "ARTWORK")
	hover:SetAllPoints(backdrop)
	hover:SetTexture(WHITE)
	SetColor(hover, DARK_COLORS.hover)
	hover:Hide()
	local pressed = backdrop:CreateTexture(nil, "ARTWORK")
	pressed:SetAllPoints(backdrop)
	pressed:SetTexture(WHITE)
	SetColor(pressed, DARK_COLORS.pressed)
	pressed:Hide()
	frame:HookScript("OnEnter", function() hover:Show() end)
	frame:HookScript("OnLeave", function() hover:Hide() end)
	frame:HookScript("OnMouseDown", function() pressed:Show() end)
	frame:HookScript("OnMouseUp", function() pressed:Hide() end)
	frame:HookScript("OnHide", function()
		hover:Hide()
		pressed:Hide()
	end)
end

local DRAW = {
	panel = function(frame)
		-- PortraitFrameTemplate: Blizzard's border and background come off, ours goes on.
		for _, key in ipairs({ "NineSlice", "Bg", "TitleBg", "PortraitContainer" }) do
			local part = frame[key]
			if type(part) == "table" and part.Hide then
				part:Hide()
			end
		end
		FadeRegions(frame)
		Backdrop(frame, DARK_COLORS.panel)
	end,
	button = function(frame)
		FadeRegions(frame)
		AddButtonStates(frame, Backdrop(frame, DARK_COLORS.control))
	end,
	checkbox = function(frame)
		local checked = frame.GetCheckedTexture and frame:GetCheckedTexture()
		FadeRegions(frame)
		if checked then
			checked:SetAlpha(1) -- the tick stays, in our accent color
			checked:SetVertexColor(DARK_COLORS.accent[1], DARK_COLORS.accent[2], DARK_COLORS.accent[3])
		end
		AddButtonStates(frame, Backdrop(frame, DARK_COLORS.input))
	end,
	editbox = function(frame)
		FadeRegions(frame)
		Backdrop(frame, DARK_COLORS.input)
	end,
	accent = function(texture)
		tinted[texture] = true
		texture:SetVertexColor(DARK_COLORS.accent[1], DARK_COLORS.accent[2], DARK_COLORS.accent[3])
	end,
}

local function DrawOne(kind, frame)
	if drawn[frame] then
		return
	end
	drawn[frame] = true
	local draw = DRAW[kind]
	if not draw then
		return
	end
	local ok, err = pcall(draw, frame)
	if not ok then
		ns.DebugOnce("skin-" .. kind .. "-" .. tostring(err), "Dark appearance: %s left stock (%s)", kind, err)
	end
end

local function Decide()
	decided = true
	appearance = Skin.Resolve(ns.Settings.Profile().appearance)
	if appearance == STOCK then
		return
	end
	for _, entry in ipairs(registry) do
		DrawOne(entry[1], entry[2])
	end
end

local function Schedule()
	if scheduled then
		return
	end
	scheduled = true
	C_Timer.After(0, Decide)
end

-- Draw a control LFG Spyglass created in the chosen appearance. kind: "panel", "button",
-- "checkbox", "editbox", or "accent" for one of our checkmark textures.
function Skin.Apply(kind, frame)
	if type(frame) ~= "table" then
		return
	end
	registry[#registry + 1] = { kind, frame }
	if not decided then
		Schedule()
	elseif appearance ~= STOCK then
		DrawOne(kind, frame)
	end
end

-- Child frame over a control that holds its markers (icons, checkmarks, crosses), above the
-- appearance's backdrop. Created once per control; doesn't take the mouse.
function Skin.MarkerLayer(control)
	local layer = control.tlfgMarkers
	if not layer then
		layer = CreateFrame("Frame", nil, control)
		layer:SetAllPoints(control)
		layer:SetFrameLevel(control:GetFrameLevel() + MARKER_LEVEL_OFFSET)
		control.tlfgMarkers = layer
	end
	return layer
end

-- The appearance running this session ("stock" or "dark").
function Skin.Current()
	return appearance
end

function Skin.IsDark()
	return appearance == DARK
end

-- The saved choice differs from the one this session was loaded with.
function Skin.NeedsReload()
	return decided and Skin.Resolve(ns.Settings.Profile().appearance) ~= appearance
end
