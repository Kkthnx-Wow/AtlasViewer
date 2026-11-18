-- Palette, media paths and layout numbers. One place, so the whole addon wears
-- the same look. Colours are plain {r, g, b} arrays so panels can tint textures
-- without allocating Color objects.
local _, ns = ...
local C = ns.C

C.Colors = {
	-- Flat slate surfaces, darkest to lightest.
	void = { 0.035, 0.042, 0.055 },
	panel = { 0.060, 0.070, 0.088 },
	raised = { 0.095, 0.110, 0.135 },
	hover = { 0.135, 0.155, 0.190 },
	-- Outline colour.
	edge = { 0.20, 0.24, 0.31 }, -- 1 px outlines on every surface
	-- Ember accent, same hue as the TOC title so the AddOns list and window agree.
	accent = { 0.910, 0.737, 0.361 },
	accentDark = { 0.788, 0.580, 0.227 },
	text = { 0.87, 0.89, 0.93 },
	mute = { 0.52, 0.57, 0.65 },
	good = { 0.36, 0.78, 0.52 },
	bad = { 0.90, 0.36, 0.36 },
}

-- "Atlas" in the text colour, "Viewer" in the accent. TOC Title uses the same pair.
C.BrandName = "|cffe8edf5Atlas|r|cffe8bc5cViewer|r"

local PATH = "Interface\\AddOns\\AtlasViewer\\Textures\\"
C.Media = {
	icon = PATH .. "Icon",
}

C.Layout = {
	defaultWidth = 1180,
	defaultHeight = 720,
	minWidth = 860,
	minHeight = 520,
	headerHeight = 44,
	toolbarHeight = 34,
	detailWidth = 340,
	gap = 12,
	pad = 12,
	-- Gallery cell sizes the slider can pick from.
	cellMin = 64,
	cellMax = 160,
	cellDefault = 92,
	cellLabelHeight = 16,
	-- Window art: Blizzard nine-slice kit. The art has about 8 px of transparent
	-- padding outside the metal, and the client area sits frameInset inside the edge.
	frameKit = "GenericMetal2",
	frameOutward = 8,
	frameInset = 24,
	frameFillInset = 12, -- the window art has chamfered corners, keep the fill clear of them
	borderFill = 3, -- inset for fills under the thin tooltip border, which has rounded corners
	-- Thin kit for panels and thumbnails inside the window.
	panelKit = "Tooltip",
	-- Thickness of the invisible resize handles on each window edge.
	handleEdge = 6,
	handleCorner = 16,
}

C.Search = {
	debounce = 0.12,
	recentLimit = 60,
}
