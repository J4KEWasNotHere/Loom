local Modules = script.Parent.Parent
local zipBuild = require(Modules.files[".zip-build"])
local packageInstancer = require(Modules.common["package-instancer"])
local wallySearch = require(Modules.external["wally-search"])

local InstallService = {}
InstallService.__index = InstallService

-- Utility

local function splitName(name)
	local scopePackage, version = name:match("^(.-)@(.+)$")
	if not scopePackage then
		scopePackage = name
	end
	local scope, package = scopePackage:match("^([^/]+)/([^/]+)$")
	if not scope then
		return nil, scopePackage, version
	end
	return scope, package, version
end

local function normalizeDependencyEntries(dependencies, includeDev, debugFn)
	local entries = {}
	local seen = {}
	for _, dep in ipairs(dependencies or {}) do
		if dep.realm ~= "dev" or includeDev then
			local scope, pkg, requirement = dep.specifier:match("^([^/]+)/([^@]+)@(.+)$")
			if scope and pkg and requirement then
				-- resolve "^1", "1.2.0", "=1.2.0" etc into a concrete version (see §3)
				local ok, resolved = wallySearch.resolveVersion(scope, pkg, requirement)
				local version = ok and resolved or requirement
				if not ok and debugFn then
					debugFn(
						`[{os.date("%H:%M:%S")}-install]: Could not resolve "{requirement}" for {scope}/{pkg}`
					)
				end

				local key = ("%s/%s@%s"):format(scope, pkg, version)
				if not seen[key] then
					seen[key] = true
					table.insert(entries, {
						scope = scope,
						package = pkg,
						version = version,
						label = dep.name,
						realm = dep.realm or "shared",
					})
				end
			end
		end
	end
	return entries
end

-- Module API

function InstallService.new(settingsService)
	return setmetatable({
		settings = settingsService,
		_callbacks = {},
	}, InstallService)
end

function InstallService:bindDebugCallback(callback)
	table.insert(self._callbacks, callback)
end

function InstallService:debug(message)
	for _, callback in self._callbacks do
		task.spawn(callback, message)
	end
end

function InstallService:installDependencies(dependencyData, options, onProgress)
	local workQueue = normalizeDependencyEntries(
		dependencyData,
		self.settings:get("includeDev", false),
		function(msg)
			self:debug(msg)
		end
	)

	local seen = {}
	for _, entry in ipairs(workQueue) do
		seen[("%s/%s@%s"):format(entry.scope, entry.package, entry.version)] = true
	end
	local failed = {}
	local installedCount = 0

	local includeDirs = self.settings:get("includeDirectors", true)

	local idx = 0
	while idx < #workQueue do
		idx += 1
		local entry = workQueue[idx]
		onProgress(idx, #workQueue, entry.label)
		local ok, result = self:installPackage(entry, {
			includeDependencies = true,
			unpackSrc = options.unpackSrc == true,
			includeDirs = includeDirs,
		})

		if not ok then
			table.insert(failed, entry.label)
		else
			installedCount += 1
			for _, dep in ipairs(result or {}) do
				local depKey = ("%s/%s@%s"):format(dep.scope, dep.package, dep.version)
				if not seen[depKey] then
					seen[depKey] = true
					table.insert(workQueue, dep)
				end
			end
		end
		task.wait()
	end

	if includeDirs then
		packageInstancer.linkAllLocalDependencies("shared")
		packageInstancer.linkAllLocalDependencies("server")
		packageInstancer.linkAllLocalDependencies("dev")
	end

	return installedCount, failed
end

function InstallService:syncFromRaw(raw, pkgLabel, options, dependencyRealm)
	local safeName = pkgLabel:gsub("/", "_")
	local sourceFolder, initModule, wallyData, dependencies = zipBuild.createFromRaw(raw, safeName)
	if not wallyData then
		warn(("[Loom]: wally.toml not found or failed to parse for %s"):format(pkgLabel))
		self:debug(
			`[{os.date("%H:%M:%S")}-install]: wally.toml not found or failed to parse for {pkgLabel}`
		)
		return false, "wally.toml not found or parsing error?"
	end

	options = typeof(options) == "table" and options or {}

	local realm = (dependencyRealm == "dev") and "dev"
		or ((wallyData.package and wallyData.package.realm) or "shared")
	local includeDirs = self.settings:get("includeDirectors", true)

	packageInstancer.syncPackage(realm, {
		source = sourceFolder,
		reference = initModule,
		name = pkgLabel,
		unpackSrc = options.unpackSrc == true,
		includeDirectors = includeDirs,
		wally = wallyData,
	})

	return true, dependencies
end

function InstallService:installPackage(entry, options)
	if not entry.scope or not entry.package or not entry.version then
		self:debug(
			`[{os.date("%H:%M:%S")}-install]: Missing package information ({entry.scope or entry.label or entry.package})`
		)
		return false, "Missing package information"
	end

	if entry.reference and entry.existingSource then
		local realm = entry.realm or "shared"
		local includeDirs = self.settings:get("includeDirectors", true)

		local wallyModule = entry.existingSource:FindFirstChild("wally.toml")
		local wallyData = nil
		if wallyModule and wallyModule:IsA("ModuleScript") then
			local parseOk, parsed = pcall(require, wallyModule)
			if parseOk and typeof(parsed) == "table" then
				wallyData = parsed
			end
		end

		packageInstancer.syncPackage(realm, {
			source = entry.existingSource,
			reference = entry.reference,
			name = entry.label or (entry.scope .. "/" .. entry.package),
			unpackSrc = options.unpackSrc == true,
			includeDirectors = includeDirs,
			wally = wallyData,
		})

		self:debug(
			`[{os.date("%H:%M:%S")}-install]: Linked already-installed package ({entry.label or entry.package})`
		)

		return true, {}
	end

	local ok, raw = wallySearch.getPackageZipRaw(entry.scope, entry.package, entry.version)
	if not ok or not raw then
		if typeof(raw) == "table" and raw.Body then
			local body = raw.Body:gsub("<[^<>]->", "")
			local success, parsed = pcall(function()
				return game.HttpService:JSONDecode(body)
			end)
			if success and parsed.Message then
				body = parsed.Message
			end
			warn(
				`[Loom-http]: {body}{raw.StatusCode == 426 and " || Wally Version is outdated?" or ""}`
			)
		end
		self:debug(
			`[{os.date("%H:%M:%S")}-install]: Failed to download package ({entry.label or entry.package}) ; {raw}`
		)
		return false, "Failed to download package"
	end

	local installed, dependencies = self:syncFromRaw(
		raw,
		entry.label or (entry.scope .. "/" .. entry.package),
		options,
		entry.realm
	)
	if not installed then
		self:debug(
			`[{os.date("%H:%M:%S")}-install]: Failed to import package ({entry.label or entry.package}) ; {dependencies}`
		)
		return false, "Failed to import package"
	end

	local nextEntries = {}
	if options.includeDependencies and dependencies then
		for _, dep in
			ipairs(
				normalizeDependencyEntries(
					dependencies,
					self.settings:get("includeDev", false),
					function(msg)
						self:debug(msg)
					end
				)
			)
		do
			table.insert(nextEntries, dep)
		end
	end

	return true, nextEntries
end

function InstallService:installQueue(queue, onProgress)
	local workQueue = {}
	local seen = {}
	local failed = {}
	local installedCount = 0

	for _, entry in ipairs(queue) do
		local scope, package, version = entry.scope, entry.package, entry.version
		local key = ("%s/%s@%s"):format(scope or "", package or "", version or "")

		if scope and package and version and not seen[key] then
			seen[key] = true

			-- Compute the custom display label. If an override name is provided,
			-- make sure it maintains the "author/override" format.
			local customLabel = entry.raw or entry.name or (scope .. "/" .. package)
			if entry.name and entry.name ~= "" then
				if not entry.name:find("/") then
					customLabel = scope .. "/" .. entry.name
				else
					customLabel = entry.name
				end
			end

			table.insert(workQueue, {
				scope = scope,
				package = package,
				version = version,
				label = customLabel,
				includeDependencies = entry.includeDependencies ~= false,
				reference = entry.reference,
				existingSource = entry.existingSource,
				realm = entry.realm,
			})
		end
	end

	local unpackSrc = self.settings:get("unpackSrc", true)
	local includeDirs = self.settings:get("includeDirectors", true)

	local idx = 0
	while idx < #workQueue do
		idx += 1
		local entry = workQueue[idx]
		onProgress(idx, #workQueue, entry.label)
		local ok, result = self:installPackage(entry, {
			includeDependencies = entry.includeDependencies ~= false,
			unpackSrc = unpackSrc,
		})

		if not ok then
			table.insert(failed, entry.label)
		else
			installedCount += 1
			for _, dep in ipairs(result or {}) do
				local depKey = ("%s/%s@%s"):format(dep.scope, dep.package, dep.version)
				if not seen[depKey] then
					seen[depKey] = true
					table.insert(workQueue, dep)
				end
			end
		end
		task.wait()
	end

	if includeDirs then
		packageInstancer.linkAllLocalDependencies("shared")
		packageInstancer.linkAllLocalDependencies("server")
		packageInstancer.linkAllLocalDependencies("dev")
	end

	return installedCount, failed
end

return InstallService
