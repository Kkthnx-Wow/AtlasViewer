-- The gallery: search box, scope and filter chips, thumbnail size slider and the
-- virtualized grid of atlas thumbnails.
local _, ns = ...
local C, L, F = ns.C, ns.L, ns.F
local Viewer = ns.Viewer
local Colors, Layout = C.Colors, C.Layout

local format = string.format
local C_Timer = C_Timer

local PAD = C.Layout.pad

-- ---------------------------------------------------------------------------
-- Grid cells
-- ---------------------------------------------------------------------------
local function createCell(parent)
	local cell = CreateFrame("Button", nil, parent)
	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local bg = cell:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", C.Layout.borderFill, -C.Layout.borderFill)
	bg:SetPoint("TOPRIGHT", -C.Layout.borderFill, -C.Layout.borderFill)
	cell.Bg = bg

	-- Thumbnails sit in a clipped frame so oversized atlases cannot bleed out.
	local clip = CreateFrame("Frame", nil, cell)
	clip:SetClipsChildren(true)
	clip:SetPoint("TOPLEFT", C.Layout.borderFill, -C.Layout.borderFill)
	clip:SetPoint("TOPRIGHT", -C.Layout.borderFill, -C.Layout.borderFill)
	cell.Clip = clip

	local icon = clip:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("CENTER")
	cell.Icon = icon

	-- Border box covers the preview square only. Created after the clip so it
	-- draws over the thumbnail edge.
	local box = CreateFrame("Frame", nil, cell)
	box:SetPoint("TOPLEFT")
	box:SetPoint("TOPRIGHT")
	F.CreateBorder(box)
	cell.Box = box

	-- Selection and hover tint over the fill, under the thumbnail.
	local wash = cell:CreateTexture(nil, "BACKGROUND", nil, 1)
	wash:SetAllPoints(bg)
	cell.Wash = wash

	local label = F.CreateText(cell, 10, Colors.mute, "LEFT")
	label:SetPoint("BOTTOMLEFT", 2, 1)
	label:SetPoint("BOTTOMRIGHT", -2, 1)
	cell.Label = label

	-- On the border box so it draws above the border art.
	local star = box:CreateTexture(nil, "OVERLAY", nil, 7)
	F.SetColor(star, Colors.accent)
	star:SetSize(7, 7)
	star:SetPoint("TOPRIGHT", -9, -9)
	cell.Star = star

	cell:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			ns:ToggleFavorite(self.name)
			Viewer.Grid:Refresh()
			if Viewer.scope == "favorites" then
				Viewer:RunSearch(true)
			end
			Viewer:RefreshDetailFavorite()
			return
		end
		Viewer.selPos = self.position
		Viewer:Select(self.name)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end)
	cell:SetScript("OnEnter", function(self)
		self.hovered = true
		Viewer:StyleCell(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.name, 1, 1, 1, 1, true)
		local info = ns:GetAtlasInfo(self.name)
		if info then
			GameTooltip:AddLine(format("%d x %d", info.width, info.height), Colors.mute[1], Colors.mute[2], Colors.mute[3])
		end
		GameTooltip:AddLine(L["Right click to favorite"], Colors.mute[1], Colors.mute[2], Colors.mute[3])
		GameTooltip:Show()
	end)
	cell:SetScript("OnLeave", function(self)
		self.hovered = false
		Viewer:StyleCell(self)
		GameTooltip:Hide()
	end)
	return cell
end

function Viewer:StyleCell(cell)
	local selected = cell.name == self.selected
	F.SetColor(cell.Bg, cell.hovered and Colors.hover or Colors.raised)
	local border, alpha = Colors.mute, 0.55
	if selected then
		border, alpha = Colors.accent, 1
	elseif cell.missing then
		border, alpha = Colors.bad, 0.9
	elseif cell.hovered then
		border, alpha = Colors.text, 0.9
	end
	F.SetBorderColor(cell.Box, border, alpha)
	if selected then
		F.SetColor(cell.Wash, Colors.accent, 0.16)
	elseif cell.hovered then
		F.SetColor(cell.Wash, Colors.text, 0.07)
	else
		F.SetColor(cell.Wash, Colors.text, 0)
	end
	local text = selected and Colors.accent or (cell.hovered and Colors.text or Colors.mute)
	cell.Label:SetTextColor(text[1], text[2], text[3])
end

local function updateCell(cell, index, position, cellW)
	local name = ns.atlasNames[index]
	cell.name, cell.position = name, position
	cell.missing = ns.backup[name] ~= nil
	local inner = cellW - 2 * C.Layout.borderFill
	cell.Bg:SetHeight(inner)
	cell.Clip:SetHeight(inner)
	F.SetFittedText(cell.Label, name, cellW - 6)
	F.PaintAtlas(cell.Icon, name, cellW - 14, cellW - 14, 4)
	cell.Star:SetShown(ns:IsFavorite(name))
	cell.Box:SetHeight(cellW)
	Viewer:StyleCell(cell)
end

-- ---------------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------------
function Viewer:RunSearch(keepScroll)
	local results = ns:Search(self.SearchBox:GetText(), {
		scope = self.scope,
		tilingOnly = self.tilingOnly,
		showIssues = ns.settings.showIssues,
	})
	self.results = results
	self.selPos = nil
	self.Grid:SetData(results, keepScroll)
	local count = BreakUpLargeNumbers and BreakUpLargeNumbers(#results) or #results
	self.CountText:SetText(L["%s atlases"]:format(count))
	self.EmptyText:SetShown(#results == 0)
	if self.mode == "sheet" then
		self:RefreshOverlays()
	end
end

-- Typing re-runs the search after a short pause. The generation counter drops
-- stale timers instead of cancelling them.
function Viewer:QueueSearch()
	self.searchGen = (self.searchGen or 0) + 1
	local gen = self.searchGen
	C_Timer.After(C.Search.debounce, function()
		if gen == self.searchGen then
			self:RunSearch()
		end
	end)
end

function Viewer:SetScope(scope)
	self.scope = scope
	for key, chip in pairs(self.ScopeChips) do
		chip:SetActive(key == scope)
	end
	self:RunSearch()
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
function Viewer:BuildGallery(main)
	local panel = F.CreatePanel(main, Colors.panel, true)
	panel:SetAllPoints()
	self.GalleryPanel = panel
	self.scope = "all"

	local search = F.CreateEditBox(panel, 100, 32, 14, { search = true })
	search:SetPoint("TOPLEFT", PAD, -PAD)
	search:SetPoint("TOPRIGHT", -PAD, -PAD)
	search:SetScript("OnTextChanged", function(_, userInput)
		self.PlaceHolder:SetShown(search:GetText() == "")
		if userInput or self.frame:IsShown() then
			self:QueueSearch()
		end
	end)
	search:SetScript("OnEscapePressed", function(box)
		if box:GetText() ~= "" then
			box:SetText("")
		else
			box:ClearFocus()
		end
	end)
	-- Enter drops focus so the arrow keys navigate the grid, and picks the first hit
	-- when nothing is selected yet.
	search:SetScript("OnEnterPressed", function(box)
		box:ClearFocus()
		if not self.selected and self.results and self.results[1] then
			self:MoveSelection(1)
		end
	end)
	search:SetScript("OnArrowPressed", function(_, key)
		if key == "UP" or key == "DOWN" then
			self:HandleNavKey(key)
		end
	end)
	self.SearchBox = search

	local hint = F.CreateText(search, 13, Colors.mute, "LEFT")
	hint:SetPoint("LEFT", F.AtlasExists("common-search-magnifyingglass") and 30 or 10, 0)
	hint:SetText(L["Search atlas names or file paths"])
	self.PlaceHolder = hint

	-- Chip row: scope on the left, filters next, count and size on the right.
	local row = CreateFrame("Frame", nil, panel)
	row:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
	row:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -8)
	row:SetHeight(28)

	self.ScopeChips = {}
	local anchor
	for _, def in ipairs({ { "all", L["All"] }, { "favorites", L["Favorites"] }, { "recent", L["Recent"] } }) do
		local chip = F.CreateTab(row, def[2], 84, 28)
		if anchor then
			chip:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			chip:SetPoint("LEFT")
		end
		chip:SetScript("OnClick", function()
			self:SetScope(def[1])
		end)
		self.ScopeChips[def[1]] = chip
		anchor = chip
	end
	self.ScopeChips.all:SetActive(true)

	local tiling = F.CreateButton(row, L["Tiling"], 62, 28)
	tiling:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
	tiling:SetScript("OnClick", function(btn)
		self.tilingOnly = not self.tilingOnly
		btn:SetActive(self.tilingOnly)
		self:RunSearch()
	end)
	F.SetTooltip(tiling, L["Tiling atlases only"])

	local issues = F.CreateAtlasButton(row, "128-RedButton-VisibilityOff", 26, {
		alt = "128-RedButton-VisibilityOn",
		fallbackText = L["Issues"],
	})
	issues:SetPoint("LEFT", tiling, "RIGHT", 8, 0)
	issues:SetToggled(ns.settings.showIssues)
	issues:SetScript("OnClick", function(btn)
		ns.settings.showIssues = not ns.settings.showIssues
		btn:SetToggled(ns.settings.showIssues)
		self:RunSearch()
	end)
	F.SetTooltip(issues, L["Show missing or outdated atlases"], L["Atlases the client no longer resolves, drawn from the bundled data."])

	local size = F.CreateSlider(row, Layout.cellMin, Layout.cellMax, 4, 110)
	size:SetPoint("RIGHT", 0, 0)
	size:SetValue(ns.settings.cellSize)
	size:SetScript("OnValueChanged", function(_, value)
		ns.settings.cellSize = value
		self.Grid:SetCellSize(value)
	end)
	F.SetTooltip(size, L["Thumbnail size"])

	local count = F.CreateText(row, 11, Colors.mute, "RIGHT")
	count:SetPoint("RIGHT", size, "LEFT", -12, 0)
	self.CountText = count

	local grid = F.CreateGrid(panel, createCell, updateCell)
	grid:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -10)
	grid:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	grid.cellSize = ns.settings.cellSize
	self.Grid = grid

	local empty = F.CreateText(panel, 14, Colors.mute, "CENTER")
	empty:SetPoint("CENTER", grid, "CENTER")
	empty:SetText(L["Nothing matches."])
	empty:Hide()
	self.EmptyText = empty
end
