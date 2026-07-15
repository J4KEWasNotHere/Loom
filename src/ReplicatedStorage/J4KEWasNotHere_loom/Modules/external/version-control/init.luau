-- VersionControl-0.3

--!strict
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
local Modules = script.Parent:FindFirstAncestor("Modules")
local toml_formatter = require(Modules.files[".toml-formatter"])

-- Variables
local RegistryUrl = "https://github.com/J4KEWasNotHere/Loom/raw/refs/heads/main/common/registry.toml"
local GitHubApiBase = "https://api.github.com/repos/J4KEWasNotHere/Loom/contents"
local GitHubRawBase = "https://raw.githubusercontent.com/J4KEWasNotHere/Loom/main"
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

	if not normalized:match("%.lua$") and not normalized:match("%.luau$") then
		return nil
	end

	local scriptName = normalized:gsub("%.lua$", ""):gsub("%.luau$", "")
	if scriptName == "" then
		return nil
	end

	return scriptName
end

local function tryGetUrl(url: string): (boolean, string)
	local headers = {
		["User-Agent"] = "Loom",
		["Accept"] = "application/vnd.github+json",
		["X-GitHub-Api-Version"] = "2022-11-28",
	}

	local success, result = pcall(function()
		return HttpService:GetAsync(url, false, headers)
	end)

	if success then
		return true, tostring(result)
	end

	return false, tostring(result)
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

local function createPluginScript(parent: Instance, name: string, source: string)
	local scriptName = getScriptName(name)
	if not scriptName then
		return nil
	end

	local scriptType = "ModuleScript"
	if name:match("%.server%.lua$") or name:match("%.server%.luau$") then
		scriptType = "Script"
	elseif name:match("%.client%.lua$") or name:match("%.client%.luau$") then
		scriptType = "LocalScript"
	end

	local script = Instance.new(scriptType)
	script.Name = scriptName
	script.Source = source or ""
	script.Parent = parent
	return script
end

local function buildPluginTreeFromGitHub(parent: Instance, path: string): (boolean, any)
	local encodedPath = path:gsub(" ", "%%20")
	local success, result = tryGetUrl(("%s/%s"):format(GitHubApiBase, encodedPath))

	if not success then
		return false, result
	end

	local decoded
	local ok, parsed = pcall(function()
		return HttpService:JSONDecode(tostring(result))
	end)
	if ok then
		decoded = parsed
	end

	if type(decoded) ~= "table" then
		return false, "invalid GitHub response"
	end

	if decoded.download_url then
		local contentOk, content = tryGetUrl(tostring(decoded.download_url))
		if not contentOk then
			return false, content
		end
		local created = createPluginScript(parent, tostring(decoded.name or path:match("([^/]+)$")), tostring(content))
		if created == nil then
			return true
		end
		return true
	end

	local entries = decoded
	if type(entries) ~= "table" then
		return false, "invalid GitHub directory listing"
	end

	for _, entry in ipairs(entries) do
		if type(entry) == "table" and entry.name then
			local childName = tostring(entry.name)
			local childPath = (path ~= "") and (path .. "/" .. childName) or childName
			if entry.type == "dir" then
				local folder = Instance.new("Folder")
				folder.Name = childName
				folder.Parent = parent
				local treeOk, err = buildPluginTreeFromGitHub(folder, childPath)
				if not treeOk then
					return false, err
				end
			elseif entry.type == "file" then
				local contentOk, content = tryGetUrl(("%s/%s"):format(GitHubRawBase, childPath:gsub(" ", "%%20")))
				if not contentOk then
					return false, content
				end
				createPluginScript(parent, childName, tostring(content))
			end
		end
	end

	return true
end

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

function module.recreateFromGitHub(pluginRoot: Instance, cleanup: (() -> ())?)
	if not pluginRoot then
		return false, "missing plugin root"
	end

	local sourcePlugin = Instance.new("Folder")
	sourcePlugin.Name = "__loom_github_source__"

	local ok, err = buildPluginTreeFromGitHub(sourcePlugin, "src/ReplicatedStorage/J4KEWasNotHere_loom")
	if not ok then
		sourcePlugin:Destroy()
		return false, err
	end

	local packagesFolder = Instance.new("Folder")
	packagesFolder.Name = "Packages"
	packagesFolder.Parent = sourcePlugin

	local packagesOk, packagesErr = buildPluginTreeFromGitHub(packagesFolder, "Packages")
	if not packagesOk then
		sourcePlugin:Destroy()
		return false, packagesErr
	end

	return module.embed(sourcePlugin, pluginRoot, cleanup)
end

function module.install(ver: string?)
	local ordered = getOrderedVersions(module.Versions)
	local cleanVer = typeof(ver) == "string" and stripQuotes(ver) or nil
	local resolvedVer = (cleanVer and module.Versions[cleanVer] ~= nil) and cleanVer or ordered[#ordered]

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
	local resolvedVer = (cleanVer and module.Versions[cleanVer] ~= nil) and cleanVer or ordered[#ordered]

	local success, result = false, nil
	local count, maxCount = 0, tonumber(max) or math.huge

	while not success and count < maxCount do
		success, result = module.install(resolvedVer)
		count += 1
		if not success then
			warn(`[{script.Name}]: Failed to install version-{resolvedVer}, retrying... ({result or "?"})`)
			task.wait(1)
		end
	end

	return success, result
end

function module.init(): (boolean, { [string]: any } | any)
	local success, result = pcall(function()
		return HttpService:GetAsync(RegistryUrl, true)
	end)

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

function module.rinit(max: number?): (boolean, { [string]: any }? | any)
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
