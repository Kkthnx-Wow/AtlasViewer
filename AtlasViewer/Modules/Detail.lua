-- The detail drawer: large preview, favorite toggle, copy formats, numbers, and
-- the jump into the sheet view.
local _, ns = ...
local C, L, F = ns.C, ns.L, ns.F
local Viewer = ns.Viewer
local Colors = C.Colors

local format = string.format

local PAD = C.Layout.pad
local PREVIEW_H = 250

-- Zoom steps for the preview. 0 fits the box.
local ZOOMS = { { 0, "Fit" }, { 1, "1x" }, { 2, "2x" }, { 4, "4x" } }

-- Copy formats. Each builds the text for the selected atlas. Clients have no
-- clipboard API, so the text lands in a box that selects itself for Ctrl+C.
local function fileOf(name, info)
	if info and info.filename and info.filename ~= "" then
		return tostring(info.filename)
	end
	if info and info.file then
		return tostring(info.file)
	end
	return ns.entries[ns.atlasFile[name]].texture
end

local FORMATS = {
	{
		key = "name",
		label = "Name",
		build = function(name)
			return name
		end,
	},
	{
		key = "code",
		label = "Code",
		build = function(name)
			return format('tex:SetAtlas("%s", true)', name)
		end,
	},
	{
		key = "markup",
		label = "Inline",
		-- Not the raw |A: escape. An edit box would render that as the picture
		-- instead of showing the text, so this is the call that produces it.
		build = function(name, info)
			return format('CreateAtlasMarkup("%s", %d, %d)', name, info.width, info.height)
		end,
	},
	{
		key = "coords",
		label = "UV",
		build = function(_, info)
			return format(
				"%.5f, %.5f, %.5f, %.5f",
				info.leftTexCoord,
				info.rightTexCoord,
				info.topTexCoord,
				info.bottomTexCoord
			)
		end,
	},
	{
		key = "file",
		label = "File",
		build = function(name, info)
			return fileOf(name, info)
		end,
	},
}

function Viewer:RefreshCopyText()
	local name = self.selected
	local box = self.Detail.CopyBox
	if not name then
		box:SetText("")
		return
	end
	local info = ns:GetAtlasInfo(name)
	local fmt = FORMATS[self.copyFormat or 1]
	box.current = info and fmt.build(name, info) or name
	box:SetText(box.current)
	box:SetCursorPosition(0)
end

function Viewer:SetCopyFormat(i)
	self.copyFormat = i
	for n, btn in ipairs(self.Detail.FormatButtons) do
		btn:SetActive(n == i)
	end
	self:RefreshCopyText()
end

function Viewer:RefreshDetailFavorite()
	local fav = self.selected and ns:IsFavorite(self.selected)
	local btn = self.Detail.FavButton
	btn.Text:SetText(fav and L["Saved"] or L["Save"])
	btn:SetActive(fav)
end

function Viewer:PaintPreview()
	local d = self.Detail
	local name = self.selected
	if not name then
		return
	end
	local zoom = ns.settings.previewZoom
	local boxW = d.Preview:GetWidth()
	local info
	if zoom == 0 then
		info = F.PaintAtlas(d.PreviewTex, name, boxW - 20, PREVIEW_H - 20, 8)
	else
		info = F.PaintAtlas(d.PreviewTex, name, 0, 0, nil, zoom)
	end
	return info
end

function Viewer:ShowDetail(name)
	local d = self.Detail
	d.Empty:Hide()
	d.Content:Show()
	local info = self:PaintPreview() or ns:GetAtlasInfo(name)

	F.SetFittedText(d.Name, name, d.Name:GetWidth())
	if info then
		d.Size:SetText(format("%d x %d", info.width, info.height))
		local h, v = info.tilesHorizontally, info.tilesVertically
		d.Tile:SetText((h and v and L["Both"]) or (h and L["Horizontal"]) or (v and L["Vertical"]) or L["None"])
		d.Coords:SetText(
			format(
				"L %.4f   R %.4f\nT %.4f   B %.4f",
				info.leftTexCoord,
				info.rightTexCoord,
				info.topTexCoord,
				info.bottomTexCoord
			)
		)
	end
	d.Warning:SetShown(info and info.missing or false)
	d.File:SetText(ns.entries[ns.atlasFile[name]].texture)
	self:RefreshDetailFavorite()
	self:RefreshCopyText()
end

function Viewer:SetBackground(r, g, b, a)
	a = a or 1
	local saved = ns.settings.background
	saved.r, saved.g, saved.b, saved.a = r, g, b, a
	self:ApplyBackground()
end

function Viewer:ApplyBackground()
	local bg = ns.settings.background
	if self.Detail then
		self.Detail.PreviewBg:SetColorTexture(bg.r, bg.g, bg.b, bg.a)
		self.Detail.Swatch.Fill:SetColorTexture(bg.r, bg.g, bg.b, 1)
	end
	if self.SheetBackground then
		self.SheetBackground:SetColorTexture(bg.r, bg.g, bg.b, bg.a)
	end
end

-- Blizzard's colour picker contract: swatchFunc / opacityFunc / cancelFunc.
function Viewer:PickBackground()
	local bg = ns.settings.background
	local function apply()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		self:SetBackground(r, g, b, ColorPickerFrame:GetColorAlpha())
	end
	ColorPickerFrame:SetupColorPickerAndShow({
		swatchFunc = apply,
		opacityFunc = apply,
		cancelFunc = function(prev)
			self:SetBackground(prev.r, prev.g, prev.b, prev.a)
		end,
		hasOpacity = true,
		r = bg.r,
		g = bg.g,
		b = bg.b,
		opacity = bg.a,
	})
end

function Viewer:BuildDetail(panel)
	local d = panel
	self.Detail = d

	-- Shown before anything is picked.
	local empty = F.CreateText(d, 13, Colors.mute, "CENTER")
	empty:SetPoint("CENTER")
	empty:SetWidth(240)
	empty:SetWordWrap(true)
	empty:SetText(L["Pick an atlas to see its details."])
	d.Empty = empty

	local content = CreateFrame("Frame", nil, d)
	content:SetAllPoints()
	content:Hide()
	d.Content = content

	-- Name row: title plus favorite toggle.
	local fav = F.CreateButton(content, L["Save"], 84, 28)
	fav:SetPoint("BOTTOMLEFT", PAD, PAD)
	fav:SetScript("OnClick", function()
		if self.selected then
			ns:ToggleFavorite(self.selected)
			self:RefreshDetailFavorite()
			self.Grid:Refresh()
			if self.scope == "favorites" then
				self:RunSearch(true)
			end
		end
	end)
	F.SetTooltip(fav, L["Favorite"], L["Keeps this atlas in your Favorites list."])
	d.FavButton = fav

	local name = F.CreateText(content, 14, Colors.accent, "LEFT")
	name:SetPoint("TOPLEFT", PAD, -PAD)
	name:SetPoint("TOPRIGHT", -PAD, -PAD)
	d.Name = name

	-- Preview box with the saved background colour.
	local preview = CreateFrame("Frame", nil, content)
	preview:SetPoint("TOPLEFT", PAD, -(PAD + 28))
	preview:SetPoint("TOPRIGHT", -PAD, -(PAD + 28))
	preview:SetHeight(PREVIEW_H)
	preview:SetClipsChildren(true)
	d.Preview = preview
	d.PreviewBg = preview:CreateTexture(nil, "BACKGROUND")
	d.PreviewBg:SetPoint("TOPLEFT", C.Layout.borderFill, -C.Layout.borderFill)
	d.PreviewBg:SetPoint("BOTTOMRIGHT", -C.Layout.borderFill, C.Layout.borderFill)
	-- The border lives on a sibling frame, because the preview clips its children.
	local previewBorder = CreateFrame("Frame", nil, content)
	previewBorder:SetAllPoints(preview)
	previewBorder:SetFrameLevel(preview:GetFrameLevel() + 5)
	F.CreateBorder(previewBorder)
	d.PreviewTex = preview:CreateTexture(nil, "ARTWORK")
	d.PreviewTex:SetPoint("CENTER")

	-- Zoom steps and the background swatch, directly under the preview.
	local zoomBar = CreateFrame("Frame", nil, content)
	zoomBar:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 0, -8)
	zoomBar:SetPoint("TOPRIGHT", preview, "BOTTOMRIGHT", 0, -8)
	zoomBar:SetHeight(22)
	d.ZoomButtons = {}
	local anchor
	for i, def in ipairs(ZOOMS) do
		local b = F.CreateButton(zoomBar, def[2], 44, 22)
		if anchor then
			b:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			b:SetPoint("LEFT")
		end
		b:SetScript("OnClick", function()
			ns.settings.previewZoom = def[1]
			for _, other in ipairs(d.ZoomButtons) do
				other:SetActive(other.zoom == def[1])
			end
			self:PaintPreview()
		end)
		b.zoom = def[1]
		b:SetActive(def[1] == ns.settings.previewZoom)
		d.ZoomButtons[i] = b
		anchor = b
	end
	-- A colour chip with the same border as the panels, lit amber on hover.
	local swatch = CreateFrame("Button", nil, zoomBar)
	swatch:SetSize(22, 22)
	swatch:SetPoint("RIGHT")
	swatch.Fill = swatch:CreateTexture(nil, "ARTWORK")
	swatch.Fill:SetPoint("TOPLEFT", C.Layout.borderFill, -C.Layout.borderFill)
	swatch.Fill:SetPoint("BOTTOMRIGHT", -C.Layout.borderFill, C.Layout.borderFill)
	F.CreateBorder(swatch)
	swatch:SetScript("OnEnter", function(self)
		F.SetBorderColor(self, Colors.accent)
	end)
	swatch:SetScript("OnLeave", function(self)
		F.SetBorderColor(self, { 1, 1, 1 })
	end)
	swatch:SetScript("OnClick", function()
		self:PickBackground()
	end)
	F.SetTooltip(swatch, L["Background color"])
	d.Swatch = swatch

	-- Numbers.
	local sizeLabel = F.CreateText(content, 11, Colors.mute, "LEFT")
	sizeLabel:SetPoint("TOPLEFT", zoomBar, "BOTTOMLEFT", 0, -14)
	sizeLabel:SetText(L["Size"])
	d.Size = F.CreateText(content, 13, Colors.text, "LEFT")
	d.Size:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -3)

	local tileLabel = F.CreateText(content, 11, Colors.mute, "LEFT")
	tileLabel:SetPoint("LEFT", sizeLabel, "LEFT", 110, 0)
	tileLabel:SetText(L["Tiling"])
	d.Tile = F.CreateText(content, 13, Colors.text, "LEFT")
	d.Tile:SetPoint("TOPLEFT", tileLabel, "BOTTOMLEFT", 0, -3)

	local coordsLabel = F.CreateText(content, 11, Colors.mute, "LEFT")
	coordsLabel:SetPoint("TOPLEFT", d.Size, "BOTTOMLEFT", 0, -12)
	coordsLabel:SetText(L["Texture coordinates"])
	d.Coords = F.CreateText(content, 12, Colors.text, "LEFT")
	d.Coords:SetPoint("TOPLEFT", coordsLabel, "BOTTOMLEFT", 0, -3)
	d.Coords:SetWordWrap(true)
	d.Coords:SetSpacing(3)

	local fileLabel = F.CreateText(content, 11, Colors.mute, "LEFT")
	fileLabel:SetPoint("TOPLEFT", d.Coords, "BOTTOMLEFT", 0, -22)
	fileLabel:SetText(L["Sheet file"])
	local file = F.CreateText(content, 11, Colors.text, "LEFT")
	file:SetPoint("TOPLEFT", fileLabel, "BOTTOMLEFT", 0, -3)
	file:SetPoint("RIGHT", -PAD, 0)
	file:SetWordWrap(true)
	d.File = file

	local warning = F.CreateText(content, 11, Colors.bad, "LEFT")
	warning:SetPoint("TOPLEFT", file, "BOTTOMLEFT", 0, -10)
	warning:SetPoint("RIGHT", -PAD, 0)
	warning:SetWordWrap(true)
	warning:SetText(L["The client no longer resolves this atlas. Showing bundled numbers."])
	warning:Hide()
	d.Warning = warning

	-- Bottom block: open sheet, then copy formats and the copy box.
	local sheetBtn = F.CreateButton(content, L["Open sheet"], 100, 28)
	sheetBtn:SetPoint("BOTTOMLEFT", fav, "BOTTOMRIGHT", 8, 0)
	sheetBtn:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	sheetBtn:SetScript("OnClick", function()
		if self.mode == "sheet" then
			self:SetMode("gallery")
		else
			self:ShowSheet()
		end
	end)
	F.SetTooltip(sheetBtn, L["Open sheet"], L["Shows the whole texture file with every atlas outlined."])
	self.OpenSheetButton = sheetBtn

	local copyBox = F.CreateEditBox(content, 100, 28, 12)
	copyBox:SetPoint("BOTTOMLEFT", fav, "TOPLEFT", 0, 12)
	copyBox:SetPoint("BOTTOMRIGHT", sheetBtn, "TOPRIGHT", 0, 12)
	copyBox:SetScript("OnEditFocusGained", function(box)
		box:HighlightText()
	end)
	copyBox:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
		box:HighlightText(0, 0)
	end)
	-- Typing must not desync the box from what the title says.
	copyBox:SetScript("OnTextChanged", function(box, userInput)
		if userInput and box.current and box:GetText() ~= box.current then
			box:SetText(box.current)
			box:HighlightText()
		end
	end)
	d.CopyBox = copyBox

	local formats = CreateFrame("Frame", nil, content)
	formats:SetPoint("BOTTOMLEFT", copyBox, "TOPLEFT", 0, 6)
	formats:SetPoint("BOTTOMRIGHT", copyBox, "TOPRIGHT", 0, 6)
	formats:SetHeight(22)
	d.FormatButtons = {}
	local count = #FORMATS
	local gap = 4
	for i, def in ipairs(FORMATS) do
		local b = F.CreateButton(formats, L[def.label], 40, 22)
		b:SetScript("OnClick", function()
			self:SetCopyFormat(i)
			copyBox:SetFocus()
		end)
		d.FormatButtons[i] = b
	end
	-- Equal widths across the row, sized once the panel width is known.
	formats:SetScript("OnSizeChanged", function(_, w)
		local each = (w - gap * (count - 1)) / count
		for i, b in ipairs(d.FormatButtons) do
			b:ClearAllPoints()
			b:SetWidth(each)
			b:SetPoint("LEFT", (i - 1) * (each + gap), 0)
		end
	end)

	local copyHint = F.CreateText(content, 11, Colors.mute, "LEFT")
	copyHint:SetPoint("BOTTOMLEFT", formats, "TOPLEFT", 0, 6)
	copyHint:SetText(L["Copy as, then press Ctrl+C"])

	self.copyFormat = 1
	self:SetCopyFormat(1)
	self:ApplyBackground()

	-- A wider or narrower drawer changes the Fit size.
	preview:SetScript("OnSizeChanged", function()
		if self.selected and ns.settings.previewZoom == 0 then
			self:PaintPreview()
		end
	end)
end
