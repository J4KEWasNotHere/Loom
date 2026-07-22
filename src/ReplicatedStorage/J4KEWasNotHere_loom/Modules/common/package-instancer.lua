local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

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

local function resolveRealm(realm)
	if typeof(realm) == "Instance" then
		return realm, "Packages", PackagesTag
	elseif realm == "server" or realm == true then
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

local function getPackageIdentifier(name)
	local scopePackage = name:match("^(.-)@") or name
	local scope, package = scopePackage:match("^([^/]+)/([^/]+)$")
	if scope and package then
		return scope .. "/" .. package
	end
	return scopePackage
end

local function getFolderVersion(name)
	return (tostring(name or ""):match("@(.+)$")) or nil
end

local function serializeList(values)
	local normalized = {}
	for _, value in ipairs(values or {}) do
		if value and tostring(value) ~= "" then
			table.insert(normalized, tostring(value))
		end
	end
	table.sort(normalized)
	return table.concat(normalized, ",")
end

local function getDependencyKeys(wallyData)
	local keys = {}
	if type(wallyData) ~= "table" then
		return keys
	end

	for _, section in ipairs({ "dependencies", "dev-dependencies" }) do
		local deps = wallyData[section]
		if type(deps) == "table" then
			for alias in pairs(deps) do
				table.insert(keys, tostring(alias))
			end
		end
	end

	table.sort(keys)
	return keys
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
		warn(
			`[getPathTo]: no common ancestor between "{origin:GetFullName()}" and "{object:GetFullName()}"`
		)
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

local function getPackageEntryPoint(folder)
	folder = toInstance(folder)
	if not folder then
		return nil
	end

	local explicit = folder:FindFirstChild("init", true) or folder:FindFirstChild("init.lua", true)
	if explicit and explicit:IsA("ModuleScript") then
		return explicit
	end

	return nil
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
	if not wallyData then
		return
	end

	local packages = find_packages(realm)
	if not packages then
		return
	end

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
			local moduleRef = new("ModuleScript", {
				Name = alias,
				Parent = source,
				Source = `return require("{path}")`,
			})
			if moduleRef then
				moduleRef:SetAttribute("loomManaged", true)
				moduleRef:SetAttribute("loomManagedTag", PackagesTag)
				moduleRef:SetAttribute("loomDependencyAlias", alias)
				moduleRef:SetAttribute("loomPackageRealm", tostring(realm))
			end
		end
	end
end

local function setPackageMetadata(source, realm, wallyData, packageIdentifier, version)
	if not source or not source:IsA("Folder") then
		return
	end

	local sourceTag = (realm == "dev") and DevPackagesTag or PackagesTag
	local deps = getDependencyKeys(wallyData)
	local packageId =
		tostring(packageIdentifier or getPackageIdentifier(source.Name) or source.Name)
	local installedVersion = tostring(version or getFolderVersion(source.Name) or "")

	source:SetAttribute("loomManaged", true)
	source:SetAttribute("loomManagedTag", sourceTag)
	source:SetAttribute("loomPackageIdentifier", packageId)
	source:SetAttribute("loomPackageVersion", installedVersion)
	source:SetAttribute("loomPackageRealm", tostring(realm or "shared"))
	source:SetAttribute(
		"loomInstallationSource",
		(realm == "server") and "server" or (realm == "dev") and "dev" or "shared"
	)
	source:SetAttribute("loomDependencyList", serializeList(deps))
	source:SetAttribute("loomReferenceCount", 0)
	source:SetAttribute("loomRootPackage", true)
end

local function getPackageRecord(folder, realm)
	if not folder or not folder:IsA("Folder") then
		return nil
	end

	local packageId = tostring(
		folder:GetAttribute("loomPackageIdentifier")
			or getPackageIdentifier(folder.Name)
			or folder.Name
	)
	local version =
		tostring(folder:GetAttribute("loomPackageVersion") or getFolderVersion(folder.Name) or "")
	local dependencies = {}
	local wallyToml = folder:FindFirstChild("wally.toml")
		or folder:FindFirstChild(".wally")
		or folder:FindFirstChild("wally")
	if wallyToml and wallyToml:IsA("ModuleScript") then
		local ok, wallyData = pcall(require, wallyToml)
		if ok and typeof(wallyData) == "table" then
			for _, alias in ipairs(getDependencyKeys(wallyData)) do
				table.insert(dependencies, alias)
			end
		end
	end

	local rootModule = nil
	local rootPackages = find_packages(realm)
	if rootPackages then
		for _, child in ipairs(rootPackages:GetChildren()) do
			if child:IsA("ModuleScript") and child.Name == packageId then
				rootModule = child
				break
			end
		end
	end

	return {
		id = packageId,
		name = packageId,
		version = version,
		realm = tostring(realm or "shared"),
		folder = folder,
		dependencies = dependencies,
		rootModule = rootModule,
		isRoot = rootModule ~= nil,
		managedTag = tostring(folder:GetAttribute("loomManagedTag") or ""),
		installedSource = tostring(
			folder:GetAttribute("loomInstallationSource") or realm or "shared"
		),
		referenceCount = tonumber(folder:GetAttribute("loomReferenceCount")) or 0,
	}
end

local function scanManagedPackages(realm)
	local results = {}
	local packages = find_packages(realm)
	if not packages then
		return results
	end

	local index = packages:FindFirstChild("_Index")
	if not index then
		return results
	end

	for _, child in ipairs(index:GetChildren()) do
		if child:IsA("Folder") then
			local record = getPackageRecord(child, realm)
			if record then
				table.insert(results, record)
			end
		end
	end

	return results
end

-- Checks all three realms' `_Index` folders for a package matching
-- scope/packageName (optionally pinned to a specific version). Returns
-- realm, sourceFolder, reference if found, or nil.
local function find_installed(scope, packageName, version)
	local base = ("%s_%s"):format(scope, packageName)
	local key = version and ("%s@%s"):format(base, version) or nil

	for _, realm in ipairs({ "shared", "server", "dev" }) do
		local p = find_packages(realm)
		if p then
			local index = p:FindFirstChild("_Index")
			if index then
				for _, child in ipairs(index:GetChildren()) do
					local matches = (key and child.Name == key)
						or (not key and getPackageBase(child.Name) == base)

					if matches then
						local reference = getPackageEntryPoint(child)
						return reference, child
					end
				end
			end
		end
	end

	return nil
end

PackageModule.inst = new
PackageModule.createPackages = create_packages
PackageModule.findInstalled = find_installed
PackageModule.scanManagedPackages = scanManagedPackages

PackageModule.getManagedPackageSummary = function()
	local entries = {}
	for _, realm in ipairs({ "shared", "server", "dev" }) do
		for _, entry in ipairs(scanManagedPackages(realm)) do
			table.insert(entries, entry)
		end
	end
	return entries
end

PackageModule.removePackage = function(realm, packageId, version)
	local packages = find_packages(realm)
	if not packages then
		return false
	end

	local index = packages:FindFirstChild("_Index")
	if not index then
		return false
	end

	local targetId = tostring(packageId or "")
	local targetVersion = tostring(version or "")
	local removed = false

	for _, child in ipairs(index:GetChildren()) do
		if child:IsA("Folder") then
			local childId = tostring(child:GetAttribute("loomPackageIdentifier") or "")
			local childVersion = tostring(
				child:GetAttribute("loomPackageVersion") or getFolderVersion(child.Name) or ""
			)
			local nameMatches = childId == targetId or getPackageBase(child.Name) == targetId
			local versionMatches = targetVersion == "" or childVersion == targetVersion
			if nameMatches and versionMatches then
				child:Destroy()
				removed = true
			end
		end
	end

	for _, child in ipairs(packages:GetChildren()) do
		if child:IsA("ModuleScript") then
			local childId = tostring(child:GetAttribute("loomPackageIdentifier") or "")
			if childId == targetId or child.Name == targetId then
				child:Destroy()
				removed = true
			end
		end
	end

	return removed
end

PackageModule.linkAllLocalDependencies = function(realm)
	local p = find_packages(realm)
	if not p then
		return
	end
	local index = p:FindFirstChild("_Index")
	if not index then
		return
	end

	for _, sourceFolder in ipairs(index:GetChildren()) do
		local wallyTomlModule = sourceFolder:FindFirstChild("wally.toml")
			or sourceFolder:FindFirstChild(".wally")
			or sourceFolder:FindFirstChild("wally")

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
		includeDirectors: boolean?,
	}
)
	local p, index = find_packages(realm)
	local reference = data.reference or getPackageEntryPoint(data.source)

	data.source.Parent = index
	local packageIdentifier = (data.wally and data.wally.package and data.wally.package.name)
		or ((data.creator and data.name) and (tostring(data.creator) .. "/" .. tostring(data.name)))
		or (data.name or data.source.Name)
	setPackageMetadata(
		data.source,
		realm,
		data.wally,
		packageIdentifier,
		(
			data.source.Name:match("@(.+)$")
			or tostring(data.major)
				.. "."
				.. tostring(data.minor)
				.. "."
				.. tostring(data.patch)
		)
	)

	if not p then
		warn(`[PackageModule]: no package folder found for realm "{tostring(realm)}", creating..`)
		p, index = create_packages(nil, realm)
	end

	if data.wally then
		toml_formatter.create(data.wally, data.source)
		if data.includeDirectors ~= false then
			createLocalDependencyDirectors(data.source, data.wally, realm)
		end
	end

	if not reference then
		-- No init/entry point was found (via zip decompression or folder
		-- search). Rather than aborting the import, leave the package
		-- as-is under _Index and skip creating a director (proxy
		-- require) ModuleScript for it, since there's nothing to point to.
		return nil, nil, true
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

	return m, reference, true
end

PackageModule.syncPackage = function(
	realm,
	data: {
		source: Folder,
		wally: { [string]: any },
		name: string?,
		reference: ModuleScript?,
		unpackSrc: boolean?,
		includeDirectors: boolean?,
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

	local reference = data.reference or getPackageEntryPoint(data.source)

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
	local packageIdentifier = (data.wally and data.wally.package and data.wally.package.name)
		or (data.name or data.source.Name)
	setPackageMetadata(
		data.source,
		realm,
		data.wally,
		packageIdentifier,
		(data.source.Name:match("@(.+)$") or "")
	)

	if data.wally then
		toml_formatter.create(data.wally, data.source)
		if data.includeDirectors ~= false then
			createLocalDependencyDirectors(data.source, data.wally, realm)
		end
	end

	if not reference then
		-- No init/entry point was found (via zip decompression or folder
		-- search). Rather than aborting the import, leave the package
		-- as-is under _Index and skip creating a director (proxy
		-- require) ModuleScript for it, since there's nothing to point to.
		return nil, nil, true
	end

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
			rawDetails = descFormat:format(data.source.Name, desc, "License: " .. license)
		else
			rawDetails = descFormat:format(data.source.Name, desc or "License: " .. license)
		end
	end
	m.Source = ([[%s
return require("%s")]]):format(rawDetails, getPathTo(m, reference))

	return m, reference, true
end

return PackageModule
