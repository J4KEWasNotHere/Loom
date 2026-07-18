-- VersionControl-0.5

--!native

local importRbx = require("@self/.import")
local types = require("@self/types")

local module = {
	RegContent = {},
	Versions = {},
} :: types.VersionControl
module.__index = module

-- Services
local HttpService = game:GetService("HttpService")

-- Modules
local toml_formatter = require("../files/.toml-formatter")
local zzlib = require("../../Packages/ZZLib")
local zipBuild = require("../files/.zip-build")

-- Variables
local RegistryUrl = "https://cdn.jsdelivr.net/gh/J4KEWasNotHere/Loom@main/common/registry.toml"
local GitHubArchiveUrls = {
	"https://codeload.github.com/J4KEWasNotHere/Loom/zip/refs/heads/main",
	"https://github.com/J4KEWasNotHere/Loom/archive/refs/heads/main.zip",
}
local WallyTomlUrls = {
	"https://raw.githubusercontent.com/J4KEWasNotHere/Loom/main/wally.toml",
	"https://cdn.jsdelivr.net/gh/J4KEWasNotHere/Loom@main/wally.toml",
}
local StoredPlugins = {}

-- Utility

local function stripQuotes(v: string): string
	return (v:gsub('^"(.*)"$', "%1"))
end

local function getOrderedVersions(vers: { [string]: any }): { string }
	local versions = {}
	for k in pairs(vers) do
		table.insert(versions, k)
	end
	table.sort(versions, function(a, b)
		local function split(v): (number, number, number)
			local major, minor, patch = stripQuotes(tostring(v)):match("^(%d+)%.(%d+)%.(%d+)")
			return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
		end

		local aMaj, aMin, aPat = split(a)
		local bMaj, bMin, bPat = split(b)
		if aMaj ~= bMaj then
			return aMaj > bMaj
		end
		if aMin ~= bMin then
			return aMin > bMin
		end
		return aPat > bPat
	end)
	return versions
end

-- Module API

function module.waitFor(timeout: number?, func: (...any) -> ...any, ...): ...any
	local startTime = os.clock()
	local result = {}
	local args = { ... }
	local done = false

	task.spawn(function()
		result = { table.pack(func(table.unpack(args))) }
		done = true
	end)

	local maxTimeout = tonumber(timeout) or math.huge
	while not done and (os.clock() - startTime) < maxTimeout do
		task.wait()
	end

	if not done then
		warn(`[VersionControl]: Timed out waiting for {func}`)
	end

	return #result > 0 and table.unpack(result) or nil
end

local function getScriptName(name: string): string?
	local normalized = tostring(name or "")
	if normalized == "" then
		return nil
	end

	if not normalized:match("%.lua$") then
		return nil
	end

	local scriptName = normalized:gsub("%.lua$", "")
	if scriptName == "" then
		return nil
	end

	return scriptName
end

local function createPluginScript(
	parent: Instance,
	name: string,
	source: string
): (BaseScript | ModuleScript)?
	local scriptName = getScriptName(name)
	if not scriptName then
		return nil
	end

	local scriptType = "ModuleScript"
	if name:match("%.server%.lua$") then
		scriptType = "Script"
	elseif name:match("%.client%.lua$") then
		scriptType = "LocalScript"
	end

	local scriptObject: BaseScript | ModuleScript = Instance.new(scriptType)
	scriptObject.Name = scriptName
	scriptObject.Source = source or ""
	scriptObject.Parent = parent

	return scriptObject
end

local function tryGetUrl(url: string): (boolean, string)
	local candidates = { url }

	if url:match("^https://raw.githubusercontent.com/") then
		local mirror = url:gsub(
			"^https://raw.githubusercontent.com/([^/]+)/([^/]+)/(.+)$",
			"https://cdn.jsdelivr.net/gh/%1/%2@main/%3"
		)
		table.insert(candidates, mirror)
	elseif url:match("^https://api.github.com/") then
		local mirror = url:gsub(
			"^https://api.github.com/repos/([^/]+)/([^/]+)/contents",
			"https://cdn.jsdelivr.net/gh/%1/%2@main"
		)
		table.insert(candidates, mirror)
	end

	for _, candidate in ipairs(candidates) do
		local success, result = pcall(function()
			return HttpService:GetAsync(candidate, false)
		end)
		if success and tostring(result or "") ~= "" then
			return true, tostring(result)
		end
	end

	return false, "fetch failed"
end

-- zzlib.files() assumes the End Of Central Directory record sits in the
-- last 22 bytes of the buffer (i.e. zero-length comment). GitHub's
-- codeload archives always append the commit SHA as a ~40-byte EOCD
-- comment, which breaks that assumption and makes zzlib throw
-- ".ZIP file comments not supported". Scan backward for the real EOCD
-- signature and trim the comment off so zzlib sees what it expects.
local function stripZipComment(buf: string): string
	local sig = "PK\5\6"
	local maxCommentLen = 65535 -- comment length field is 16 bits
	local searchFrom = math.max(1, #buf - 22 - maxCommentLen)

	for i = #buf - 21, searchFrom, -1 do
		if buf:sub(i, i + 3) == sig then
			local commentLen = string.byte(buf, i + 20) + string.byte(buf, i + 21) * 256
			if i + 21 + commentLen == #buf then
				return buf:sub(1, i + 21)
			end
		end
	end

	return buf
end

local function tryGetGitHubArchive(): (boolean, string)
	local lastErr = "archive fetch failed"

	for _, candidate in ipairs(GitHubArchiveUrls) do
		local ok, response = pcall(function()
			return HttpService:RequestAsync({
				Url = candidate,
				Method = "GET",
			})
		end)

		if
			ok
			and response.Success
			and response.StatusCode == 200
			and tostring(response.Body or "") ~= ""
		then
			return true, stripZipComment(response.Body)
		end

		if ok then
			lastErr = ("archive fetch failed (%d %s)"):format(
				response.StatusCode,
				response.StatusMessage or ""
			)
		else
			lastErr = tostring(response)
		end
	end

	return false, lastErr
end

local function createFolder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function extractArchivePath(
	parent: Instance,
	archiveContent: string,
	targetPath: string?
): (boolean, string?)
	if #archiveContent < 22 or archiveContent:sub(1, 2) ~= "PK" then
		return false, ("not a zip archive (got %d bytes)"):format(#archiveContent)
	end

	local entries = {}
	local ok = pcall(function()
		for _, name in zzlib.files(archiveContent) do
			table.insert(entries, tostring(name))
		end
	end)
	if not ok then
		return false, "invalid archive"
	end

	local normalizedTarget = tostring(targetPath or ""):gsub("\\", "/"):gsub("^%./", "")
	normalizedTarget = normalizedTarget:gsub("/$", "")

	for _, entryName in ipairs(entries) do
		local normalizedEntry = entryName:gsub("\\", "/")
		local withoutRoot = normalizedEntry
		if withoutRoot:match("^[^/]+/") then
			withoutRoot = withoutRoot:gsub("^[^/]+/", "", 1)
		end

		local relPath: string = withoutRoot
		if normalizedTarget ~= "" then
			local prefix = normalizedTarget .. "/"
			if relPath == normalizedTarget then
				relPath = ""
			elseif relPath:sub(1, #prefix) == prefix then
				relPath = relPath:sub(#prefix + 1)
			else
				relPath = ""
			end
		end

		if relPath == nil or relPath == "" then
			continue
		end

		local parts = {}
		for part in relPath:gmatch("([^/]+)") do
			table.insert(parts, part)
		end
		if #parts == 0 then
			continue
		end

		local currentParent = parent
		for i = 1, #parts - 1 do
			currentParent = createFolder(currentParent, parts[i])
		end

		local fileName = parts[#parts]
		local content = nil
		for _, name, offset, size, packed, crc in zzlib.files(archiveContent) do
			if tostring(name) == entryName then
				if packed then
					local ok2, result = pcall(function()
						return zzlib.unzip(archiveContent, offset, crc)
					end)
					if ok2 then
						content = result
					end
				else
					content = archiveContent:sub(offset, offset + size - 1)
				end
				break
			end
		end

		if content == nil then
			continue
		end

		local created = createPluginScript(currentParent, fileName, tostring(content))
		if created == nil then
			-- skip non-Luau files and directories
			continue
		end
	end

	return true, nil
end

--[[
	extractArchivePath mirrors the zip's raw file layout 1:1: a folder that
	contains an "init.lua" stays a Folder with a script literally named
	"init" inside it, instead of becoming Rojo's usual "folder + init.lua"
	shape - a single script named after the folder, with everything else
	that lived in the folder as ITS children rather than its siblings.
	That matters here because requires like `require("@self/types")` only
	resolve `types` as a child of the init script itself.

	resolveNested walks `root` and fixes every such folder, bottom-up so
	nested folders collapse correctly. `exclude` is a set of child names
	(matched at every level) to leave untouched entirely - e.g. "Packages",
	whose layout is intentionally managed by the package installer instead.
]]
local function resolveNested(root: Instance, exclude: { [string]: boolean }?)
	local function resolve(instance: Instance)
		for _, child in ipairs(instance:GetChildren()) do
			if child:IsA("Folder") and not (exclude and exclude[child.Name]) then
				resolve(child)
			end
		end

		if not instance:IsA("Folder") then
			return
		end

		local initScript = instance:FindFirstChild("init")
		if not (initScript and initScript:IsA("LuaSourceContainer")) then
			return
		end

		local folderName = instance.Name
		local parent = instance.Parent
		if not parent then
			return
		end

		for _, sibling in ipairs(instance:GetChildren()) do
			if sibling ~= initScript then
				sibling.Parent = initScript
			end
		end

		initScript.Name = folderName
		initScript.Parent = parent
		instance:Destroy()
	end

	for _, child in ipairs(root:GetChildren()) do
		if not (exclude and exclude[child.Name]) then
			resolve(child)
		end
	end
end

local function cloneSourceTree(sourceParent: Instance, targetParent: Instance)
	for _, child in ipairs(sourceParent:GetChildren()) do
		local clone
		if child:IsA("Folder") or child:IsA("Model") then
			clone = Instance.new(child.ClassName)
			clone.Name = child.Name
			clone.Parent = targetParent
			cloneSourceTree(child, clone)
		elseif child:IsA("LuaSourceContainer") or child:IsA("BaseScript") then
			clone = Instance.new(child.ClassName)
			clone.Name = child.Name
			clone.Source = child.Source
			clone.Disabled = child.Disabled
			clone.Parent = targetParent
		else
			clone = Instance.new(child.ClassName)
			clone.Name = child.Name
			clone.Parent = targetParent
		end

		for name, value in pairs(child:GetAttributes()) do
			clone:SetAttribute(name, value)
		end
	end
end

local function buildPluginTreeFromGitHub(parent: Instance, path: string): (boolean, any)
	local archiveOk, archiveContent = tryGetGitHubArchive()
	if not archiveOk then
		return false, archiveContent
	end

	local success, err = extractArchivePath(parent, archiveContent, path)
	if not success then
		return false, err
	end

	return true
end

module.resolveNested = resolveNested

-- detaches the plugin entirely and reloads it.
function module.embed(newPlugin: Instance, pluginRoot: Instance, cleanup: (() -> ())?)
	if not newPlugin or not pluginRoot then
		warn(`[VersionControl]: embed called with nil args`)
		return false
	end

	if typeof(cleanup) == "function" then
		pcall(cleanup)
	end

	local oldEntry
	for _, child in ipairs(pluginRoot:GetChildren()) do
		if child:IsA("LuaSourceContainer") and not child:IsA("ModuleScript") then
			oldEntry = child
			break
		end
	end

	if oldEntry then
		pcall(function()
			oldEntry.Disabled = true
		end)
	end

	local stash = Instance.new("Folder")
	stash.Name = "__loom_stash__"
	stash.Parent = game:GetService("ServerStorage")

	for _, child in ipairs(pluginRoot:GetChildren()) do
		child.Parent = stash
	end

	local newEntry
	for _, child in ipairs(newPlugin:GetChildren()) do
		if child:IsA("BaseScript") and not child:IsA("ModuleScript") then
			newEntry = child
			child.Disabled = true
		end
		child.Parent = pluginRoot
	end

	if not newEntry then
		warn(`[VersionControl]: No entry script found in new plugin`)
		for _, child in ipairs(stash:GetChildren()) do
			child.Parent = pluginRoot
		end
		stash:Destroy()
		return false
	end

	task.defer(function()
		stash:Destroy()
		task.wait()
		warn(`[VersionControl]: Restarting plugin..`)
		pluginRoot:SetAttribute("__needsRestart", true)
	end)

	return true
end

-- Reads the repo's own wally.toml and turns [dependencies] /
-- [server-dependencies] / [dev-dependencies] into the same entry shape
-- InstallService already knows how to consume (see zip-build.lua's
-- getDependenciesFromToml, which this reuses directly).
function module.getGitHubWallyDependencies(): (boolean, { any } | string)
	local ok, raw = tryGetUrl(WallyTomlUrls[1])
	if not ok then
		for i = 2, #WallyTomlUrls do
			ok, raw = tryGetUrl(WallyTomlUrls[i])
			if ok then
				break
			end
		end
	end
	if not ok then
		return false, raw
	end

	local parseOk, toml = pcall(toml_formatter.format, raw)
	if not parseOk or typeof(toml) ~= "table" then
		return false, "failed to parse wally.toml"
	end

	return true, zipBuild.getDependenciesFromToml(toml)
end

-- Installs the plugin's own wally.toml dependencies through the normal
-- InstallService pipeline (registry lookup + package-instancer), the
-- same code path used for a manual package install or a .zip import.
--
-- This replaces the old approach of extracting the repo's prebuilt
-- Packages folder straight out of the GitHub zip: that extraction only
-- turned .lua files into scripts, so every dependency lost its own
-- wally.toml (and any non-.lua files) along the way - Loom had no way
-- to tell what was installed afterwards, and installs into Packages
-- silently produced folders with none of the [[dependencies]] metadata
-- attached, which is presumably why they wouldn't get picked up.
-- `parent`, if provided, is an Instance (e.g. the plugin's own root, or a
-- folder the user selected) that packages are installed directly under -
-- resolveRealm/find_packages never look outside it, so this never touches
-- ReplicatedStorage/ServerScriptService and never risks picking up
-- unrelated packages that happen to already live there.
function module.installPackagesFromGitHub(
	installService,
	onProgress: ((number, number, string) -> ())?,
	parent: Instance?
): (boolean, number | string, { string }?)
	if not installService then
		return false, "installService is required to install packages from wally.toml"
	end

	local ok, deps = module.getGitHubWallyDependencies()
	if not ok then
		return false, deps :: string
	end

	deps = deps :: { any }
	if #deps == 0 then
		return true, 0, {}
	end

	local installedCount, failed =
		installService:installDependencies(deps, { parent = parent }, onProgress or function() end)

	return true, installedCount, failed
end

function module.recreateFromGitHub(
	pluginRoot: Instance,
	installService,
	cleanup: (() -> ())?,
	packagesParent: Instance?
)
	if not pluginRoot then
		return false, "missing plugin root"
	end

	local sourcePlugin = Instance.new("Folder")
	sourcePlugin.Name = "__loom_github_source__"

	local ok, err =
		buildPluginTreeFromGitHub(sourcePlugin, "src/ReplicatedStorage/J4KEWasNotHere_loom")
	if not ok then
		sourcePlugin:Destroy()
		return false, err
	end

	-- Fix up the raw zip-mirrored tree into proper folder+init modules
	-- before anything else touches it. "Packages" is excluded since it
	-- doesn't exist yet at this point anyway, and installPackagesFromGitHub
	-- below builds it directly with the correct layout regardless.
	resolveNested(sourcePlugin, { Packages = true })

	if installService then
		-- Default to sourcePlugin itself: embed() below stashes and destroys
		-- everything currently in pluginRoot, so installing packages there
		-- (or leaving them in ReplicatedStorage) would just lose them. They
		-- need to already be inside the tree that's about to become the
		-- live plugin.
		local packagesOk, installedOrErr, failed =
			module.installPackagesFromGitHub(installService, nil, packagesParent or sourcePlugin)
		if not packagesOk then
			warn(`[VersionControl]: Failed to install packages from wally.toml: {installedOrErr}`)
		elseif failed and #failed > 0 then
			warn(
				`[VersionControl]: {#failed} package(s) failed to install: {table.concat(
					failed,
					", "
				)}`
			)
		end
	else
		warn(`[VersionControl]: No installService provided - skipping package install`)
	end

	return module.embed(sourcePlugin, pluginRoot, cleanup)
end

function module.install(ver: string?)
	local ordered = getOrderedVersions(module.Versions)
	local cleanVer = typeof(ver) == "string" and stripQuotes(ver) or nil
	local resolvedVer = (cleanVer and module.Versions[cleanVer] ~= nil) and cleanVer
		or ordered[#ordered]

	if not resolvedVer then
		return false, "no versions available"
	end

	if StoredPlugins[resolvedVer] then
		return true, StoredPlugins[resolvedVer]
	end

	local url = module.RegContent["versions"][resolvedVer].ref
	local success, content = pcall(function()
		return HttpService:GetAsync(url, false)
	end)

	if not success then
		return false, content
	end

	local importSuccess, results = importRbx(content, script)
	local _plugin = (importSuccess and typeof(results) == "table") and results[1] or nil

	if _plugin then
		StoredPlugins[resolvedVer] = _plugin
		return true, _plugin
	else
		return false, results
	end
end

function module.rinstall(ver: string?, max: number?)
	local ordered = getOrderedVersions(module.Versions)
	local cleanVer = typeof(ver) == "string" and stripQuotes(ver) or nil
	local resolvedVer = (cleanVer and module.Versions[cleanVer] ~= nil) and cleanVer
		or ordered[#ordered]

	local success, result = false, nil
	local count, maxCount = 0, tonumber(max) or math.huge

	while not success and count < maxCount do
		success, result = module.install(resolvedVer)
		count += 1
		if not success then
			warn(
				`[{script.Name}]: Failed to install version-{resolvedVer}, retrying... ({result or "?"})`
			)
			task.wait(1)
		end
	end

	return success, result
end

function module.init(): (boolean, { [string]: any } | any)
	local success, result = tryGetUrl(RegistryUrl)
	if not success then
		return false, result
	end

	local toml = toml_formatter.format(result)

	local versions = {}
	for k, v in pairs(toml["versions"] or {}) do
		versions[stripQuotes(tostring(k or ""))] = v
	end
	toml["versions"] = versions

	module.RegContent = toml
	module.Versions = versions

	return true, toml
end

function module.rinit(max: number?): (boolean, { [string]: any }?)
	local success, result = false, nil
	local count, maxCount = 0, tonumber(max) or math.huge

	while not success and count < maxCount do
		success, result = module.init()
		count += 1
		if not success then
			warn(`[{script.Name}]: Failed to fetch registry, retrying... ({result or "?"})`)
			task.wait(1)
		end
	end

	return success, result
end

module.sortVersions = getOrderedVersions
return module
