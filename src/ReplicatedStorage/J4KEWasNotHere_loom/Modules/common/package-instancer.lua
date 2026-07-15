local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local PackagesTag = "package-directory/@jakeboygamer64"
local DevPackagesTag = "package-directory-dev/@jakeboygamer64"

local PackageNameFormat = "%s_%s@%d.%d.%d"
local SharedOrigin = ReplicatedStorage
local ServerOrigin = ServerScriptService

local toml_formatter = require(script.Parent:FindFirstAncestor("Modules").files[".toml-formatter"])

local PackageModule = {}
PackageModule.PackagesTag = PackagesTag
PackageModule.DevPackagesTag = DevPackagesTag

-- Utility

local function insertAll(tb: {[any]: any}, ...: any)
	local args = {...}
	for _, v in ipairs(args) do
		table.insert(tb, v)
	end

	return tb
end

-- realm accepts: true/"server",
-- "dev", or anything else/nil -> shared.
local function resolveRealm(realm)
	if realm == "server" or realm == true then
		return ServerOrigin, "Packages", PackagesTag
	elseif realm == "dev" then
		return SharedOrigin, "DevPackages", DevPackagesTag
	else
		return SharedOrigin, "Packages", PackagesTag
	end
end

local function getPackageBase(name)
	return name:match("^(.-)@") or name
end

local function toString(str)
	local a1 = (type(str) == "string") and str or nil
	return (a1 and #a1 > 0) and a1 or nil
end

local function new(className, properties)
	local ok, obj = pcall(Instance.new, className)
	if not ok then
		warn(`[instancer]: {obj}`)
		return nil
	end
	for property, value in pairs(properties) do
		local setOk, err = pcall(function()
			obj[property] = value
		end)
		if not setOk then
			warn(`[instancer]: {err}`)
		end
	end
	return obj
end

local function getPathTo(origin, object)
	if object == origin then
		return "./"
	end

	local originLineage = {}
	local current = origin
	while current do
		originLineage[current] = true
		current = current.Parent
	end

	local downSegments = {}
	local commonAncestor = nil
	current = object
	while current do
		if originLineage[current] then
			commonAncestor = current
			break
		end
		table.insert(downSegments, 1, current.Name)
		current = current.Parent
	end

	if not commonAncestor then
		warn(`[getPathTo]: no common ancestor between "{origin:GetFullName()}" and "{object:GetFullName()}"`)
		return object:GetFullName()
	end

	local upCount = 0
	current = origin
	while current and current ~= commonAncestor do
		upCount += 1
		current = current.Parent
	end

	local parts: { string } = {}

	if upCount == 0 or (upCount == 1 and #downSegments > 0) then
		table.insert(parts, ".")
	else
		for _ = 1, upCount do
			table.insert(parts, "..")
		end
	end

	for _, segment in ipairs(downSegments) do
		table.insert(parts, segment)
	end

	return table.concat(parts, "/")
end

local function toInstance(inst)
	return typeof(inst) == "Instance" and inst or nil
end

local function unpackTo(inst, parent)
	parent = toInstance(parent) or inst.Parent

	for _, child in inst:GetChildren() do
		child.Parent = parent
	end

	inst:Destroy()
end

local function unpackModuleRoot(source, reference)
	source = toInstance(source)
	reference = toInstance(reference)
	if not source or not reference then
		return false
	end

	local moduleRoot = reference.Parent
	if not moduleRoot or moduleRoot == source then
		return false
	end

	if reference:IsDescendantOf(moduleRoot) then
		reference.Parent = source
	end

	unpackTo(moduleRoot, source)
	return true
end

-- Folder Helpers

local function create_folder(name, tag)
	local folder = new("Folder", { Name = name or "Packages" })
	folder:AddTag(tag or PackagesTag)
	local index = new("Folder", { Name = "_Index", Parent = folder })
	return folder, index
end

local function create_package_directory(creator, name, major, minor, patch)
	return new("Folder", {
		Name = PackageNameFormat:format(
			toString(creator) or "unknown",
			toString(name) or "untitled",
			tonumber(major) or 1,
			tonumber(minor) or 0,
			tonumber(patch) or 0
		),
	})
end

-- Smart Merge

local function merge_packages(folders, name, tag)
	local spillParent = (folders[1] and folders[1].Parent) or SharedOrigin
	local folder, index = create_folder(name or "Packages", tag)
	folder.Parent = spillParent

	for _, src in ipairs(folders) do
		for _, item in ipairs(src:GetChildren()) do
			if item.Name == "_Index" then
				for _, pkg in ipairs(item:GetChildren()) do
					if not index:FindFirstChild(pkg.Name) then
						pkg.Parent = index
					end
				end
			else
				item.Parent = folder
			end
		end
		src:Destroy()
	end

	return folder
end

-- Discovery

local function update_missing_files(packages)
	if not packages:FindFirstChild("_Index") then
		new("Folder", { Name = "_Index", Parent = packages })
	end
end

local function find_packages(realm)
	local origin, folderName, tag = resolveRealm(realm)
	local seen = {}
	local found = {}

	for _, folder in ipairs(CollectionService:GetTagged(tag)) do
		if folder:IsDescendantOf(origin) and not seen[folder] then
			seen[folder] = true
			update_missing_files(folder)
			table.insert(found, folder)
		end
	end

	local plain = origin:FindFirstChild(folderName)
	if plain and not seen[plain] then
		seen[plain] = true
		update_missing_files(plain)
		table.insert(found, plain :: Folder)
	end

	if #found == 0 then
		return nil
	elseif #found == 1 then
		return found[1]
	else
		return merge_packages(found, folderName, tag)
	end
end

local function create_packages(name, realm)
	local origin, defaultName, tag = resolveRealm(realm)
	name = name or defaultName

	local existing = find_packages(realm)
	if existing then
		if existing.Name ~= name then
			existing.Name = name
		end
		return existing
	end

	local folder, index = create_folder(name, tag)
	folder.Parent = origin
	return folder, index
end

local function createLocalDependencyDirectors(source, wallyData, realm)
	if not wallyData then return end

	local packages = find_packages(realm)
	if not packages then return end

	local dependencies = {}
	if wallyData.dependencies then
		for alias, _ in pairs(wallyData.dependencies) do
			dependencies[alias] = true
		end
	end
	if wallyData["dev-dependencies"] then
		for alias, _ in pairs(wallyData["dev-dependencies"]) do
			dependencies[alias] = true
		end
	end

	for alias, _ in pairs(dependencies) do
		local existing = source:FindFirstChild(alias)
		if existing then 
			existing:Destroy() 
		end

		local targetDirector = packages:FindFirstChild(alias)
		if targetDirector and targetDirector:IsA("ModuleScript") then
			local path = getPathTo(source, targetDirector)
			new("ModuleScript", {
				Name = alias,
				Parent = source,
				Source = `return require("{path}")`,
			})
		end
	end
end

-- Public Module API

PackageModule.inst = new
PackageModule.createPackages = create_packages

PackageModule.linkAllLocalDependencies = function(realm)
	local p = find_packages(realm)
	if not p then return end
	local index = p:FindFirstChild("_Index")
	if not index then return end

	for _, sourceFolder in ipairs(index:GetChildren()) do
		local wallyTomlModule = sourceFolder:FindFirstChild(".wally") or sourceFolder:FindFirstChild("wally")
		-- Fallback to attempting to find a parsed configuration matrix if available
		local rawAttributes = sourceFolder:GetAttributes()

		-- Look for an existing parsed file asset or structure 
		if wallyTomlModule and wallyTomlModule:IsA("ModuleScript") then
			local success, wallyData = pcall(require, wallyTomlModule)
			if success and typeof(wallyData) == "table" then
				createLocalDependencyDirectors(sourceFolder, wallyData, realm)
			end
		end
	end
end

PackageModule.createPackageDirectory = function(realm, creator, name, major, minor, patch)
	local p = find_packages(realm)
	local f = create_package_directory(creator, name, major, minor, patch)
	if p then
		local index = p:FindFirstChild("_Index")
		if not index then
			index = new("Folder", { Name = "_Index", Parent = p })
		end

		f.Parent = index
	end
	return f
end

PackageModule.addPackage = function(
	realm,
	data: {
		creator: string,
		wally: { [string]: any },
		name: string,
		major: number,
		minor: number,
		patch: number,
		source: Folder,
		display: string?,
		reference: ModuleScript?,
	}
)
	local p, index = find_packages(realm)
	local reference = data.reference
		or data.source:FindFirstChild("init", true)
		or data.source:FindFirstChild("init.lua", true)
		or data.source:FindFirstChild("init.luau", true)
		or data.source:FindFirstChildWhichIsA("ModuleScript", true)

	data.source.Parent = index

	if not p then
		warn(`[PackageModule]: no package folder found for realm "{tostring(realm)}", creating..`)
		p, index = create_packages(nil, realm)
	end
	if not reference then
		warn(`[PackageModule]: no reference found for package {data.name}, did you forget to pass it?`)
		return
	end

	local f = create_package_directory(data.creator, data.name, data.major, data.minor, data.patch)

	local code = getPathTo(f, reference)
	local name = toString(data.display) or data.name

	local m = nil
	if p:FindFirstChild(name) then
		for _, v in ipairs(p:GetChildren()) do
			if v.Name == name and v:IsA("ModuleScript") then
				warn(`[PackageModule]: duplicate package "{name}"`)
				m = v
				break
			end
		end
	else
		m = new("ModuleScript", { Name = name, Source = code, Parent = p })
	end

	if data.wally then
		toml_formatter.create(data.wally, data.source)
		createLocalDependencyDirectors(data.source, data.wally, realm)
	end

	return m, reference
end

PackageModule.syncPackage = function(
	realm,
	data: {
		source: Folder,
		wally: { [string]: any },
		name: string?,
		reference: ModuleScript?,
		unpackSrc: boolean?,
	}
)
	local p = find_packages(realm)

	if not p then
		p = create_packages(nil, realm)
	end

	local index = p:FindFirstChild("_Index")
	if not index then
		index = new("Folder", { Name = "_Index", Parent = p })
	end

	local reference = data.reference
		or data.source:FindFirstChild("init", true)
		or data.source:FindFirstChild("init.lua", true)
		or data.source:FindFirstChild("init.luau", true)
		or data.source:FindFirstChildWhichIsA("ModuleScript", true)

	if not reference then
		warn(`[PackageModule]: no reference found for package, did you forget to pass it?`)
		return
	end

	local displayName = (data.name and data.name ~= "") and data.name or data.source.Name

	for _, child in ipairs(index:GetChildren()) do
		if child.Name == displayName then
			child:Destroy()
		else
			local base = child.Name:gsub("@.+$", ""):gsub("%-%d+%.%d+%.%d+$", "")
			if base == displayName then
				child:Destroy()
			end
		end
	end

	local newBase = getPackageBase(data.source.Name)

	for _, child in ipairs(index:GetChildren()) do
		if child ~= data.source and getPackageBase(child.Name) == newBase then
			child:Destroy()
		end
	end

	data.source.Parent = index

	local m

	for _, child in ipairs(p:GetChildren()) do
		if child:IsA("ModuleScript") and child.Name == displayName then
			m = child
			break
		end
	end

	for _, child in ipairs(p:GetChildren()) do
		if child.Name == displayName and not child:IsA("ModuleScript") then
			child:Destroy()
		end
	end

	if data.unpackSrc == true then
		unpackModuleRoot(data.source, reference)
	end

	if not m then
		m = new("ModuleScript", {
			Name = displayName,
			Parent = p,
		})
	end

	local attributes = data.source:GetAttributes()
	local rawDetails = "--> " .. data.source.Name
	local desc, license = nil, nil

	for name, value in attributes do
		if name == "description" then
			desc = value
		elseif name == "license" then
			license = value
		end
	end

	if desc or license then
		local descFormat = not (desc and license) and [[--> %s
--%s]] or [[--> %s
--%s
--%s]]

		if desc and license then
			rawDetails = descFormat:format(data.source.Name, desc, `License: {license}`)
		else
			rawDetails = descFormat:format(data.source.Name, desc or `License: {license}`)
		end
	end
	m.Source = ([[%s
return require("%s")]]):format(rawDetails, getPathTo(m, reference))

	if data.wally then
		toml_formatter.create(data.wally, data.source)
		createLocalDependencyDirectors(data.source, data.wally, realm)
	end

	return m, reference
end

return PackageModule