--[[
	package-utils.lua

	Small, dependency-free helpers for working with package names and
	the install queue. Split out of plugin-basis.lua so pages can share
	them without pulling in Fusion/UI code.
]]

local PackageUtils = {}

function PackageUtils.splitName(name: string): (string?, string, string?)
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

function PackageUtils.cloneQueue(queue)
	local copy = {}
	for _, entry in ipairs(queue or {}) do
		table.insert(copy, {
			raw = entry.raw or "",
			scope = entry.scope,
			package = entry.package,
			version = entry.version,
			name = entry.name or "",
			includeDependencies = entry.includeDependencies ~= false,
			_depsValue = entry._depsValue,
			reference = entry.reference,
			existingSource = entry.existingSource,
			realm = entry.realm,
		})
	end
	return copy
end

function PackageUtils.makeEntryLabel(entry): string
	local label = entry.raw or ""
	if entry.version and entry.version ~= "" then
		label = label .. " @" .. entry.version
	end
	return label
end

return PackageUtils
