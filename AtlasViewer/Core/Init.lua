-- Boot: register the slash command and be a good citizen by hiding out of combat.
-- The dataset is built lazily on first open (see ns:EnsureData), so there's no
-- login-time work to do here.
local _, ns = ...

-- Close the window when entering combat; StartMoving/secure taint aside, it's
-- just polite not to cover the screen mid-pull.
ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if ns.Viewer and ns.Viewer.frame and ns.Viewer.frame:IsShown() then
		ns.Viewer.frame:Hide()
	end
end)

SLASH_ATLASVIEWER1 = "/atlasviewer"
SLASH_ATLASVIEWER2 = "/av"
SlashCmdList.ATLASVIEWER = function(msg)
	if InCombatLockdown() then
		return
	end
	msg = (msg or ""):trim()
	if msg == "dump" or msg == "dump clear" then
		ns:EnsureData()
		if msg == "dump clear" then
			ns.db.harvest = nil
			print(ns.C.BrandName .. ": " .. ns.L["Client dump cleared."])
			return
		end
		local count = ns:DumpLive()
		if count then
			print(ns.C.BrandName .. ": " .. ns.L["Saved %d atlases. Log out or /reload, then run update_atlas_data.py --from-client."]:format(count))
		else
			print(ns.C.BrandName .. ": " .. ns.L["This client cannot list its atlases."])
		end
		return
	end
	if msg == "probe" then
		-- Reports which window art this client resolves, so a flat fallback is explainable.
		local kit = ns.C.Layout.frameKit
		for _, fmt in ipairs({
			"%s-NineSlice-CornerTopLeft", "%s-NineSlice-CornerTopRight",
			"%s-NineSlice-CornerBottomLeft", "%s-NineSlice-CornerBottomRight",
			"_%s-NineSlice-EdgeTop", "_%s-NineSlice-EdgeBottom",
			"!%s-NineSlice-EdgeLeft", "!%s-NineSlice-EdgeRight",
		}) do
			local name = fmt:format(kit)
			print(ns.C.BrandName .. ": " .. name .. " " .. (C_Texture.GetAtlasInfo(name) and "found" or "missing"))
		end
		print(ns.C.BrandName .. ": window art " .. ((ns.Viewer.frame and ns.Viewer.frame.metalFallback) and "flat fallback" or "metal"))
		return
	end
	ns.Viewer:Toggle(msg)
end
