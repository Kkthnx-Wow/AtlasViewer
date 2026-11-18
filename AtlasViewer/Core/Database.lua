-- Saved variables, the atlas dataset, and the search index.
--
-- Why we ship a data file: there is no client API to enumerate atlas *names*
-- (C_Texture.GetAtlasInfo only answers if you already know the name), except
-- C_Texture.GetAtlasElements on clients that have it. Bundled dumps are verified
-- against the live API at load, and names the client no longer knows are kept
-- as flagged "missing" entries so they still draw.
local _, ns = ...
local C = ns.C

local tinsert, tremove, tsort = table.insert, table.remove, table.sort
local strlower = string.lower

local DEFAULTS = {
	settings = {
		showIssues = false,
		cellSize = C.Layout.cellDefault,
		previewZoom = 0, -- 0 fits the preview, otherwise a fixed multiplier
		background = { r = 0.10, g = 0.11, b = 0.13, a = 1 },
	},
	favorites = {},
	recent = {},
	window = {},
}

-- Merge saved values over defaults without clobbering user data.
local function applyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then
				target[k] = {}
			end
			applyDefaults(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
end

function ns:InitDB()
	AtlasViewerDB = AtlasViewerDB or {}
	-- A client dump left by /av dump is several MB of saved variables. Keep it long
	-- enough to run the updater, then drop it so it stops loading every login.
	local harvest = AtlasViewerDB.harvest
	if harvest and (not harvest.stamp or time() - harvest.stamp > 3 * 86400) then
		AtlasViewerDB.harvest = nil
	end
	-- 1.0 saved a "passiveBorders" flag the new design has no use for.
	if AtlasViewerDB.settings then
		AtlasViewerDB.settings.passiveBorders = nil
	end
	applyDefaults(AtlasViewerDB, DEFAULTS)
	self.db = AtlasViewerDB
	self.settings = AtlasViewerDB.settings
end

-- Look up an atlas: prefer the bundled backup flag for names the client lost,
-- otherwise ask the live API.
function ns:GetAtlasInfo(atlasName)
	if self.backup and self.backup[atlasName] then
		return self.backup[atlasName]
	end
	return C_Texture.GetAtlasInfo(atlasName)
end

-- ---------------------------------------------------------------------------
-- Favorites and recents
-- ---------------------------------------------------------------------------
function ns:IsFavorite(name)
	return self.db.favorites[name] == true
end

function ns:ToggleFavorite(name)
	local favs = self.db.favorites
	if favs[name] then
		favs[name] = nil
	else
		favs[name] = true
	end
	return favs[name] == true
end

-- Newest first, no duplicates, capped.
function ns:AddRecent(name)
	local recent = self.db.recent
	for i = #recent, 1, -1 do
		if recent[i] == name then
			tremove(recent, i)
		end
	end
	tinsert(recent, 1, name)
	for i = #recent, C.Search.recentLimit + 1, -1 do
		recent[i] = nil
	end
end

-- ---------------------------------------------------------------------------
-- Dataset
-- ---------------------------------------------------------------------------
-- Townlong occasionally ships keys like "Interface/ Garrison/..." (space after
-- the slash). Those won't load via SetTexture, so crush the junk on ingest.
local function normalizeTextureKey(key)
	return (key:gsub("/%s+", "/"))
end

-- Read the whole atlas set from the running client. Returns the same
-- texture -> { atlas -> { w, h, l, r, t, b, tilesH, tilesV } } shape the Data
-- files use, or nil when the API is missing.
function ns:HarvestLive()
	local getElements = C_Texture and C_Texture.GetAtlasElements
	if not getElements then
		return nil
	end
	local ok, names = pcall(getElements)
	if not ok or type(names) ~= "table" then
		return nil
	end

	local getInfo = C_Texture.GetAtlasInfo
	local raw = {}
	for i = 1, #names do
		local name = names[i]
		local info = getInfo(name)
		if info then
			-- Group by texture file like the dump does. A bare fileDataID stays a
			-- string and is coerced when displayed.
			local key
			if info.filename and info.filename ~= "" then
				key = tostring(info.filename):gsub("\\", "/")
				key = key:gsub("%.%w+$", "")
			elseif info.file then
				key = tostring(info.file)
			end
			if key then
				local map = raw[key]
				if not map then
					map = {}
					raw[key] = map
				end
				map[name] = {
					info.width,
					info.height,
					info.leftTexCoord,
					info.rightTexCoord,
					info.topTexCoord,
					info.bottomTexCoord,
					info.tilesHorizontally,
					info.tilesVertically,
				}
			end
		end
	end
	return raw
end

-- Writes every atlas the running client knows into the saved variables, so
-- update_atlas_data.py --from-client can turn it into a Data file for exactly this
-- build. One line per atlas: name|file|w|h|left|right|top|bottom|tilesH|tilesV.
-- Returns the atlas count, or nil when this client cannot list atlases.
function ns:DumpLive()
	local raw = self:HarvestLive()
	if not raw then
		return nil
	end
	local lines = {}
	for file, map in pairs(raw) do
		for name, v in pairs(map) do
			lines[#lines + 1] = string.format(
				"%s|%s|%d|%d|%.8g|%.8g|%.8g|%.8g|%d|%d",
				name, file, v[1], v[2], v[3], v[4], v[5], v[6], v[7] and 1 or 0, v[8] and 1 or 0
			)
		end
	end
	tsort(lines)
	self.db.harvest = {
		build = tonumber((select(2, GetBuildInfo()))),
		project = WOW_PROJECT_ID,
		stamp = time(),
		lines = lines,
	}
	return #lines
end

-- Build the file list (ns.entries) and the flat atlas index from ns.data, which a
-- Data file sets, or from the live client when this game type has no data.
--   ns.entries[i]      = { texture, name, path, lowerPath, count }
--   ns.atlasNames[i]   = atlas name, sorted
--   ns.atlasLower[i]   = lowercased, space-free copy for matching
--   ns.atlasFile[name] = file index into ns.entries
--   ns.atlasIndex[name]= position in ns.atlasNames
function ns:BuildAtlasList()
	self.entries = {}
	self.backup = {}
	self.atlasNames, self.atlasLower, self.atlasFile, self.atlasIndex = {}, {}, {}, {}

	local raw = self.data
	local live = false
	if type(raw) ~= "table" then
		raw = self:HarvestLive()
		if type(raw) ~= "table" then
			return
		end
		live = true
		self.data = raw
		self.dataBuild = tonumber((select(2, GetBuildInfo())))
	end

	-- Rewrite keys once so lookups and SetTexture agree.
	local cleaned = {}
	for texture, atlasMap in pairs(raw) do
		local key = normalizeTextureKey(texture)
		if cleaned[key] then
			for atlasName, info in pairs(atlasMap) do
				if cleaned[key][atlasName] == nil then
					cleaned[key][atlasName] = info
				end
			end
		else
			cleaned[key] = atlasMap
		end
	end
	self.data = cleaned

	local getInfo = C_Texture.GetAtlasInfo
	for texture, atlasMap in pairs(cleaned) do
		local count = 0
		for atlasName, info in pairs(atlasMap) do
			count = count + 1
			-- Keep bundled numbers for names the live API does not know so they
			-- still draw, flagged as missing.
			if not live and not getInfo(atlasName) then
				self.backup[atlasName] = {
					missing = true,
					width = info[1],
					height = info[2],
					leftTexCoord = info[3],
					rightTexCoord = info[4],
					topTexCoord = info[5],
					bottomTexCoord = info[6],
					tilesHorizontally = info[7],
					tilesVertically = info[8],
				}
			end
		end
		-- Keys are a path ("Interface/Foo/Bar") or a bare fileDataID string.
		local path, name = texture:match("(.+)/(.+)")
		self.entries[#self.entries + 1] = {
			texture = texture,
			name = name or texture,
			path = path,
			lowerPath = strlower(texture),
			count = count,
		}
	end
	tsort(self.entries, function(a, b)
		if a.name == b.name then
			return a.texture < b.texture
		end
		return a.name < b.name
	end)

	local names = self.atlasNames
	for i = 1, #self.entries do
		local entry = self.entries[i]
		for atlasName in pairs(cleaned[entry.texture]) do
			names[#names + 1] = atlasName
			self.atlasFile[atlasName] = i
		end
	end
	tsort(names)
	for i = 1, #names do
		local n = names[i]
		self.atlasLower[i] = strlower(n):gsub(" ", "")
		self.atlasIndex[n] = i
	end
end

-- Load on demand: settings and the (large) index are only built the first time
-- the window opens, so people who never open it pay nothing at login.
function ns:EnsureData()
	if not self.settings then
		self:InitDB()
	end
	if self.entries then
		return
	end
	self:BuildAtlasList()
	if #self.entries == 0 then
		print(C.BrandName .. "|cffffffff:|r " .. ns.L["No atlas data loaded."])
	end
end

-- Raw bundled numbers for an atlas, or nil. Cheaper than the API for filters.
function ns:GetRaw(atlasName)
	local entry = self.entries[self.atlasFile[atlasName] or 0]
	local map = entry and self.data[entry.texture]
	return map and map[atlasName]
end

-- ---------------------------------------------------------------------------
-- Search. Returns an array of indices into ns.atlasNames, best matches first.
-- Ranking buckets: name starts with the query, name contains it, file path
-- contains it. Each bucket keeps the global alphabetical order, so no sort runs.
-- opts: scope ("all" | "favorites" | "recent"), tilingOnly, showIssues.
-- ---------------------------------------------------------------------------
function ns:Search(query, opts)
	local names, lowers = self.atlasNames, self.atlasLower
	local results = {}
	if not names then
		return results
	end
	local needle = strlower(query or ""):gsub(" ", "")
	local scope = opts.scope or "all"
	local tilingOnly, showIssues = opts.tilingOnly, opts.showIssues
	local backup, favs = self.backup, self.db.favorites

	local function allowed(name)
		if backup[name] and not showIssues then
			return false
		end
		if tilingOnly then
			local info = self:GetRaw(name)
			if not (info and (info[7] or info[8])) then
				return false
			end
		end
		return true
	end

	-- Recents keep their own order (newest first) and ignore ranking.
	if scope == "recent" then
		local recent = self.db.recent
		for i = 1, #recent do
			local idx = self.atlasIndex[recent[i]]
			if idx and allowed(recent[i]) and (needle == "" or lowers[idx]:find(needle, 1, true)) then
				results[#results + 1] = idx
			end
		end
		return results
	end

	local starts, contains, paths = {}, {}, {}
	local entries, fileOf = self.entries, self.atlasFile
	local onlyFavs = scope == "favorites"
	for i = 1, #names do
		local name = names[i]
		if (not onlyFavs or favs[name]) and allowed(name) then
			if needle == "" then
				starts[#starts + 1] = i
			else
				local at = lowers[i]:find(needle, 1, true)
				if at == 1 then
					starts[#starts + 1] = i
				elseif at then
					contains[#contains + 1] = i
				elseif entries[fileOf[name]].lowerPath:find(needle, 1, true) then
					paths[#paths + 1] = i
				end
			end
		end
	end
	local n = #starts
	for i = 1, #contains do
		starts[n + i] = contains[i]
	end
	n = #starts
	for i = 1, #paths do
		starts[n + i] = paths[i]
	end
	return starts
end
