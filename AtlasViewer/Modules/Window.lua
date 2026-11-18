-- The shell: window, panel layout, selection state, keyboard navigation and the
-- open/close entry point. Gallery, Detail and Sheet attach their builders and
-- methods onto the Viewer table this file creates.
local _, ns = ...
local C, L, F = ns.C, ns.L, ns.F
local Layout, Colors = C.Layout, C.Colors

local max, min = math.max, math.min

local Viewer = {}
ns.Viewer = Viewer

-- ---------------------------------------------------------------------------
-- Painting an atlas into a texture, shared by the grid cells and the preview.
-- Live atlases use SetAtlas. Names the client lost fall back to the bundled
-- numbers against the sheet file. Returns the atlas info, or nil when unknown.
-- ---------------------------------------------------------------------------
function F.PaintAtlas(tex, name, maxW, maxH, maxScale, fixedScale)
	local info = ns:GetAtlasInfo(name)
	if not info or not info.width or info.width <= 0 then
		tex:Hide()
		return nil
	end
	local w, h = info.width, info.height
	local scale = fixedScale or min(maxW / w, maxH / h, maxScale or 1)
	tex:SetSize(max(1, w * scale), max(1, h * scale))
	if info.missing then
		local file = ns.entries[ns.atlasFile[name]].texture
		tex:SetTexture(tonumber(file) or file)
		tex:SetTexCoord(info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord)
	else
		tex:SetAtlas(name, false)
	end
	tex:Show()
	return info
end

-- ---------------------------------------------------------------------------
-- Selection
-- ---------------------------------------------------------------------------
function Viewer:Select(name, skipRecent)
	if not name then
		return
	end
	self.selected = name
	if not skipRecent then
		ns:AddRecent(name)
	end
	self:ShowDetail(name)
	if self.Grid then
		local idx = ns.atlasIndex[name]
		if idx and self.results then
			for p = 1, #self.results do
				if self.results[p] == idx then
					self.selPos = p
					self.Grid:ScrollToPosition(p)
					break
				end
			end
		end
		self.Grid:Refresh()
	end
	if self.mode == "sheet" then
		local file = ns.entries[ns.atlasFile[name]].texture
		if file ~= self.sheetTexture then
			self:DisplaySheet(file)
		else
			self:RefreshOverlays()
		end
	end
end

-- Step the selection through the current results (gallery mode).
function Viewer:MoveSelection(delta)
	local results = self.results
	if self.mode ~= "gallery" or not results or #results == 0 then
		return
	end
	local pos = self.selPos
	if not pos or results[pos] ~= ns.atlasIndex[self.selected or ""] then
		pos = nil
	end
	local target = pos and (pos + delta) or (delta > 0 and 1 or #results)
	target = min(#results, max(1, target))
	self.selPos = target
	self:Select(ns.atlasNames[results[target]], true)
end

-- ---------------------------------------------------------------------------
-- Layout persistence
-- ---------------------------------------------------------------------------
local function saveLayout(f)
	local w = ns.db.window
	w.width, w.height = f:GetSize()
	local point, _, relPoint, x, y = f:GetPoint()
	w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
end

local function restoreLayout(f)
	local w = ns.db.window
	if w.width and w.height then
		f:SetSize(max(Layout.minWidth, w.width), max(Layout.minHeight, w.height))
	end
	if w.point then
		f:ClearAllPoints()
		f:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
	end
end

-- ---------------------------------------------------------------------------
-- Build the whole UI once, on first open.
-- ---------------------------------------------------------------------------
function Viewer:BuildHeaderBuild(f)
	-- dataBuild is the dump build, not a promise that a newer dump exists. A client
	-- ahead of the dump means the publisher has not caught up, not that the user
	-- forgot to update, so that case gets a soft amber chip and an honest tooltip.
	if not ns.dataBuild then
		return
	end
	local clientBuild = tonumber((select(2, GetBuildInfo())))
	local ahead = clientBuild and clientBuild > ns.dataBuild

	local holder = CreateFrame("Frame", nil, f.Header)
	holder:SetPoint("RIGHT", f.CloseButton, "LEFT", -12, 0)
	local text = F.CreateText(holder, 11, ahead and Colors.accent or Colors.mute, "RIGHT")
	text:SetPoint("RIGHT")
	text:SetText(L["Atlas build %s"]:format(ns.dataBuild))
	holder:SetSize(max(1, text:GetStringWidth()) + 4, 18)
	holder:EnableMouse(true)
	holder:SetScript("OnEnter", function()
		GameTooltip:SetOwner(holder, "ANCHOR_BOTTOM")
		if ahead then
			GameTooltip:AddLine(L["Newer client than atlas dump"], Colors.accent[1], Colors.accent[2], Colors.accent[3])
			GameTooltip:AddLine(L["Client %s, dump %s. The source may not have republished yet, re-run the updater after it does."]:format(clientBuild, ns.dataBuild), 1, 1, 1, true)
		else
			GameTooltip:AddLine(L["Atlas dump matches this client"], Colors.good[1], Colors.good[2], Colors.good[3])
		end
		GameTooltip:Show()
	end)
	holder:SetScript("OnLeave", GameTooltip_Hide)
end

function Viewer:Build()
	if self.frame then
		return
	end
	local f = F.CreateWindow("AtlasViewerFrame", Layout.defaultWidth, Layout.defaultHeight)
	f:SetTitle(L["Atlas Viewer"])

	-- Version from the TOC, small and muted beside the name.
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local version = getMeta and getMeta(ns.addonName, "Version")
	if version then
		local tag = F.CreateText(f.Header, 11, Colors.mute, "LEFT")
		tag:SetPoint("BOTTOMLEFT", f.Title, "BOTTOMRIGHT", 6, 1)
		tag:SetText("v" .. version)
	end
	f.OnLayoutChanged = saveLayout
	restoreLayout(f)
	self.frame = f
	self:BuildHeaderBuild(f)

	-- Body regions: main (gallery or sheet) on the left, detail drawer on the right.
	local body = CreateFrame("Frame", nil, f.Client)
	body:SetPoint("TOPLEFT", Layout.pad, -(Layout.headerHeight + Layout.pad))
	body:SetPoint("BOTTOMRIGHT", -Layout.pad, Layout.pad)

	local detail = F.CreatePanel(body, Colors.panel, true)
	detail:SetPoint("TOPRIGHT")
	detail:SetPoint("BOTTOMRIGHT")
	detail:SetWidth(Layout.detailWidth)

	local main = CreateFrame("Frame", nil, body)
	main:SetPoint("TOPLEFT")
	main:SetPoint("BOTTOMRIGHT", detail, "BOTTOMLEFT", -Layout.gap, 0)

	self:BuildDetail(detail)
	self:BuildGallery(main)
	self:BuildSheet(main)
	self:SetMode("gallery")

	-- Arrow keys through the grid. The nav button receives the keys through override
	-- bindings that exist only while the window is shown. A focused edit box eats
	-- keys itself, so the search box forwards its arrow presses (see BuildGallery).
	local nav = CreateFrame("Button", "AtlasViewerNavButton", f)
	nav:RegisterForClicks("AnyDown")
	nav:SetScript("OnClick", function(_, key)
		self:HandleNavKey(key)
	end)
	f:HookScript("OnShow", function()
		self:UpdateNavBindings()
	end)
	f:HookScript("OnHide", ClearOverrideBindings)
end

-- The arrow keys belong to the grid only while the gallery is on screen. In the
-- sheet view they are released, so they keep moving the character and camera.
function Viewer:UpdateNavBindings()
	local f = self.frame
	if not f then
		return
	end
	if f:IsShown() and self.mode == "gallery" then
		for _, key in ipairs({ "UP", "DOWN", "LEFT", "RIGHT", "PAGEUP", "PAGEDOWN" }) do
			SetOverrideBindingClick(f, false, key, "AtlasViewerNavButton", key)
		end
	else
		ClearOverrideBindings(f)
	end
end

function Viewer:HandleNavKey(key)
	local grid = self.Grid
	if self.mode ~= "gallery" or not grid or not grid.cols then
		return
	end
	local cols = grid.cols
	if key == "UP" then
		self:MoveSelection(-cols)
	elseif key == "DOWN" then
		self:MoveSelection(cols)
	elseif key == "LEFT" then
		self:MoveSelection(-1)
	elseif key == "RIGHT" then
		self:MoveSelection(1)
	elseif key == "PAGEUP" then
		self:MoveSelection(-cols * (grid.rowsVisible or 1))
	elseif key == "PAGEDOWN" then
		self:MoveSelection(cols * (grid.rowsVisible or 1))
	end
end

function Viewer:SetMode(mode)
	self.mode = mode
	self.GalleryPanel:SetShown(mode == "gallery")
	self.SheetPanel:SetShown(mode == "sheet")
	if self.OpenSheetButton then
		self.OpenSheetButton:SetActive(mode == "sheet")
	end
	self:UpdateNavBindings()
end

function Viewer:Toggle(searchText)
	ns:EnsureData()
	local firstBuild = not self.frame
	self:Build()

	if self.frame:IsShown() and (not searchText or searchText == "") then
		self.frame:Hide()
		return
	end
	self.frame:Show()
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)

	if firstBuild then
		self:RunSearch()
	end
	if searchText and searchText ~= "" then
		self:SetMode("gallery")
		self.SearchBox:SetText(searchText) -- fires OnTextChanged, which searches
	end
end
