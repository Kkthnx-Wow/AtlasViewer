-- AtlasViewer, a texture atlas browser. Standalone addon with no libraries, built
-- from plain frames and the game's own atlas art.
--
-- Everything hangs off `ns`. Nothing touches _G unless the API forces it to.
local addonName, ns = ...

ns.C = ns.C or {} -- Constants (colors, media/textures, layout)
ns.L = ns.L or {} -- Locale strings
ns.F = ns.F or {} -- Frame/widget factory helpers

ns.addonName = addonName

-- ---------------------------------------------------------------------------
-- Tiny event dispatcher. One frame, many listeners, keyed by event name.
-- A map of callbacks is all this addon needs.
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local listeners = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = listeners[event]
	if not list then
		return
	end
	for i = 1, #list do
		list[i](event, ...)
	end
end)

-- Register a callback for a Blizzard event. Callback gets (event, ...payload).
function ns:RegisterEvent(event, callback)
	local list = listeners[event]
	if not list then
		list = {}
		listeners[event] = list
		eventFrame:RegisterEvent(event)
	end
	list[#list + 1] = callback
end
