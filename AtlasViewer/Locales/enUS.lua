-- enUS strings. Every user-facing literal lives here. Other locales can overwrite
-- ns.L keys after this loads.
local _, ns = ...
local L = ns.L

L["Atlas Viewer"] = ns.C.BrandName
L["No atlas data loaded."] = "No atlas data loaded."
L["Search atlas names or file paths"] = "Search atlas names or file paths"
L["%s atlases"] = "%s atlases"
L["%d atlases"] = "%d atlases"
L["Nothing matches."] = "Nothing matches."
L["Right click to favorite"] = "Right click to favorite"

-- Chips and filters
L["All"] = "All"
L["Favorites"] = "Favorites"
L["Recent"] = "Recent"
L["Tiling"] = "Tiling"
L["Tiling atlases only"] = "Tiling atlases only"
L["Issues"] = "Issues"
L["Show missing or outdated atlases"] = "Show missing or outdated atlases"
L["Atlases the client no longer resolves, drawn from the bundled data."] =
	"Atlases the client no longer resolves, drawn from the bundled data."
L["Thumbnail size"] = "Thumbnail size"

-- Detail drawer
L["Pick an atlas to see its details."] = "Pick an atlas to see its details."
L["Save"] = "Save"
L["Saved"] = "Saved"
L["Favorite"] = "Favorite"
L["Keeps this atlas in your Favorites list."] = "Keeps this atlas in your Favorites list."
L["Background color"] = "Background color"
L["Size"] = "Size"
L["Both"] = "Both"
L["Horizontal"] = "Horizontal"
L["Vertical"] = "Vertical"
L["None"] = "None"
L["Texture coordinates"] = "Texture coordinates"
L["Sheet file"] = "Sheet file"
L["The client no longer resolves this atlas. Showing bundled numbers."] =
	"The client no longer resolves this atlas. Showing bundled numbers."
L["Open sheet"] = "Open sheet"
L["Shows the whole texture file with every atlas outlined."] =
	"Shows the whole texture file with every atlas outlined."
L["Copy as, then press Ctrl+C"] = "Copy as, then press Ctrl+C"
L["Name"] = "Name"
L["Code"] = "Code"
L["Inline"] = "Inline"
L["UV"] = "UV"
L["File"] = "File"

-- Sheet
L["Gallery"] = "Gallery"
L["Fit"] = "Fit"
L["Fit to view"] = "Fit to view"
L["Previous file"] = "Previous file"
L["Next file"] = "Next file"

-- Header build chip
L["Atlas build %s"] = "Atlas build %s"
L["Atlas dump matches this client"] = "Atlas dump matches this client"
L["Newer client than atlas dump"] = "Newer client than atlas dump"
L["Client %s, dump %s. The source may not have republished yet, re-run the updater after it does."] =
	"Client %s, dump %s. The source may not have republished yet, re-run the updater after it does."

-- Client dump (/av dump)
L["Client dump cleared."] = "Client dump cleared."
L["Saved %d atlases. Log out or /reload, then run update_atlas_data.py --from-client."] =
	"Saved %d atlases. Log out or /reload, then run update_atlas_data.py --from-client."
L["This client cannot list its atlases."] = "This client cannot list its atlases."
