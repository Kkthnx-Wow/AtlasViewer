-- The sheet view: one texture file on a zoom and pan canvas with every atlas in it
-- outlined and clickable. Reached from the detail drawer, so the gallery stays
-- the front door and this is the "where does it sit in the file" view.
local _, ns = ...
local C, L, F = ns.C, ns.L, ns.F
local Viewer = ns.Viewer
local Colors = C.Colors

local format = string.format
local GetCursorPosition = GetCursorPosition
local Saturate = Saturate
local min, max = math.min, math.max

local PAD = C.Layout.pad
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.1, 4, 0.1

-- ---------------------------------------------------------------------------
-- Overlay pool. One button per atlas outlined on the sheet.
-- ---------------------------------------------------------------------------
local function createOverlay(parent)
	local o = CreateFrame("Button", nil, parent)
	o:RegisterForDrag("LeftButton")
	F.CreateOutline(o)
	local hl = o:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.14)
	o.Highlight = hl
	return o
end

function Viewer:AcquireOverlay()
	self.overlayPool = self.overlayPool or {}
	self.activeOverlays = self.activeOverlays or {}
	local o = table.remove(self.overlayPool)
	if not o then
		o = createOverlay(self.SheetChild)
		o:SetScript("OnClick", function(frame)
			self:Select(frame.name)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end)
		o:SetScript("OnEnter", function(frame)
			self:StartCoordsPoll()
			GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
			GameTooltip:SetText(frame.name, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		o:SetScript("OnLeave", GameTooltip_Hide)
		o:SetScript("OnDragStart", function()
			self:PanStart()
		end)
		o:SetScript("OnDragStop", function()
			self:PanStop()
		end)
	end
	self.activeOverlays[#self.activeOverlays + 1] = o
	return o
end

function Viewer:ReleaseOverlays()
	if not self.activeOverlays then
		return
	end
	for i = #self.activeOverlays, 1, -1 do
		local o = self.activeOverlays[i]
		o:Hide()
		self.overlayPool[#self.overlayPool + 1] = o
		self.activeOverlays[i] = nil
	end
end

-- The search text as the index stores names: lowercased, spaces removed.
function Viewer:SearchNeedle()
	if not self.SearchBox then
		return ""
	end
	return (self.SearchBox:GetText():lower():gsub(" ", ""))
end

-- Selected wins, then search matches, then missing, then a faint default.
-- needle comes from SearchNeedle, worked out once per pass, not once per outline.
function Viewer:ColorOverlay(o, needle)
	local color, alpha = Colors.text, 0.28
	if o.name == self.selected then
		color, alpha = Colors.accent, 1
	elseif o.info.missing then
		color, alpha = Colors.bad, 0.7
	elseif needle ~= "" then
		local lower = ns.atlasLower[ns.atlasIndex[o.name] or 0]
		if lower and lower:find(needle, 1, true) then
			color, alpha = Colors.good, 0.9
		end
	end
	o.Outline:SetColor(color, alpha)
	o.Highlight:SetVertexColor(color[1], color[2], color[3])
end

function Viewer:PositionOverlay(o)
	local info, w, h = o.info, self.SheetChild:GetSize()
	o:ClearAllPoints()
	o:SetPoint("TOPLEFT", self.SheetChild, "TOPLEFT", info.leftTexCoord * w, -info.topTexCoord * h)
	o:SetPoint("BOTTOMRIGHT", self.SheetChild, "TOPLEFT", info.rightTexCoord * w, -info.bottomTexCoord * h)
end

-- positionOnly skips the recolour, for zoom steps where only the size changed.
function Viewer:RefreshOverlays(positionOnly)
	local active = self.activeOverlays
	if not active then
		return
	end
	local needle = not positionOnly and self:SearchNeedle()
	for i = 1, #active do
		local o = active[i]
		self:PositionOverlay(o)
		if needle then
			self:ColorOverlay(o, needle)
		end
	end
end

function Viewer:BuildOverlays()
	self:ReleaseOverlays()
	local names = ns.data[self.sheetTexture]
	if not names then
		return
	end
	local needle = self:SearchNeedle()
	for atlasName in pairs(names) do
		local info = ns:GetAtlasInfo(atlasName)
		if info and (not info.missing or ns.settings.showIssues) then
			local o = self:AcquireOverlay()
			o.name, o.info = atlasName, info
			self:PositionOverlay(o)
			self:ColorOverlay(o, needle)
			o:Show()
		end
	end
end

-- ---------------------------------------------------------------------------
-- Display and view control
-- ---------------------------------------------------------------------------
function Viewer:DisplaySheet(texture)
	self.sheetTexture = texture
	-- Rebuild the full sheet size from any atlas's coordinates, preferring live
	-- ones, because missing backup numbers can skew the size.
	local width, height, count, sized = 256, 256, 0, false
	local names = ns.data[texture]
	if names then
		for atlasName in pairs(names) do
			local info = ns:GetAtlasInfo(atlasName)
			if info and (not info.missing or ns.settings.showIssues) then
				local dw = info.rightTexCoord - info.leftTexCoord
				local dh = info.bottomTexCoord - info.topTexCoord
				if dw > 0 and dh > 0 and (not sized or not info.missing) then
					width, height = info.width / dw, info.height / dh
					sized = not info.missing
				end
			end
			count = count + 1
		end
	end
	self.texWidth, self.texHeight = width, height
	self.SheetChild.Texture:SetTexture(tonumber(texture) or texture)
	self.SheetChild:Show()
	self.SheetFile:SetText(texture)
	self.SheetCount:SetText(L["%d atlases"]:format(count))
	self:ResetView()
	self:BuildOverlays()
	PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
end

function Viewer:ShowSheet()
	if not self.selected then
		return
	end
	self:SetMode("sheet")
	local file = ns.entries[ns.atlasFile[self.selected]].texture
	-- Show() above gave the viewport real dimensions for the fit math.
	if file ~= self.sheetTexture then
		self:DisplaySheet(file)
	else
		self:RefreshOverlays()
	end
end

-- Step to the neighbouring texture file in the alphabetical file list.
function Viewer:StepSheet(delta)
	local entries = ns.entries
	local current = 0
	for i = 1, #entries do
		if entries[i].texture == self.sheetTexture then
			current = i
			break
		end
	end
	local target = entries[min(#entries, max(1, current + delta))]
	if target and target.texture ~= self.sheetTexture then
		self:DisplaySheet(target.texture)
	end
end

function Viewer:ResetView()
	local viewW, viewH = self.SheetViewport:GetSize()
	local scale = 1
	local availW, availH = viewW - 20, viewH - 20
	if self.texWidth > availW or self.texHeight > availH then
		scale = min(availW / self.texWidth, availH / self.texHeight)
	end
	self:SetScale(scale)
	self.SheetChild:ClearAllPoints()
	self.SheetChild:SetPoint("CENTER", self.SheetViewport, "CENTER")
end

function Viewer:SetScale(scale)
	if not self.texWidth then
		return
	end
	scale = min(SCALE_MAX, max(SCALE_MIN, scale))
	self.scale = scale
	self.SheetChild:SetSize(self.texWidth * scale, self.texHeight * scale)
	self.ScaleSlider:SetValue(scale)
	self.ScaleText:SetText(format("%d%%", math.floor(scale * 100 + 0.5)))
	self:RefreshOverlays(true)
end

function Viewer:PanStart()
	if not self.SheetChild:IsShown() then
		return
	end
	self.SheetChild:StartMoving()
	self.panning = true
	GameTooltip:Hide()
end

function Viewer:PanStop()
	if not self.panning then
		return
	end
	self.SheetChild:StopMovingOrSizing()
	-- Re-anchor to CENTER so later resizes stay stable.
	local cx, cy = self.SheetViewport:GetCenter()
	local x, y = self.SheetChild:GetCenter()
	self.SheetChild:ClearAllPoints()
	self.SheetChild:SetPoint("CENTER", self.SheetViewport, "CENTER", x - cx, y - cy)
	self.panning = false
end

-- Returns false once the cursor has left the viewport, which ends the poll.
function Viewer:UpdateCoords()
	local child = self.SheetChild
	if not child:IsShown() or not self.SheetViewport:IsMouseOver() then
		return false
	end
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	x, y = x / scale, y / scale
	local w, h = child:GetSize()
	self.Coords:SetText(
		format(
			"x %.4f   y %.4f",
			Saturate((x - child:GetLeft()) / w),
			Saturate((child:GetTop() - y) / h)
		)
	)
	return true
end

-- Coordinates are display only, so poll just while the cursor is over the
-- viewport. Overlays take the mouse from the canvas, so the canvas OnLeave
-- cannot end the poll. The poll ends itself when the cursor leaves the viewport.
function Viewer:StartCoordsPoll()
	local canvas = self.SheetCanvas
	if canvas:GetScript("OnUpdate") then
		return
	end
	self.coordsPoll = self.coordsPoll or function()
		if not self:UpdateCoords() then
			canvas:SetScript("OnUpdate", nil)
			self.Coords:SetText("")
		end
	end
	canvas:SetScript("OnUpdate", self.coordsPoll)
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
function Viewer:BuildSheet(main)
	local panel = F.CreatePanel(main, Colors.panel, true)
	panel:SetAllPoints()
	panel:Hide()
	self.SheetPanel = panel

	local back = F.CreateButton(panel, L["Gallery"], 80, 26)
	back:SetPoint("TOPLEFT", PAD, -PAD)
	back:SetScript("OnClick", function()
		self:SetMode("gallery")
	end)

	local prev = F.CreateAtlasButton(panel, "128-RedButton-ArrowDown", 26, { rotation = -math.pi / 2, fallbackText = "<" })
	prev:SetPoint("LEFT", back, "RIGHT", 8, 0)
	prev:SetScript("OnClick", function()
		self:StepSheet(-1)
	end)
	F.SetTooltip(prev, L["Previous file"])
	local nextBtn = F.CreateAtlasButton(panel, "128-RedButton-ArrowDown", 26, { rotation = math.pi / 2, fallbackText = ">" })
	nextBtn:SetPoint("LEFT", prev, "RIGHT", 4, 0)
	nextBtn:SetScript("OnClick", function()
		self:StepSheet(1)
	end)
	F.SetTooltip(nextBtn, L["Next file"])

	local file = F.CreateText(panel, 12, Colors.accent, "LEFT")
	file:SetPoint("LEFT", nextBtn, "RIGHT", 12, 0)
	file:SetPoint("RIGHT", panel, "TOPRIGHT", -PAD - 130, 0)
	file:SetPoint("TOP", back, "TOP", 0, -6)
	self.SheetFile = file
	local count = F.CreateText(panel, 11, Colors.mute, "RIGHT")
	count:SetPoint("RIGHT", panel, "TOPRIGHT", -PAD, -PAD - 13)
	self.SheetCount = count

	-- Canvas.
	local canvas = CreateFrame("Frame", nil, panel)
	canvas:SetPoint("TOPLEFT", back, "BOTTOMLEFT", 0, -10)
	canvas:SetPoint("BOTTOMRIGHT", -PAD, PAD + 34)
	canvas:EnableMouse(true)
	canvas:EnableMouseWheel(true)
	canvas:RegisterForDrag("LeftButton")
	local canvasBorder = CreateFrame("Frame", nil, panel)
	canvasBorder:SetAllPoints(canvas)
	canvasBorder:SetFrameLevel(canvas:GetFrameLevel() + 20)
	F.CreateBorder(canvasBorder)
	self.SheetCanvas = canvas

	local viewport = CreateFrame("Frame", nil, canvas)
	viewport:SetPoint("TOPLEFT", C.Layout.borderFill, -C.Layout.borderFill)
	viewport:SetPoint("BOTTOMRIGHT", -C.Layout.borderFill, C.Layout.borderFill)
	viewport:SetClipsChildren(true)
	self.SheetViewport = viewport

	local child = CreateFrame("Frame", nil, viewport)
	child:SetSize(256, 256)
	child:SetPoint("CENTER")
	child:SetMovable(true)
	child:EnableMouse(false)
	child:Hide()
	self.SheetChild = child
	self.SheetBackground = child:CreateTexture(nil, "BACKGROUND")
	self.SheetBackground:SetAllPoints()
	child.Texture = child:CreateTexture(nil, "ARTWORK")
	child.Texture:SetAllPoints()

	canvas:SetScript("OnDragStart", function()
		self:PanStart()
	end)
	canvas:SetScript("OnDragStop", function()
		self:PanStop()
	end)
	canvas:SetScript("OnMouseWheel", function(_, delta)
		self:SetScale((self.scale or 1) + SCALE_STEP * delta * 3)
	end)
	canvas:SetScript("OnEnter", function()
		self:StartCoordsPoll()
	end)
	canvas:SetScript("OnSizeChanged", function()
		if self.sheetTexture and self.mode == "sheet" then
			self:RefreshOverlays()
		end
	end)

	-- Bottom strip: zoom, fit, coordinates.
	local reset = F.CreateAtlasButton(panel, "128-RedButton-Refresh", 26, { fallbackText = L["Fit"] })
	reset:SetPoint("BOTTOMLEFT", PAD, PAD)
	F.SetTooltip(reset, L["Fit to view"])
	local zoomOut = F.CreateAtlasButton(panel, "128-RedButton-Minus", 26, { fallbackText = "-" })
	zoomOut:SetPoint("LEFT", reset, "RIGHT", 8, 0)
	zoomOut:SetScript("OnClick", function()
		self:SetScale((self.scale or 1) - SCALE_STEP * 3)
	end)
	reset:SetScript("OnClick", function()
		self:ResetView()
	end)

	local slider = F.CreateSlider(panel, SCALE_MIN, SCALE_MAX, SCALE_STEP, 180)
	slider:SetPoint("LEFT", zoomOut, "RIGHT", 10, 0)
	slider:SetScript("OnValueChanged", function(_, value)
		if math.abs((self.scale or 0) - value) > 0.0001 then
			self:SetScale(value)
		end
	end)
	self.ScaleSlider = slider
	local zoomIn = F.CreateAtlasButton(panel, "128-RedButton-Plus", 26, { fallbackText = "+" })
	zoomIn:SetPoint("LEFT", slider, "RIGHT", 10, 0)
	zoomIn:SetScript("OnClick", function()
		self:SetScale((self.scale or 1) + SCALE_STEP * 3)
	end)
	self.ScaleText = F.CreateText(panel, 11, Colors.mute, "LEFT")
	self.ScaleText:SetPoint("LEFT", zoomIn, "RIGHT", 10, 0)

	self.Coords = F.CreateText(panel, 11, Colors.mute, "RIGHT")
	self.Coords:SetPoint("BOTTOMRIGHT", -PAD, PAD + 6)

	self:ApplyBackground()
end
