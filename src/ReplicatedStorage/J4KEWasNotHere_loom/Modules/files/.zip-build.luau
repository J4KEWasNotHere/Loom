-- PackageZipBuilder-0.4

local HttpService = game:GetService("HttpService")
local File = script.Parent

-- Modules
local Modules = File:FindFirstAncestor("Modules")
local package_instancer = require(Modules.common["package-instancer"])
local toml_formatter = require(Modules.files[".toml-formatter"])

-- Packages
local Packages = Modules.Parent.Packages
local zzlib = require(Packages.ZZLib)

local ZipBuild = { debugCallbacks = {} }
ZipBuild.__index = ZipBuild

local function formatBytes(bytes)
	local suffixes = { "B", "KB", "MB", "GB", "TB", "PB" }
	local i = 1
	while bytes >= 1024 and i < #suffixes do
		bytes = bytes / 1024
		i += 1
	end
	return string.format("%.1f %s", bytes, suffixes[i])
end

local function getScriptType(filename)
	if filename:match("%.server%.luau?$") then
		return "Script"
	elseif filename:match("%.client%.luau?$") then
		return "LocalScript"
	else
		return "ModuleScript"
	end
end

local function getScriptName(filename)
	return filename:match("^(.-)%.server%.luau?$")
		or filename:match("^(.-)%.client%.luau?$")
		or filename:match("^(.-)%.luau?$")
		or filename
end

local function isLuauFile(name)
	return name:match("%.luau?$") ~= nil
end

local function normalizeScriptPath(path)
	return (path:gsub("%.server%.luau?$", ""):gsub("%.client%.luau?$", ""):gsub("%.luau?$", ""))
end

local function applyMetaProperties(object, meta)
	if not object or type(meta) ~= "table" then
		return
	end

	local properties = meta.properties
	if type(properties) == "table" then
		for key, value in pairs(properties) do
			local ok = pcall(function()
				object[key] = value
			end)
			if not ok and type(value) == "string" then
				-- Fallback for Enum-typed properties (e.g. RunContext = "Client")
				local enumType = Enum[key]
				if enumType then
					pcall(function()
						object[key] = enumType[value]
					end)
				end
			end
		end
	end

	local attributes = meta.attributes
	if type(attributes) == "table" then
		for key, value in pairs(attributes) do
			pcall(function()
				object:SetAttribute(key, value)
			end)
		end
	end
end

-- Glob matching -----------------------------------------------------------

-- Converts a wally-style glob pattern into a Lua pattern string.
-- Supports:  **  (any path, including slashes)
--             *  (any segment, no slashes)
--             ?  (single char, no slash)
local function globToLuaPattern(glob)
	local p = glob:gsub("([%.%+%-%^%$%(%)%[%]%{%}])", "%%%1")
	p = p:gsub("%*%*", "\1")
	p = p:gsub("%*", "[^/]*")
	p = p:gsub("\1", ".*")
	p = p:gsub("%?", "[^/]")
	return "^" .. p .. "$"
end

--[[
	Returns true when `path` matches `glob`.
	A directory-style pattern like "src" also matches "src/anything".
]]
local function matchGlob(glob, path)
	local exact = globToLuaPattern(glob)
	if path:match(exact) then
		return true
	end
	local prefix = globToLuaPattern(glob:gsub("/$", "")) -- strip trailing /
	return path:match("^" .. prefix:sub(2, -2) .. "/") ~= nil
end

--[[
	Given include/exclude lists from wally.toml, decides whether a zip path
	should be processed.
]]
local function passesFilter(path, includes, excludes)
	local hasIncludes = includes and #includes > 0
	local hasExcludes = excludes and #excludes > 0

	local excluded = false
	if hasExcludes then
		for _, pat in ipairs(excludes) do
			if matchGlob(pat, path) then
				excluded = true
				break
			end
		end
	end

	if hasIncludes then
		for _, pat in ipairs(includes) do
			if matchGlob(pat, path) then
				return true
			end
		end
		return false
	end

	return not excluded
end

-- Instance helpers ---------------------------------------------------------

local function new(className, properties)
	local ok, obj = pcall(Instance.new, className)
	if not ok then
		warn(`[instancer]: {obj}`)
		return nil
	end
	for prop, value in pairs(properties) do
		local ok2, err = pcall(function()
			obj[prop] = value
		end)
		if not ok2 then
			warn(`[instancer]: {err}`)
		end
	end
	return obj
end

local function inst(className, properties)
	local ok, obj = pcall(Instance.new, className)
	if not ok then
		warn(`[instancer]: {obj}`)
		ZipBuild.__log(`[instancer]: Failed to create {className} – {obj}`)
		return nil
	end
	for prop, value in pairs(properties) do
		local ok2, err = pcall(function()
			obj[prop] = value
		end)
		if not ok2 then
			ZipBuild.__log(`[instancer]: {err}`)
		end
	end
	return obj
end

local function resolveParent(root, dirPath, folderCache)
	if dirPath == "" then
		return root
	end
	if folderCache[dirPath] then
		return folderCache[dirPath]
	end

	local parts = {}
	for part in dirPath:gmatch("[^/]+") do
		table.insert(parts, part)
	end

	local current = root
	local built = ""
	for _, part in ipairs(parts) do
		built = built == "" and part or (built .. "/" .. part)
		if folderCache[built] then
			current = folderCache[built]
		else
			local child = current:FindFirstChild(part) or Instance.new("Folder")
			child.Name = part
			child.Parent = current
			folderCache[built] = child
			current = child
		end
	end

	return current
end

-- Private ------------------------------------------------------------------

function ZipBuild.__log(...)
	local msg = table.concat({ ... }, " ")
	task.spawn(function()
		for _, cb in ZipBuild.debugCallbacks do
			cb(msg)
		end
	end)
end

local initNames = { "init", "init.luau", "init.lua" }

local function isInitFile(filename)
	return table.find(initNames, filename) ~= nil
end

---- Project file (Rojo) path remapping -------------------------------------

local function readZipEntryContent(buf, wantedPath)
	for _, name, offset, size, packed, crc in zzlib.files(buf) do
		if name == wantedPath then
			if packed then
				local ok, result = pcall(zzlib.unzip, buf, offset, crc)
				return ok and result or nil
			end
			return buf:sub(offset, offset + size - 1)
		end
	end
	return nil
end

local function findProjectFilePath(buf)
	local best, bestDepth
	for _, name in zzlib.files(buf) do
		if name:match("default%.project%.json$") then
			local depth = select(2, name:gsub("/", "/"))
			if not best or depth < bestDepth then
				best, bestDepth = name, depth
			end
		end
	end
	return best
end

local function decodeProjectJson(content)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(content)
	end)
	return ok and data or nil
end

local function joinPath(base, rel)
	rel = rel:gsub("^%./", "")
	if base == "" or base == nil then
		return rel
	elseif rel == "" then
		return base
	end
	return base .. "/" .. rel
end

--[[
	Walks a Rojo project "tree" table, recursively following $path entries
	that point at *other* project.json files, and records every real
	filesystem $path as {physical = <zip path>, logical = <instance path>}.
]]
local function walkProjectTree(buf, node, basePath, logicalPath, mappings, depth)
	depth = depth or 0
	if depth > 12 or type(node) ~= "table" then
		return
	end

	local nodePath = node["$path"]
	if type(nodePath) == "string" then
		local physical = joinPath(basePath, nodePath)
		if physical:match("%.project%.json$") then
			local content = readZipEntryContent(buf, physical)
			local nested = content and decodeProjectJson(content)
			if nested and type(nested.tree) == "table" then
				local nestedBase = physical:match("^(.*)/[^/]+$") or ""
				walkProjectTree(buf, nested.tree, nestedBase, logicalPath, mappings, depth + 1)
			end
		else
			table.insert(mappings, { physical = physical, logical = logicalPath })
		end
	end

	for key, value in pairs(node) do
		if type(key) == "string" and key:sub(1, 1) ~= "$" and type(value) == "table" then
			local childLogical = (logicalPath == "") and key or (logicalPath .. "/" .. key)
			walkProjectTree(buf, value, basePath, childLogical, mappings, depth + 1)
		end
	end
end

local function getProjectPathMappings(buf)
	local rootPath = findProjectFilePath(buf)
	if not rootPath then
		return nil
	end

	local rootContent = readZipEntryContent(buf, rootPath)
	local project = rootContent and decodeProjectJson(rootContent)
	if not project or type(project.tree) ~= "table" then
		return nil
	end

	local rootBase = rootPath:match("^(.*)/[^/]+$") or ""
	local mappings = {}
	walkProjectTree(buf, project.tree, rootBase, "", mappings)

	if #mappings == 0 then
		return nil
	end

	-- Longest physical prefix wins so nested $path overrides ("src/Packages")
	-- take priority over their parent ("src").
	table.sort(mappings, function(a, b)
		return #a.physical > #b.physical
	end)

	return mappings
end

local function remapPhysicalPath(path, mappings)
	if not mappings then
		return path
	end
	for _, mapping in ipairs(mappings) do
		local physical = mapping.physical
		if path == physical then
			return mapping.logical
		elseif path:sub(1, #physical + 1) == physical .. "/" then
			local rest = path:sub(#physical + 2)
			return mapping.logical == "" and rest or (mapping.logical .. "/" .. rest)
		end
	end
	return path
end

---- Importer ---------------------------------------------------------------

local function getShortPackageName(toml)
	local pkg = toml.package or toml
	local name = pkg.name or ""
	return name:match("/([^/]+)$") or name
end

--[[
	Core import logic.
]]
local function importZip(buf, root, includes, excludes, pathMappings)
	local folderCache = {}
	local createdByKey = {}
	local metaFiles = {}
	local imported = 0
	local skipped = 0
	local rootInit = nil
	local wallyData = nil

	local entries = {}
	for _, name, offset, size, packed, crc in zzlib.files(buf) do
		table.insert(entries, { name = name, offset = offset, size = size, packed = packed, crc = crc })
	end

	table.sort(entries, function(a, b)
		local aInit = isInitFile(a.name:match("[^/]+$") or a.name)
		local bInit = isInitFile(b.name:match("[^/]+$") or b.name)
		if aInit ~= bInit then
			return aInit
		end
		return a.name < b.name
	end)

	for _, entry in ipairs(entries) do
		local name = entry.name
		local offset = entry.offset
		local size = entry.size
		local packed = entry.packed
		local crc = entry.crc

		local isLuau = isLuauFile(name)
		local isWally = name:match("wally%.toml$") ~= nil
		local isMeta = name:match("%.meta%.json$") ~= nil
		local isDir = name:match("/$") ~= nil

		if isDir then
			skipped += 1
			continue
		end

		if not isWally and not isMeta and not passesFilter(name, includes, excludes) then -- CHANGED
			ZipBuild.__log(`[ZipImporter] Filtered out: "{name}"`)
			skipped += 1
			continue
		end

		if not isLuau and not isWally and not isMeta then
			skipped += 1
			continue
		end

		local content
		if packed then
			local ok, result = pcall(zzlib.unzip, buf, offset, crc)
			if not ok then
				ZipBuild.__log(`[ZipImporter] Skipped "{name}": {result}`)
				skipped += 1
				continue
			end
			content = result
		else
			content = buf:sub(offset, offset + size - 1)
		end

		if isWally then
			local ok, result = pcall(toml_formatter.format, content)
			if ok then
				wallyData = result
				ZipBuild.__log(`[ZipImporter] Parsed wally.toml`)
			else
				ZipBuild.__log(`[ZipImporter] Failed to parse wally.toml: {result}`)
			end
			continue
		end

		if isMeta then
			local remappedMetaName = remapPhysicalPath(name, pathMappings)
			local key = normalizeScriptPath((remappedMetaName:gsub("%.meta%.json$", "")))
			table.insert(metaFiles, { key = key, content = content, name = name })
			continue
		end

		-- Resolve path parts (remapped through the project file, if any)
		local remappedName = remapPhysicalPath(name, pathMappings)
		local dir, filename = remappedName:match("^(.*)/([^/]+)$")
		if not dir then
			dir = ""
			filename = remappedName
		end

		local scriptType = getScriptType(filename)
		local scriptName = getScriptName(filename)
		local parentInstance
		local mergeFolder = nil

		local metaKey = normalizeScriptPath(remappedName)

		if scriptName == "init" and dir ~= "" and dir ~= "src" then
			local dirParts = {}
			for part in dir:gmatch("[^/]+") do
				table.insert(dirParts, part)
			end

			local instanceName = table.remove(dirParts)
			local parentDir = table.concat(dirParts, "/")
			parentInstance = resolveParent(root, parentDir, folderCache)
			scriptName = instanceName

			local cacheKey = dir
			local existing = folderCache[cacheKey]
			if not existing and parentInstance then
				existing = parentInstance:FindFirstChild(instanceName)
			end
			if existing and existing:IsA("Folder") then
				mergeFolder = existing
			end
			folderCache[cacheKey] = nil
		else
			parentInstance = resolveParent(root, dir, folderCache)
		end

		local object = inst(scriptType, {
			Name = scriptName or name or "ErrNoName",
			Source = content or 'return {err = "NoSource"}',
			Parent = parentInstance or game.ServerStorage,
		})

		if object then
			createdByKey[metaKey] = object
		end

		if object and mergeFolder then
			for _, child in ipairs(mergeFolder:GetChildren()) do
				child.Parent = object
			end
			mergeFolder:Destroy()
		end

		if object then
			local logicalPath = dir == "" and scriptName or `{dir}/{scriptName}`
			if not folderCache[logicalPath] then
				folderCache[logicalPath] = object
			end
		end

		if
			not rootInit
			and dir == ""
			and object
			and object:IsA("ModuleScript")
			and isInitFile(filename)
			and parentInstance == root
		then
			rootInit = object
		end

		ZipBuild.__log(`[ZipImporter] Imported {scriptType} "{scriptName}" from "{name}"`)
		imported += 1
	end

	if rootInit and wallyData then
		local shortName = getShortPackageName(wallyData)
		if shortName ~= "" then
			rootInit.Name = shortName
		end
	end

	if rootInit then
		for _, child in ipairs(root:GetChildren()) do
			if child ~= rootInit then
				child.Parent = rootInit
			end
		end
	end

	for _, meta in ipairs(metaFiles) do
		local target = createdByKey[meta.key]
		if not target then
			ZipBuild.__log(`[ZipImporter] No matching instance for meta file "{meta.name}"`)
			continue
		end

		local ok, parsed = pcall(function()
			return HttpService:JSONDecode(meta.content)
		end)

		if not ok or type(parsed) ~= "table" then
			ZipBuild.__log(`[ZipImporter] Failed to parse meta file "{meta.name}"`)
			continue
		end

		applyMetaProperties(target, parsed)
		ZipBuild.__log(`[ZipImporter] Applied meta properties from "{meta.name}" to "{target:GetFullName()}"`)
	end

	return imported, skipped, rootInit, wallyData
end

---- Toml helpers -------------------------------------------------------------

local function getDataFromToml(toml)
	local pkg = toml.package or toml
	local name = pkg.name
	local ver = pkg.version
	local realm = pkg.realm
	local license = pkg.license
	local result = `{name}@{ver}`

	for i = 1, #result do
		if result:sub(i, i) == "/" then
			result = `{result:sub(1, i - 1)}_{result:sub(i + 1)}`
			break
		end
	end

	return result, realm == "shared", license or "", pkg.description or ""
end

local function getDependenciesFromToml(toml)
	local deps = {}
	local sections = {
		{ key = "dependencies", realm = "shared" },
		{ key = "server-dependencies", realm = "server" },
		{ key = "dev-dependencies", realm = "dev" },
	}
	for _, section in ipairs(sections) do
		local entries = toml[section.key]
		if type(entries) == "table" then
			for depName, specifier in pairs(entries) do
				table.insert(deps, { name = depName, specifier = specifier, realm = section.realm })
				ZipBuild.__log(`[ZipImporter] Dependency: {depName} = "{specifier}" ({section.realm})`)
			end
		end
	end
	return deps
end

--[[
	Reads include/exclude lists from a parsed wally.toml.
	They live either directly on the root table or under [package].
]]
local function getFilterFromToml(toml)
	local src = toml.package or toml
	local includes = type(src.include) == "table" and src.include or {}
	local excludes = type(src.exclude) == "table" and src.exclude or {}
	return includes, excludes
end

---- Public API ---------------------------------------------------------------

function ZipBuild.bindDebugCallback(callback: (string) -> ())
	table.insert(ZipBuild.debugCallbacks, callback)
end

function ZipBuild.clearBinds()
	table.clear(ZipBuild.debugCallbacks)
end

--[[
	Returns: targetObject, initScript, wallyData, dependencies
]]
function ZipBuild.createFromFile(file: File, folder: Folder?)
	ZipBuild.__log(`[ZipImporter]: Importing {file.Name}...`)

	local folderWasNil = folder == nil
	local targetObject = folder or new("Folder", { Name = file.Name, Parent = game.TestService })
	local raw = file:GetBinaryContents()

	-- Log raw entries
	for _, name, offset, size, packed, crc in zzlib.files(raw) do
		ZipBuild.__log("[ZipImporter]:", name, formatBytes(size), packed and "(compressed)" or "(stored)")
	end

	-- Pre-scan for wally.toml to get include/exclude before importing
	local includes, excludes = {}, {}
	for _, name, offset, size, packed, crc in zzlib.files(raw) do
		if name:match("wally%.toml$") then
			local content
			if packed then
				local ok, result = pcall(zzlib.unzip, raw, offset, crc)
				if ok then
					content = result
				end
			else
				content = raw:sub(offset :: number, offset + size - 1)
			end
			if content then
				local ok, toml = pcall(toml_formatter.format, content)
				if ok and toml then
					includes, excludes = getFilterFromToml(toml)
					if #includes > 0 then
						ZipBuild.__log(`[ZipImporter] Include filter: {table.concat(includes, ", ")}`)
					end
					if #excludes > 0 then
						ZipBuild.__log(`[ZipImporter] Exclude filter: {table.concat(excludes, ", ")}`)
					end
				end
			end
			break
		end
	end

	local pathMappings = getProjectPathMappings(raw)
	if pathMappings then
		ZipBuild.__log(`[ZipImporter] Found project file remapping ({#pathMappings} path(s))`)
	end

	local ok, imported, skipped, init, wally = pcall(importZip, raw, targetObject, includes, excludes, pathMappings)
	if ok then
		if init then
			ZipBuild.__log(`[ZipImporter]: Root module -> {init:GetFullName()}`)
		end

		local dependencies = nil
		if wally then
			ZipBuild.__log(`[ZipImporter]: wally.toml parsed successfully`)
			local formatName, isShared, license, description = getDataFromToml(wally)
			if folderWasNil then
				targetObject.Name = formatName
			end
			targetObject:SetAttribute("isShared", isShared)
			targetObject:SetAttribute("license", license ~= "" and license or nil)
			targetObject:SetAttribute("description", description)
			dependencies = getDependenciesFromToml(wally)
			ZipBuild.__log(`[ZipImporter]: {#dependencies} dependenc{#dependencies == 1 and "y" or "ies"} found`)
		end

		ZipBuild.__log(`[ZipImporter]: Done – {imported} scripts imported, {skipped} skipped`)
		return targetObject, init, wally, dependencies
	else
		local err = tostring(imported)
		ZipBuild.__log(`[ZipImporter]: Failed to import {file.Name} – {err}`)
		return nil, nil, nil, nil
	end
end

--[[
	Returns: targetObject, initScript, wallyData, dependencies
]]
function ZipBuild.createFromRaw(raw, name, folder: Folder?)
	ZipBuild.__log(`[ZipImporter]: Importing from raw...`)

	local folderWasNil = folder == nil
	local targetObject = folder or new("Folder", { Name = name, Parent = game.TestService })

	-- Pre-scan for wally.toml
	local includes, excludes = {}, {}
	for _, entryName, offset, size, packed, crc in zzlib.files(raw) do
		if entryName:match("wally%.toml$") then
			local content
			if packed then
				local ok, result = pcall(zzlib.unzip, raw, offset, crc)
				if ok then
					content = result
				end
			else
				content = raw:sub(offset, offset + size - 1)
			end
			if content then
				local ok, toml = pcall(toml_formatter.format, content)
				if ok and toml then
					includes, excludes = getFilterFromToml(toml)
				end
			end
			break
		end
	end

	local pathMappings = getProjectPathMappings(raw)
	if pathMappings then
		ZipBuild.__log(`[ZipImporter] Found project file remapping ({#pathMappings} path(s))`)
	end

	local ok, imported, skipped, init, wally = pcall(importZip, raw, targetObject, includes, excludes, pathMappings)
	if ok then
		local dependencies = nil
		if wally then
			local formatName, isShared, license, description = getDataFromToml(wally)
			if folderWasNil then
				targetObject.Name = formatName
			end
			targetObject:SetAttribute("isShared", isShared)
			targetObject:SetAttribute("license", license ~= "" and license or nil)
			targetObject:SetAttribute("description", description)
			dependencies = getDependenciesFromToml(wally)
			ZipBuild.__log(`[ZipImporter]: {#dependencies} dependenc{#dependencies == 1 and "y" or "ies"} found`)
		end

		ZipBuild.__log(`[ZipImporter]: Done – {imported} scripts imported, {skipped} skipped`)
		return targetObject, init, wally, dependencies
	else
		local err = tostring(imported)
		ZipBuild.__log(`[ZipImporter]: Failed to import {name} – {err}`)
		return nil, nil, nil, nil
	end
end

return ZipBuild