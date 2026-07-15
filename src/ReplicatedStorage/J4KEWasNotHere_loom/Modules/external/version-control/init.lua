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

	local success, results = importRbx(content, script)
	local _plugin = (success and typeof(results) == "table") and results[1] or nil

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
