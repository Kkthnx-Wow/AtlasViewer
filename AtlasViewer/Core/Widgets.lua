-- Widget kit. One visual language: slate fills, the game's own atlas art for frames,
-- buttons, borders and bars, and one ember accent for selection and active state.
-- Every piece of game art is looked up first and falls back to flat widgets, so a
-- client without it still gets a working window. No Blizzard templates and no
-- backdrop API, so nothing depends on a client keeping a template alive.
local _, ns = ...
local C, F = ns.C, ns.F

local CreateFrame = CreateFrame
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT

local Colors, Layout = C.Colors, C.Layout

local function setColor(texture, color, alpha)
	texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
end
F.SetColor = setColor

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------
function F.CreateText(parent, size, color, justify, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(STANDARD_TEXT_FONT, size or 12, "")
	color = color or Colors.text
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

-- Shorten from the middle so both the shared prefix and the distinguishing tail
-- of an atlas name stay visible. Measures with the real font, no guessed widths.
function F.SetFittedText(fs, text, width)
	fs:SetText(text)
	local natural = fs:GetStringWidth()
	if natural <= width or #text < 8 then
		return
	end
	local keep = math.max(4, math.floor(#text * width / natural) - 3)
	local head = math.ceil(keep * 0.4)
	fs:SetText(text:sub(1, head) .. "..." .. text:sub(#text - (keep - head) + 1))
end

-- ---------------------------------------------------------------------------
-- 1 px outline for small controls where the full edge would be too heavy.
-- ---------------------------------------------------------------------------
local function outlineSetColor(outline, color, alpha)
	for i = 1, 4 do
		outline[i]:SetColorTexture(color[1], color[2], color[3], alpha or 1)
	end
end

function F.CreateOutline(frame, color, alpha)
	local o = { SetColor = outlineSetColor }
	for i = 1, 4 do
		o[i] = frame:CreateTexture(nil, "BORDER")
	end
	o[1]:SetPoint("TOPLEFT")
	o[1]:SetPoint("TOPRIGHT")
	o[1]:SetHeight(1)
	o[2]:SetPoint("BOTTOMLEFT")
	o[2]:SetPoint("BOTTOMRIGHT")
	o[2]:SetHeight(1)
	o[3]:SetPoint("TOPLEFT")
	o[3]:SetPoint("BOTTOMLEFT")
	o[3]:SetWidth(1)
	o[4]:SetPoint("TOPRIGHT")
	o[4]:SetPoint("BOTTOMRIGHT")
	o[4]:SetWidth(1)
	outlineSetColor(o, color or Colors.edge, alpha)
	frame.Outline = o
	return o
end

-- Inner borders: the game's tooltip frame art, so panels and thumbnails share the
-- metal frame's silver. Falls back to the flat 1 px outline when the kit is missing.
function F.CreateBorder(frame)
	if not F.CreateMetalFrame(frame, Layout.panelKit, 0) then
		F.CreateOutline(frame)
	end
end

-- Tint whichever border a frame ended up with. The art is silver, so a colour
-- multiplies it; alpha dims it.
function F.SetBorderColor(frame, color, alpha)
	if frame.Metal then
		for _, piece in pairs(frame.Metal) do
			piece:SetVertexColor(color[1], color[2], color[3], alpha or 1)
		end
	elseif frame.Outline then
		frame.Outline:SetColor(color, alpha)
	end
end

-- ---------------------------------------------------------------------------
-- Panel: flat fill with an optional 1 px outline.
-- ---------------------------------------------------------------------------
function F.CreatePanel(parent, fill, outlined)
	local p = CreateFrame("Frame", nil, parent)
	p.Bg = p:CreateTexture(nil, "BACKGROUND")
	p.Bg:SetAllPoints()
	setColor(p.Bg, fill or Colors.panel)
	if outlined then
		F.CreateBorder(p)
		if p.Metal then
			-- The border has rounded corners, so the fill stops short of them.
			p.Bg:ClearAllPoints()
			p.Bg:SetPoint("TOPLEFT", Layout.borderFill, -Layout.borderFill)
			p.Bg:SetPoint("BOTTOMRIGHT", -Layout.borderFill, Layout.borderFill)
		end
	end
	return p
end

-- ---------------------------------------------------------------------------
-- Buttons. Hover lifts the fill and lights the outline; `active` (toggle state)
-- paints the label and outline in the accent colour.
-- ---------------------------------------------------------------------------
local function applyButtonState(btn)
	local lit = btn.active or btn.hovered
	setColor(btn.Bg, btn.hovered and Colors.hover or Colors.raised)
	btn.Outline:SetColor(btn.active and Colors.accent or (btn.hovered and Colors.mute or Colors.edge))
	local c = btn.active and Colors.accent or (lit and Colors.text or Colors.mute)
	btn.Text:SetTextColor(c[1], c[2], c[3])
end

function F.CreateFlatButton(parent, text, width, height)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width or 90, height or 24)
	btn.Bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.Bg:SetAllPoints()
	F.CreateOutline(btn)
	btn.Text = F.CreateText(btn, 12, Colors.mute, "CENTER")
	btn.Text:SetPoint("LEFT", 6, 0)
	btn.Text:SetPoint("RIGHT", -6, 0)
	btn.Text:SetText(text or "")

	function btn:SetActive(on)
		self.active = on and true or false
		applyButtonState(self)
	end
	btn:HookScript("OnEnter", function(self)
		self.hovered = true
		applyButtonState(self)
	end)
	btn:HookScript("OnLeave", function(self)
		self.hovered = false
		applyButtonState(self)
	end)
	applyButtonState(btn)
	return btn
end

-- ---------------------------------------------------------------------------
-- Text button from the game's three-slice red button: a left cap, a tiled centre
-- and a right cap, scaled to the button height. Narrow buttons trim the caps the
-- way Blizzard's own template does. A toggled-on button uses the gold variant
-- when the client has it. Flat button when the art is missing.
-- ---------------------------------------------------------------------------
local RED, GOLD = "128-RedButton", "128-GoldRedButton"

local function kitComplete(kit)
	return F.AtlasExists(kit .. "-Left") and F.AtlasExists(kit .. "-Right") and F.AtlasExists("_" .. kit .. "-Center")
end

-- Caps scale to the button height. When both caps together are wider than the
-- button, slice width off the larger one first, then both equally.
local function layoutCaps(btn)
	local left, right = btn.leftInfo, btn.rightInfo
	local scale = btn:GetHeight() / left.height
	btn.Left:SetScale(scale)
	btn.Right:SetScale(scale)
	local leftW, rightW = left.width * scale, right.width * scale
	local extra = leftW + rightW - btn:GetWidth()
	if extra <= 0 then
		btn.Left:SetTexCoord(0, 1, 0, 1)
		btn.Left:SetWidth(left.width)
		btn.Right:SetTexCoord(0, 1, 0, 1)
		btn.Right:SetWidth(right.width)
		return
	end
	local newLeft, newRight = leftW, rightW
	if leftW - extra > rightW then
		newLeft = leftW - extra
	elseif rightW - extra > leftW then
		newRight = rightW - extra
	else
		if leftW ~= rightW then
			extra = extra - math.abs(leftW - rightW)
			newLeft = math.min(leftW, rightW)
			newRight = newLeft
		end
		newLeft = newLeft - extra / 2
		newRight = newRight - extra / 2
	end
	btn.Left:SetTexCoord(0, newLeft / leftW, 0, 1)
	btn.Left:SetWidth(newLeft / scale)
	btn.Right:SetTexCoord(1 - newRight / rightW, 1, 0, 1)
	btn.Right:SetWidth(newRight / scale)
end

local goldAvailable -- resolved on first use, the client does not change mid-session
local TEXT_NORMAL, TEXT_HOVER, TEXT_ACTIVE = { 1, 0.82, 0 }, { 1, 0.93, 0.55 }, { 1, 1, 1 }

local function paintSlice(btn, suffix)
	if goldAvailable == nil then
		goldAvailable = kitComplete(GOLD)
	end
	local kit = (btn.active and goldAvailable) and GOLD or RED
	local function pick(name)
		local full = name .. (suffix or "")
		return F.AtlasExists(full) and full or name
	end
	btn.Left:SetAtlas(pick(kit .. "-Left"), true)
	btn.Right:SetAtlas(pick(kit .. "-Right"), true)
	btn.Center:SetAtlas(pick("_" .. kit .. "-Center"))
	layoutCaps(btn)
	local c = btn.active and TEXT_ACTIVE or (btn.hovered and TEXT_HOVER or TEXT_NORMAL)
	btn.Text:SetTextColor(c[1], c[2], c[3])
end

function F.CreateButton(parent, text, width, height)
	if not kitComplete(RED) then
		return F.CreateFlatButton(parent, text, width, height)
	end
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width or 90, height or 24)
	btn.leftInfo = C_Texture.GetAtlasInfo(RED .. "-Left")
	btn.rightInfo = C_Texture.GetAtlasInfo(RED .. "-Right")

	btn.Left = btn:CreateTexture(nil, "BACKGROUND")
	btn.Left:SetPoint("TOPLEFT")
	btn.Right = btn:CreateTexture(nil, "BACKGROUND")
	btn.Right:SetPoint("TOPRIGHT")
	btn.Center = btn:CreateTexture(nil, "BACKGROUND")
	btn.Center:SetHorizTile(true)
	btn.Center:SetPoint("TOPLEFT", btn.Left, "TOPRIGHT")
	btn.Center:SetPoint("BOTTOMRIGHT", btn.Right, "BOTTOMLEFT")

	btn.Text = F.CreateText(btn, 12, TEXT_NORMAL, "CENTER")
	btn.Text:SetPoint("LEFT", 6, 0)
	btn.Text:SetPoint("RIGHT", -6, 0)
	btn.Text:SetText(text or "")

	if F.AtlasExists(RED .. "-Highlight") then
		btn:SetHighlightAtlas(RED .. "-Highlight")
	end

	function btn:SetActive(on)
		self.active = on and true or false
		paintSlice(self)
	end
	btn:HookScript("OnMouseDown", function(self)
		if self:IsEnabled() then
			self.Text:SetPoint("LEFT", 4, -1)
			self.Text:SetPoint("RIGHT", -8, -1)
			paintSlice(self, "-Pressed")
		end
	end)
	btn:HookScript("OnMouseUp", function(self)
		self.Text:SetPoint("LEFT", 6, 0)
		self.Text:SetPoint("RIGHT", -6, 0)
		paintSlice(self)
	end)
	btn:HookScript("OnEnter", function(self)
		self.hovered = true
		paintSlice(self)
	end)
	btn:HookScript("OnLeave", function(self)
		self.hovered = false
		paintSlice(self)
	end)
	btn:HookScript("OnDisable", function(self)
		paintSlice(self, "-Disabled")
	end)
	btn:HookScript("OnEnable", function(self)
		paintSlice(self)
	end)
	btn:SetScript("OnSizeChanged", function(self)
		layoutCaps(self)
	end)
	paintSlice(btn)
	return btn
end

-- Attach a plain tooltip without replacing the hover handlers above.
function F.SetTooltip(frame, title, body)
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(title, 1, 1, 1)
		if body then
			GameTooltip:AddLine(body, 0.7, 0.75, 0.82, true)
		end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", GameTooltip_Hide)
end

-- ---------------------------------------------------------------------------
-- Edit box. Wears the game's search-box art (left cap, stretched middle, right
-- cap) when the client has it, and lights it amber while focused. opts.search adds
-- the magnifier and a clear button. Flat fill and outline otherwise.
-- ---------------------------------------------------------------------------
local SEARCH_ART = { "common-search-border-left", "common-search-border-middle", "common-search-border-right" }

function F.CreateEditBox(parent, width, height, fontSize, opts)
	opts = opts or {}
	height = height or 26
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width or 200, height)
	box:SetAutoFocus(false)
	box:SetFont(STANDARD_TEXT_FONT, fontSize or 13, "")
	box:SetTextColor(Colors.text[1], Colors.text[2], Colors.text[3])

	-- Dark fill sits under the art so text stays readable on any background.
	box.Bg = box:CreateTexture(nil, "BACKGROUND")
	box.Bg:SetPoint("TOPLEFT", 3, -3)
	box.Bg:SetPoint("BOTTOMRIGHT", -3, 3)
	setColor(box.Bg, Colors.void)

	local useArt = true
	for i = 1, #SEARCH_ART do
		useArt = useArt and C_Texture.GetAtlasInfo(SEARCH_ART[i]) ~= nil
	end
	local tint
	if useArt then
		-- The art is 16 x 40 caps on a 40 px tall box, so caps scale with the height.
		local cap = height * 0.4
		local left = box:CreateTexture(nil, "BACKGROUND", nil, 1)
		left:SetAtlas(SEARCH_ART[1])
		left:SetSize(cap, height)
		left:SetPoint("LEFT")
		local right = box:CreateTexture(nil, "BACKGROUND", nil, 1)
		right:SetAtlas(SEARCH_ART[3])
		right:SetSize(cap, height)
		right:SetPoint("RIGHT")
		local middle = box:CreateTexture(nil, "BACKGROUND", nil, 1)
		middle:SetAtlas(SEARCH_ART[2])
		middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
		middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
		tint = function(c)
			c = c or { 1, 1, 1 }
			left:SetVertexColor(c[1], c[2], c[3])
			middle:SetVertexColor(c[1], c[2], c[3])
			right:SetVertexColor(c[1], c[2], c[3])
		end
	else
		F.CreateOutline(box)
		tint = function(c)
			box.Outline:SetColor(c or Colors.edge)
		end
	end
	-- Resting tint. The art is silver, so this darkens it to sit quietly until focus.
	local rest = Colors.edge
	tint(rest)

	local leftInset, rightInset = 10, 10
	if opts.search then
		if F.AtlasExists("common-search-magnifyingglass") then
			local glass = box:CreateTexture(nil, "OVERLAY")
			glass:SetAtlas("common-search-magnifyingglass")
			glass:SetSize(14, 14)
			glass:SetPoint("LEFT", 10, 0)
			glass:SetAlpha(0.7)
			leftInset = 30
		end
		if F.AtlasExists("common-search-clearbutton") then
			local clear = CreateFrame("Button", nil, box)
			clear:SetSize(18, 18)
			clear:SetPoint("RIGHT", -8, 0)
			clear.Art = clear:CreateTexture(nil, "OVERLAY")
			clear.Art:SetAllPoints()
			clear.Art:SetAtlas("common-search-clearbutton")
			clear.Art:SetAlpha(0.5)
			clear:SetScript("OnEnter", function(self)
				self.Art:SetAlpha(1)
			end)
			clear:SetScript("OnLeave", function(self)
				self.Art:SetAlpha(0.5)
			end)
			clear:SetScript("OnClick", function()
				box:SetText("")
				box:ClearFocus()
			end)
			clear:Hide()
			box:HookScript("OnTextChanged", function(self)
				clear:SetShown(self:GetText() ~= "")
			end)
			rightInset = 30
		end
	end
	box:SetTextInsets(leftInset, rightInset, 0, 0)

	box:HookScript("OnEditFocusGained", function()
		tint(Colors.accent)
	end)
	box:HookScript("OnEditFocusLost", function()
		tint(rest)
	end)
	return box
end

-- ---------------------------------------------------------------------------
-- Slider. Uses the game's minimal slider bar (end caps, tiled middle and a round
-- knob) when the client has it, a hairline track and amber bar otherwise.
-- ---------------------------------------------------------------------------
function F.CreateSlider(parent, minVal, maxVal, step, length)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(minVal, maxVal)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)

	local art = F.AtlasExists("Minimal_SliderBar_Left")
		and F.AtlasExists("_Minimal_SliderBar_Middle")
		and F.AtlasExists("Minimal_SliderBar_Right")
		and F.AtlasExists("Minimal_SliderBar_Button")
	if art then
		s:SetSize(length, 19)
		local left = s:CreateTexture(nil, "BACKGROUND")
		left:SetAtlas("Minimal_SliderBar_Left", true)
		left:SetPoint("LEFT")
		local right = s:CreateTexture(nil, "BACKGROUND")
		right:SetAtlas("Minimal_SliderBar_Right", true)
		right:SetPoint("RIGHT")
		local middle = s:CreateTexture(nil, "BACKGROUND")
		middle:SetAtlas("_Minimal_SliderBar_Middle", true)
		middle:SetHorizTile(true)
		middle:SetPoint("LEFT", left, "RIGHT")
		middle:SetPoint("RIGHT", right, "LEFT")
		local thumb = s:CreateTexture(nil, "OVERLAY")
		thumb:SetAtlas("Minimal_SliderBar_Button", true)
		s:SetThumbTexture(thumb)
		s.Thumb = thumb
	else
		s:SetSize(length, 14)
		local track = s:CreateTexture(nil, "BACKGROUND")
		setColor(track, Colors.raised)
		track:SetPoint("LEFT")
		track:SetPoint("RIGHT")
		track:SetHeight(4)
		local thumb = s:CreateTexture(nil, "OVERLAY")
		setColor(thumb, Colors.accent)
		thumb:SetSize(8, 14)
		s:SetThumbTexture(thumb)
		s.Thumb = thumb
	end
	return s
end

-- ---------------------------------------------------------------------------
-- Vertical scrollbar from the game's minimal scrollbar art: a track and a thumb,
-- each a top cap, a stretched middle and a bottom cap. The thumb lights on hover
-- and darkens while dragged. onChange(value) fires on user input only.
-- ---------------------------------------------------------------------------
local BAR = "minimal-scrollbar-small-"

local function threePart(parent, layer, top, mid, bottom, tileMid)
	local a = parent:CreateTexture(nil, layer)
	a:SetAtlas(top, true)
	a:SetPoint("TOP")
	local z = parent:CreateTexture(nil, layer)
	z:SetAtlas(bottom, true)
	z:SetPoint("BOTTOM")
	local m = parent:CreateTexture(nil, layer)
	m:SetAtlas(mid, tileMid or false)
	if tileMid then
		m:SetVertTile(true)
	end
	m:SetPoint("TOPLEFT", a, "BOTTOMLEFT")
	m:SetPoint("BOTTOMRIGHT", z, "TOPRIGHT")
	return { top = a, mid = m, bottom = z }
end

function F.CreateScrollbar(parent, onChange)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetWidth(8)
	bar:EnableMouse(true)
	bar:SetHitRectInsets(-4, -4, 0, 0)
	bar.min, bar.max, bar.value, bar.ratio = 0, 0, 0, 1

	local flat = not (F.AtlasExists(BAR .. "track-top") and F.AtlasExists(BAR .. "thumb-top"))
	local thumb = CreateFrame("Button", nil, bar)
	thumb:SetWidth(8)
	thumb:SetHitRectInsets(-4, -4, 0, 0)
	bar.Thumb = thumb

	local thumbParts
	if flat then
		local track = bar:CreateTexture(nil, "BACKGROUND")
		setColor(track, Colors.raised)
		track:SetAllPoints()
		bar.thumbFill = thumb:CreateTexture(nil, "ARTWORK")
		setColor(bar.thumbFill, Colors.accent)
		bar.thumbFill:SetAllPoints()
	else
		threePart(bar, "BACKGROUND", BAR .. "track-top", "!" .. BAR .. "track-middle", BAR .. "track-bottom", true)
		thumbParts = threePart(thumb, "ARTWORK", BAR .. "thumb-top", BAR .. "thumb-middle", BAR .. "thumb-bottom")
	end

	local function paintThumb(state)
		if flat then
			return
		end
		local suffix = state and ("-" .. state) or ""
		thumbParts.top:SetAtlas(BAR .. "thumb-top" .. suffix, true)
		thumbParts.mid:SetAtlas(BAR .. "thumb-middle" .. suffix)
		thumbParts.bottom:SetAtlas(BAR .. "thumb-bottom" .. suffix, true)
	end

	local function layout()
		local track = bar:GetHeight()
		local span = bar.max - bar.min
		local h = math.max(24, math.min(track, track * bar.ratio))
		thumb:SetHeight(h)
		local travel = math.max(0, track - h)
		local frac = span > 0 and (bar.value - bar.min) / span or 0
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", bar, "TOP", 0, -travel * frac)
	end
	bar.Layout = layout

	function bar:SetMinMaxValues(lo, hi)
		self.min, self.max = lo, hi
		layout()
	end
	function bar:SetValue(v)
		self.value = math.max(self.min, math.min(self.max, v))
		layout()
	end
	function bar:GetValue()
		return self.value
	end
	-- Fraction of the list one page covers, which sets the thumb length.
	function bar:SetThumbRatio(r)
		self.ratio = r
		layout()
	end

	local function cursorY()
		return select(2, GetCursorPosition()) / bar:GetEffectiveScale()
	end
	local function valueFromCursor(grabOffset)
		local track = bar:GetHeight()
		local travel = track - thumb:GetHeight()
		if travel <= 0 then
			return bar.min
		end
		local fromTop = bar:GetTop() - cursorY() - grabOffset
		return bar.min + (bar.max - bar.min) * math.max(0, math.min(1, fromTop / travel))
	end

	local dragging, grab = false, 0
	-- The poll only runs while the thumb is held, never idle.
	local function dragUpdate()
		if onChange then
			onChange(valueFromCursor(grab))
		end
	end
	thumb:SetScript("OnMouseDown", function()
		dragging = true
		grab = thumb:GetTop() - cursorY()
		paintThumb("down")
		bar:SetScript("OnUpdate", dragUpdate)
	end)
	thumb:SetScript("OnMouseUp", function(self)
		dragging = false
		bar:SetScript("OnUpdate", nil)
		paintThumb(self:IsMouseOver() and "over" or nil)
	end)
	thumb:SetScript("OnEnter", function()
		if not dragging then
			paintThumb("over")
		end
	end)
	thumb:SetScript("OnLeave", function()
		if not dragging then
			paintThumb(nil)
		end
	end)
	-- Clicking empty track centres the thumb there.
	bar:SetScript("OnMouseDown", function()
		if not thumb:IsMouseOver() then
			local v = valueFromCursor(thumb:GetHeight() / 2)
			if onChange then
				onChange(v)
			end
		end
	end)
	bar:SetScript("OnSizeChanged", layout)
	return bar
end

-- Scope tabs share the button art: the active one turns gold.
function F.CreateTab(parent, text, width, height)
	return F.CreateButton(parent, text, width, height)
end

-- ---------------------------------------------------------------------------
-- Game art. The metal frame and the red icon buttons are Blizzard atlases, so
-- they match the client and cost no shipped textures. Every piece is looked up
-- through the live API first, and the caller falls back to flat widgets when a
-- client does not have it.
-- ---------------------------------------------------------------------------
local function atlasExists(name)
	return C_Texture.GetAtlasInfo(name) ~= nil
end
F.AtlasExists = atlasExists

-- One piece: try each candidate { atlas, mirrorH, mirrorV } and use the first
-- the client knows. Mirroring flips the texture coordinates the way Blizzard's
-- own nine-slice does, so one corner can serve all four.
local function setPiece(tex, candidates)
	for i = 1, #candidates do
		local atlas, mirrorH, mirrorV = unpack(candidates[i])
		local info = C_Texture.GetAtlasInfo(atlas)
		if info then
			tex:SetTexCoord(mirrorH and 1 or 0, mirrorH and 0 or 1, mirrorV and 1 or 0, mirrorV and 0 or 1)
			tex:SetHorizTile(info.tilesHorizontally or false)
			tex:SetVertTile(info.tilesVertically or false)
			tex:SetAtlas(atlas, true)
			return atlas
		end
	end
	return nil
end

-- Builds a nine-slice-style frame (no centre) from a texture kit such as
-- "GenericMetal2". Returns the piece table, or nil when the kit is not complete
-- enough to look right, in which case nothing is left behind.
function F.CreateMetalFrame(frame, kit, outward)
	local function name(fmt)
		return fmt:format(kit)
	end
	local cornerTL, cornerTR = name("%s-NineSlice-CornerTopLeft"), name("%s-NineSlice-CornerTopRight")
	local cornerBL, cornerBR = name("%s-NineSlice-CornerBottomLeft"), name("%s-NineSlice-CornerBottomRight")
	local edgeT, edgeB = name("_%s-NineSlice-EdgeTop"), name("_%s-NineSlice-EdgeBottom")
	local edgeL, edgeR = name("!%s-NineSlice-EdgeLeft"), name("!%s-NineSlice-EdgeRight")

	local layout = {
		TL = { { cornerTL }, { cornerBL, false, true }, { cornerTR, true } },
		TR = { { cornerTR }, { cornerTL, true }, { cornerBL, true, true } },
		BL = { { cornerBL }, { cornerTL, false, true }, { cornerBR, true } },
		BR = { { cornerBR }, { cornerBL, true }, { cornerTL, true, true } },
		T = { { edgeT }, { edgeB, false, true } },
		B = { { edgeB }, { edgeT, false, true } },
		L = { { edgeL }, { edgeR, true } },
		R = { { edgeR }, { edgeL, true } },
	}

	local pieces, missing = {}, nil
	for key, candidates in pairs(layout) do
		local tex = frame:CreateTexture(nil, "BORDER")
		if setPiece(tex, candidates) then
			pieces[key] = tex
		else
			missing = candidates[1][1]
			tex:Hide()
			break
		end
	end
	if missing then
		for _, made in pairs(pieces) do
			made:Hide()
		end
		return nil, missing
	end

	-- The art has transparent padding outside the metal, so the pieces hang past
	-- the frame by `outward`, which keeps the metal flush with the window edge.
	local o = outward or 0
	pieces.TL:SetPoint("TOPLEFT", frame, "TOPLEFT", -o, o)
	pieces.TR:SetPoint("TOPRIGHT", frame, "TOPRIGHT", o, o)
	pieces.BL:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -o, -o)
	pieces.BR:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", o, -o)
	pieces.T:SetPoint("TOPLEFT", pieces.TL, "TOPRIGHT")
	pieces.T:SetPoint("TOPRIGHT", pieces.TR, "TOPLEFT")
	pieces.B:SetPoint("BOTTOMLEFT", pieces.BL, "BOTTOMRIGHT")
	pieces.B:SetPoint("BOTTOMRIGHT", pieces.BR, "BOTTOMLEFT")
	pieces.L:SetPoint("TOPLEFT", pieces.TL, "BOTTOMLEFT")
	pieces.L:SetPoint("BOTTOMLEFT", pieces.BL, "TOPLEFT")
	pieces.R:SetPoint("TOPRIGHT", pieces.TR, "BOTTOMRIGHT")
	pieces.R:SetPoint("BOTTOMRIGHT", pieces.BR, "TOPRIGHT")
	frame.Metal = pieces
	return pieces
end

-- Red icon button: normal, pressed, disabled and highlight art from one atlas
-- family ("128-RedButton-Exit" and its -Pressed and -Disabled siblings). opts.alt
-- is the family shown while toggled on. Falls back to a flat text button when
-- the family is missing. opts.rotation turns the glyph, so one arrow serves all
-- four directions.
function F.CreateAtlasButton(parent, base, size, opts)
	opts = opts or {}
	if not atlasExists(base) then
		local fallback = F.CreateButton(parent, opts.fallbackText or "?", size, size)
		fallback.SetToggled = fallback.SetActive
		return fallback
	end
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(size, size)

	local art = btn:CreateTexture(nil, "ARTWORK")
	art:SetAllPoints()
	if opts.rotation then
		art:SetRotation(opts.rotation)
	end
	btn.Art = art

	if atlasExists("128-RedButton-Highlight") then
		local hi = btn:CreateTexture(nil, "HIGHLIGHT")
		hi:SetAllPoints()
		hi:SetAtlas("128-RedButton-Highlight")
		hi:SetBlendMode("ADD")
		hi:SetAlpha(0.6)
	end

	btn.family = base
	local function paint(self, suffix)
		local atlas = self.family .. (suffix or "")
		art:SetAtlas(atlasExists(atlas) and atlas or self.family)
	end
	function btn:SetToggled(on)
		self.family = (on and opts.alt) or base
		paint(self)
	end
	btn.SetActive = btn.SetToggled
	paint(btn)

	btn:HookScript("OnMouseDown", function(self)
		if self:IsEnabled() then
			paint(self, "-Pressed")
		end
	end)
	btn:HookScript("OnMouseUp", function(self)
		paint(self)
	end)
	btn:HookScript("OnDisable", function(self)
		paint(self, "-Disabled")
	end)
	btn:HookScript("OnEnable", function(self)
		paint(self)
	end)
	return btn
end

-- ---------------------------------------------------------------------------
-- Window: metal frame, header strip, close button, drag, and resize
-- handles on every edge and corner. Position and size persist in the saved vars.
-- ---------------------------------------------------------------------------
local HANDLES = {
	{ "TOPLEFT", true },
	{ "TOPRIGHT", true },
	{ "BOTTOMLEFT", true },
	{ "BOTTOMRIGHT", true },
	{ "TOP" },
	{ "BOTTOM" },
	{ "LEFT" },
	{ "RIGHT" },
}

local function createHandle(win, point, corner)
	local h = CreateFrame("Frame", nil, win)
	h:SetFrameLevel(win:GetFrameLevel() + 50)
	h:EnableMouse(true)
	local e, c = Layout.handleEdge, Layout.handleCorner
	if corner then
		h:SetSize(c, c)
		h:SetPoint(point, win, point)
	elseif point == "TOP" or point == "BOTTOM" then
		h:SetHeight(e)
		h:SetPoint(point .. "LEFT", win, point .. "LEFT", c, 0)
		h:SetPoint(point .. "RIGHT", win, point .. "RIGHT", -c, 0)
	else
		h:SetWidth(e)
		h:SetPoint("TOP" .. point, win, "TOP" .. point, 0, -c)
		h:SetPoint("BOTTOM" .. point, win, "BOTTOM" .. point, 0, c)
	end

	-- Lit line along the grabbed edge while hovering, so the handle is findable.
	local glow = h:CreateTexture(nil, "OVERLAY")
	setColor(glow, Colors.accent, 0.55)
	glow:Hide()
	if corner then
		glow:SetSize(c - 4, 2)
		glow:SetPoint(point, h, point, point:find("LEFT") and 2 or -2, point:find("TOP") and -2 or 2)
	elseif point == "TOP" or point == "BOTTOM" then
		glow:SetHeight(2)
		glow:SetPoint("LEFT")
		glow:SetPoint("RIGHT")
		glow:SetPoint(point, h, point, 0, point == "TOP" and -2 or 2)
	else
		glow:SetWidth(2)
		glow:SetPoint("TOP")
		glow:SetPoint("BOTTOM")
		glow:SetPoint(point, h, point, point == "LEFT" and 2 or -2, 0)
	end

	h:SetScript("OnEnter", function()
		glow:Show()
	end)
	h:SetScript("OnLeave", function()
		if not h.sizing then
			glow:Hide()
		end
	end)
	h:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then
			return
		end
		h.sizing = true
		win:StartSizing(point)
	end)
	h:SetScript("OnMouseUp", function()
		h.sizing = false
		glow:Hide()
		win:StopMovingOrSizing()
		if win.OnLayoutChanged then
			win:OnLayoutChanged()
		end
	end)
	return h
end

function F.CreateWindow(globalName, width, height)
	local f = CreateFrame("Frame", globalName, UIParent)
	f:SetSize(width, height)
	f:SetPoint("CENTER")
	f:SetClampedToScreen(true)
	f:SetFrameStrata("HIGH")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then
		f:SetResizeBounds(Layout.minWidth, Layout.minHeight)
	end
	f:Hide()

	f.Bg = f:CreateTexture(nil, "BACKGROUND")
	f.Bg:SetAllPoints()
	setColor(f.Bg, Colors.void)
	if not F.CreateMetalFrame(f, Layout.frameKit, Layout.frameOutward) then
		F.CreateOutline(f)
		f.metalFallback = true
	else
		-- Fill stops under the metal band, so square fill corners never poke out
		-- past the frame's chamfered corners.
		f.Bg:ClearAllPoints()
		f.Bg:SetPoint("TOPLEFT", Layout.frameFillInset, -Layout.frameFillInset)
		f.Bg:SetPoint("BOTTOMRIGHT", -Layout.frameFillInset, Layout.frameFillInset)
	end

	-- Everything inside sits in Client, inset past the frame art.
	local inset = f.metalFallback and 0 or Layout.frameInset
	local client = CreateFrame("Frame", nil, f)
	client:SetPoint("TOPLEFT", inset, -inset)
	client:SetPoint("BOTTOMRIGHT", -inset, inset)
	f.Client = client

	local header = CreateFrame("Frame", nil, client)
	header:SetPoint("TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", 0, 0)
	header:SetHeight(Layout.headerHeight)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function()
		f:StartMoving()
	end)
	header:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		if f.OnLayoutChanged then
			f:OnLayoutChanged()
		end
	end)
	f.Header = header

	local rule = header:CreateTexture(nil, "ARTWORK")
	setColor(rule, Colors.edge, 0.6)
	rule:SetPoint("BOTTOMLEFT", 0, 0)
	rule:SetPoint("BOTTOMRIGHT", 0, 0)
	rule:SetHeight(1)

	local icon = header:CreateTexture(nil, "OVERLAY")
	icon:SetSize(26, 26)
	icon:SetPoint("LEFT", Layout.pad, 0)
	icon:SetTexture(C.Media.icon)
	f.Icon = icon

	f.Title = F.CreateText(header, 18, Colors.text, "LEFT")
	f.Title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	function f:SetTitle(text)
		self.Title:SetText(text)
	end

	local close = F.CreateAtlasButton(header, "128-RedButton-Exit", 28, { fallbackText = "x" })
	close:SetPoint("RIGHT", -Layout.pad, 0)
	close:SetFrameLevel(header:GetFrameLevel() + 10)
	close:SetScript("OnClick", function()
		f:Hide()
	end)
	f.CloseButton = close

	f.Handles = {}
	for i = 1, #HANDLES do
		local def = HANDLES[i]
		f.Handles[i] = createHandle(f, def[1], def[2])
	end

	tinsert(UISpecialFrames, globalName)
	return f
end
