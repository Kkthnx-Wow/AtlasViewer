-- Virtualized grid. Only the cells on screen exist, and scrolling re-binds them to
-- other data positions, so tens of thousands of atlases cost a few dozen frames.
local _, ns = ...
local C, F = ns.C, ns.F

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local GAP = 8

-- createCell(parent) -> frame, updateCell(cell, value, position, cellW, cellH)
-- (value is nil for the unused tail cells, which get hidden).
function F.CreateGrid(parent, createCell, updateCell)
	local grid = CreateFrame("Frame", nil, parent)
	grid.data = {}
	grid.cells = {}
	grid.rowOffset = 0
	grid.cellSize = C.Layout.cellDefault
	grid.cols = 1

	local bar = F.CreateScrollbar(grid, function(value)
		value = floor(value + 0.5)
		if value ~= grid.rowOffset then
			grid.rowOffset = value
			grid:Refresh()
		end
	end)
	bar:SetPoint("TOPRIGHT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", 0, 0)
	grid.ScrollBar = bar

	local content = CreateFrame("Frame", nil, grid)
	content:SetPoint("TOPLEFT")
	content:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -6, 0)
	content:SetClipsChildren(true)
	grid.Content = content

	function grid:Layout()
		local w, h = content:GetSize()
		if w < 10 or h < 10 then
			return
		end
		local cols = max(1, floor((w + GAP) / (self.cellSize + GAP)))
		local cellW = (w - GAP * (cols - 1)) / cols
		local cellH = cellW + C.Layout.cellLabelHeight
		self.cols, self.cellW, self.cellH = cols, cellW, cellH
		self.rowsVisible = max(1, floor((h + GAP) / (cellH + GAP)))
		self.rowsTotal = ceil(#self.data / cols)
		self.maxRowOffset = max(0, self.rowsTotal - self.rowsVisible)
	end

	function grid:Refresh()
		self:Layout()
		if not self.cellW then
			return
		end
		local cols = self.cols
		self.rowOffset = min(self.rowOffset, self.maxRowOffset)

		bar:SetMinMaxValues(0, self.maxRowOffset)
		bar:SetValue(self.rowOffset)
		bar:SetShown(self.maxRowOffset > 0)
		-- Thumb length follows how much of the list one page covers.
		bar:SetThumbRatio(self.rowsVisible / max(1, self.rowsTotal))

		-- One extra row so a partly scrolled view never shows a gap at the bottom.
		local needed = (self.rowsVisible + 1) * cols
		for i = #self.cells + 1, needed do
			self.cells[i] = createCell(content)
		end

		local data, base = self.data, self.rowOffset * cols
		for i = 1, #self.cells do
			local cell = self.cells[i]
			local value = i <= needed and data[base + i] or nil
			if value then
				local col, row = (i - 1) % cols, floor((i - 1) / cols)
				cell:ClearAllPoints()
				cell:SetSize(self.cellW, self.cellH)
				cell:SetPoint("TOPLEFT", content, "TOPLEFT", col * (self.cellW + GAP), -row * (self.cellH + GAP))
				updateCell(cell, value, base + i, self.cellW, self.cellH)
				cell:Show()
			else
				cell:Hide()
			end
		end
	end

	function grid:SetData(data, keepScroll)
		self.data = data or {}
		if not keepScroll then
			self.rowOffset = 0
		end
		self:Refresh()
	end

	function grid:SetCellSize(size)
		self.cellSize = size
		self:Refresh()
	end

	-- Scroll just far enough to bring a data position on screen.
	function grid:ScrollToPosition(position)
		self:Layout()
		if not self.cellW then
			return
		end
		local row = floor((position - 1) / self.cols)
		if row < self.rowOffset then
			self.rowOffset = row
		elseif row >= self.rowOffset + self.rowsVisible then
			self.rowOffset = row - self.rowsVisible + 1
		end
		self:Refresh()
	end

	grid:EnableMouseWheel(true)
	grid:SetScript("OnMouseWheel", function(_, delta)
		local target = max(0, min(grid.maxRowOffset or 0, grid.rowOffset - delta * 2))
		if target ~= grid.rowOffset then
			grid.rowOffset = target
			grid:Refresh()
		end
	end)
	content:SetScript("OnSizeChanged", function()
		grid:Refresh()
	end)

	return grid
end
